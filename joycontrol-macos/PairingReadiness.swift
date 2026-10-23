import Foundation

struct PairingReadiness {
    let name: String
    let deviceClass: UInt32
    let scanReadStatus: Int32
    let scanMode: UInt8

    var blockers: [String] {
        var result: [String] = []
        if name != "Pro Controller" { result.append("Bluetooth name is not Pro Controller") }
        if deviceClass & 0x1fff != 0x0508 { result.append("gamepad device class is not active") }
        if scanReadStatus != 0 { result.append("scan mode could not be verified") }
        else if scanMode & 0x03 != 0x03 { result.append("inquiry/page scan is not enabled") }
        return result
    }
}
