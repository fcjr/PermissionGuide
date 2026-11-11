// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PermissionGuideDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "PermissionGuide", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "PermissionGuideDemo",
            dependencies: [.product(name: "PermissionGuide", package: "PermissionGuide")]
        )
    ]
)
