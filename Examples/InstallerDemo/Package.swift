// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InstallerDemo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "InstallerDemo", targets: ["InstallerDemo"]),
        .library(name: "InstallerDemoPlugin", type: .dynamic, targets: ["InstallerDemoPlugin"]),
    ],
    dependencies: [
        .package(name: "PermissionGuide", path: "../.."),
    ],
    targets: [
        // The setup is shared: the plugin shows it, the app performs its steps.
        .target(name: "DemoSetup", dependencies: [.product(name: "PermissionInstaller", package: "PermissionGuide")]),
        .executableTarget(name: "InstallerDemo", dependencies: ["DemoSetup"]),
        .target(name: "InstallerDemoPlugin", dependencies: [
            "DemoSetup",
            .product(name: "PermissionInstallerPlugin", package: "PermissionGuide"),
        ]),
    ]
)
