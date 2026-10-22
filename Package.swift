// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "JoycontrolMacos",
    platforms: [.macOS(.v11)],
    products: [.executable(name: "joycontrol-macos", targets: ["JoycontrolMacos"])],
    dependencies: [
        .package(url: "https://github.com/PureSwift/Bluetooth.git", .revision("308277c808ced9ab169f52cb911b593c96b6fd27")),
        .package(url: "https://github.com/PureSwift/BluetoothDarwin.git", .revision("375e2db4d6bcc62b064866989df8c5b300ee9037"))
    ],
    targets: [
        .target(
            name: "JoycontrolMacos",
            dependencies: [
                .product(name: "Bluetooth", package: "Bluetooth"),
                .product(name: "BluetoothDarwin", package: "BluetoothDarwin")
            ],
            path: "joycontrol-macos",
            exclude: ["Info.plist", "joycontrol_macos.entitlements", "NintendoSwitchControllerSDP.plist", "Assets.xcassets", "Preview Content"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
