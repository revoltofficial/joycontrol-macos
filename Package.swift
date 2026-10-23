// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "JoycontrolMacos",
    platforms: [.macOS(.v11)],
    products: [.executable(name: "joycontrol-macos", targets: ["JoycontrolMacos"])],
    dependencies: [
        .package(path: "Vendor/Bluetooth"),
        .package(path: "Vendor/BluetoothDarwin")
    ],
    targets: [
        .executableTarget(
            name: "JoycontrolMacos",
            dependencies: [
                .product(name: "Bluetooth", package: "Bluetooth"),
                .product(name: "BluetoothDarwin", package: "BluetoothDarwin")
            ],
            path: "joycontrol-macos",
            exclude: ["Info.plist", "joycontrol_macos.entitlements", "NintendoSwitchControllerSDP.plist", "Assets.xcassets", "Preview Content"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .testTarget(name: "PairingReadinessTests", dependencies: ["JoycontrolMacos"], path: "Tests/PairingReadinessTests")
    ]
)
