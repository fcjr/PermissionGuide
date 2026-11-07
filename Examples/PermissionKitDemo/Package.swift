// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PermissionKitDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "PermissionKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "PermissionKitDemo",
            dependencies: [.product(name: "PermissionKit", package: "PermissionKit")]
        )
    ]
)
