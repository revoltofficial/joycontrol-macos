//
//  BluetoothManager.swift
//  joycontrol-macos
//
//  Created by Joey Jacobs on 2/15/21.
//
import BluetoothDarwin
import BluetoothHCI
import CBluetoothDarwin
import Foundation
import Darwin
import IOBluetooth
import IOBluetoothUI
import os.log
import SwiftUI

class NintendoSwitchBluetoothManager: NSObject, IOBluetoothL2CAPChannelDelegate, ObservableObject, IOBluetoothHostControllerDelegate, ControllerProtocolDelgate {
    private static let deviceName = Controller.proController.name
    private static let controlPsm = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDControl)
    private static let interruptPsm = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDInterrupt)
    static let shared = NintendoSwitchBluetoothManager()
    private static let hostController = IOBluetoothHostController()
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    private var controlChannelOutgoing: IOBluetoothL2CAPChannel?
    private var interruptChannelOutgoing: IOBluetoothL2CAPChannel?
    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var hostAddress: BluetoothAddress?
    private let logger = Logger()
    private var controllerProtocol: ControllerProtocol?
    private var nintendoSwitch: IOBluetoothDevice?
    @Published var pairingStatus = "Ready to prepare controller."
    private var channelNotifications: [IOBluetoothUserNotification] = []
    @objc @Published var deviceAddress: String = ""
    private var connected: Bool = false
    @objc @Published var readyForInput: Bool = false

    var isScanEnabled: Bool {
        Self.hostController.isScanEnable()
    }

    override private init() {
        super.init()
        Self.hostController.delegate = self
    }

    func setScanEnabled(enabled: Bool) throws {
        if enabled {
            try configureHostControllerForNintendoSwitch()
            pairingStatus = "Controller service ready. Open Change Grip/Order on Switch; if it stays empty, use Pair using macOS."
            // The system picker handles discoverability. Raw scan HCI commands
            // are unsupported on current macOS and are no longer sent.
        } else {
            channelNotifications.forEach { $0.unregister() }
            channelNotifications.removeAll()
            serviceRecord?.remove()
            serviceRecord = nil
            pairingStatus = "Controller service stopped."
        }
    }

    func pairUsingMacOS() throws {
        guard let picker = IOBluetoothDeviceSelectorController.deviceSelector() else {
            throw ApplicationError.general("macOS could not open its Bluetooth device selector.")
        }
        try configureHostControllerForNintendoSwitch()
        picker.setTitle("Pair with Nintendo Switch")
        picker.setHeader("Keep the Switch on Change Grip/Order.")
        picker.setDescriptionText("Choose the Switch if it appears. This step uses macOS Bluetooth pairing.")
        pairingStatus = "Waiting for a selection in the macOS pairing window."
        guard picker.runModal() == kIOBluetoothUISuccess else {
            pairingStatus = "Pairing window closed. Controller service remains ready."
            return
        }
        guard let device = (picker.getResults() as? [IOBluetoothDevice])?.first,
              let address = device.addressString else {
            pairingStatus = "No Bluetooth device was selected."
            return
        }
        deviceAddress = address.replacingOccurrences(of: "-", with: ":")
        pairingStatus = "Device selected. Press Connect to start the controller connection."
    }

    func controllerProtocolConnectionLost() {
        interruptChannel = nil
        controlChannel = nil
        controllerProtocol = nil
        nintendoSwitch = nil
        interruptChannelOutgoing = nil
        controlChannelOutgoing = nil
        readyForInput = false
    }

    private func configureHostControllerForNintendoSwitch() throws {
        guard Self.hostController.powerState == kBluetoothHCIPowerStateON else {
            throw ApplicationError.general("Turn Bluetooth on in System Settings first.")
        }
        if serviceRecord != nil { return }
        guard let rawAddress = Self.hostController.addressAsString(),
              let address = BluetoothAddress(rawValue: rawAddress.replacingOccurrences(of: "-", with: ":").uppercased()) else {
            throw ApplicationError.general("macOS did not provide a local Bluetooth address.")
        }
        hostAddress = address
        guard let path = Bundle.main.path(forResource: "NintendoSwitchControllerSDP", ofType: "plist"),
              let dictionary = NSDictionary(contentsOfFile: path),
              let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: dictionary as! [NSObject: AnyObject]) else {
            throw ApplicationError.general("macOS could not publish the controller service.")
        }
        serviceRecord = record
        for psm in [Self.controlPsm, Self.interruptPsm] {
            guard let notification = IOBluetoothL2CAPChannel.register(
                forChannelOpenNotifications: self,
                selector: #selector(newL2CAPChannelOpened),
                withPSM: psm,
                direction: kIOBluetoothUserNotificationChannelDirectionIncoming) else {
                channelNotifications.forEach { $0.unregister() }
                channelNotifications.removeAll()
                record.remove()
                serviceRecord = nil
                throw ApplicationError.general("macOS could not register the controller connection channels.")
            }
            channelNotifications.append(notification)
        }
        let result = Self.hostController.setClassOfDevice(0x000508, forTimeInterval: 120.0)
        pairingStatus = result == kIOReturnSuccess
            ? "Controller service published and gamepad device class enabled."
            : "Controller service published; macOS rejected the gamepad device class (\(result))."
    }

    private func onBluetoothPoweredOn() {
        pairingStatus = "Bluetooth is on. Enable Allow Pairing to prepare the controller."
    }

    private func onBluetoothPoweredOff() {}

    func connectNintendoSwitch(_ address: String) {
        do { try configureHostControllerForNintendoSwitch() }
        catch { pairingStatus = String(describing: error); return }
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: ":")
        guard BluetoothAddress(rawValue: normalized.uppercased()) != nil,
              let device = IOBluetoothDevice(addressString: normalized) else {
            pairingStatus = "Choose a device with Pair using macOS before pressing Connect."
            return
        }
        nintendoSwitch = device
        let aclStatus = device.openConnection()
        guard aclStatus == kIOReturnSuccess else {
            pairingStatus = "Bluetooth connection failed: \(aclStatus)"
            return
        }
        let controlStatus = device.openL2CAPChannelSync(&controlChannelOutgoing, withPSM: Self.controlPsm, delegate: self)
        guard controlStatus == kIOReturnSuccess else {
            pairingStatus = "Controller control channel failed: \(controlStatus)"
            device.closeConnection()
            return
        }
        let interruptStatus = device.openL2CAPChannelSync(&interruptChannelOutgoing, withPSM: Self.interruptPsm, delegate: self)
        guard interruptStatus == kIOReturnSuccess else {
            pairingStatus = "Controller interrupt channel failed: \(interruptStatus)"
            controlChannelOutgoing?.close()
            device.closeConnection()
            return
        }
    }

    func disconnectNintendoSwitch() {
        logger.debug(#function)
        DispatchQueue.main.async { [self] in
            interruptChannel?.close()
            controlChannel?.close()
            interruptChannelOutgoing?.close()
            controlChannelOutgoing?.close()
            nintendoSwitch?.closeConnection()
        }
    }

    @objc
    func newL2CAPChannelOpened(notification _: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        logger.debug(#function)
        channel.setDelegate(self)
        pairingStatus = "Switch opened a controller channel."
        l2capChannelOpenComplete(channel, status: kIOReturnSuccess)
    }

    func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        if l2capChannel.psm == Self.interruptPsm {
            let data: Bytes = dataPointer.readAsArray(dataLength)

            controllerProtocol?.reportReceived(data)
        } else {
            fatalError("Received data from non-interrupt channel.")
        }
    }

    func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        logger.debug(#function)
        guard error == kIOReturnSuccess else {
            pairingStatus = "Controller channel failed: \(error)"
            logger.error("Channel open failed: \(error)")
            return
        }

        logger.debug("\(l2capChannel.debugDescription)")
        switch l2capChannel.psm {
        case NintendoSwitchBluetoothManager.controlPsm:
            logger.info("Control PSM Channel Connected")
            controlChannel = l2capChannel

        case NintendoSwitchBluetoothManager.interruptPsm:
            logger.info("Interrupt PSM Channel Connected")
            interruptChannel = l2capChannel
            guard let hostAddress = hostAddress else {
                pairingStatus = "Local Bluetooth setup is incomplete. Enable Allow Pairing first."
                return
            }
            pairingStatus = "Connected; waiting for the Switch controller handshake."
            controllerProtocol = ControllerProtocol(spiFlash: FlashMemory.factoryDefault, hostAddress: hostAddress, delegate: self, transport: l2capChannel)
            nintendoSwitch = l2capChannel.device
            deviceAddress = l2capChannel.device.addressString.split(separator: "-").joined(separator: ":")
            DispatchQueue.global(qos: .background).async {
                self.controllerProtocol!.readyToAcceptInput.wait()
                DispatchQueue.main.async {
                    self.readyForInput = true
                    self.pairingStatus = "Controller connected and ready."
                }
            }

        default:
            return
        }
    }

    func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        logger.debug(#function)
        logger.debug("\(l2capChannel.debugDescription)")
        if l2capChannel == interruptChannel {
            if controllerProtocol == nil {
                controllerProtocolConnectionLost()
            } else {
                controllerProtocol!.connectionLost()
            }
        }
    }

    func bluetoothHCIEventNotificationMessage(_ controller: IOBluetoothHostController, in _: IOBluetoothHCIEventNotificationMessageRef) {
        let isConnected = controller.powerState == kBluetoothHCIPowerStateON
        if isConnected != connected {
            logger.debug("Detected powerState change: \(self.connected) -> \(isConnected)")
            connected = isConnected
            if connected {
                onBluetoothPoweredOn()
            } else {
                onBluetoothPoweredOff()
            }
        }
    }

    func controlStickPushed(_ button: ControllerButton, _ direction: StickDirection, durationInMs: Double = 100) {
        switch button {
        case .leftStick:
            controllerProtocol?.controllerState.leftStickState.setPosition(direction, durationInMs: durationInMs)

        case .rightStick:
            controllerProtocol?.controllerState.rightStickState.setPosition(direction, durationInMs: durationInMs)

        default:
            fatalError("Only \(ControllerButton.leftStick) and \(ControllerButton.rightStick) are supported.")
        }
    }

    func controllerButtonPushed(buttons: [ControllerButton], durationInMs: Double = 100) {
        guard controllerProtocol != nil else {
            logger.error("controllerProtocol not initialized")
            return
        }
        logger.debug(#function)
        logger.debug("\(String(describing: buttons))")
        buttonPush(controllerProtocol!.controllerState.buttonState, controllerProtocol!, buttons, sec: durationInMs / 1_000)
    }

    func performQuickAction(quickAction: ControllerQuickAction) {
        logger.info("Perforing Quick Action: \(quickAction.name)...")
        DispatchQueue.global(qos: .background).async { [self] in
            for step in quickAction.steps {
                if !step.buttons.isEmpty {
                    controllerButtonPushed(buttons: step.buttons, durationInMs: Double(step.durationInMs))
                }
                if step.stickAndDirection != nil {
                    controlStickPushed(step.stickAndDirection!.0, step.stickAndDirection!.1, durationInMs: Double(step.durationInMs))
                }
            }
        }
    }

    deinit {
        logger.debug("Removing service record")
        serviceRecord?.remove()
    }
}
