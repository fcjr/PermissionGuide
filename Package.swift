// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PermissionKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionKit", targets: ["PermissionKit"]),
        .library(name: "PermissionInstaller", targets: ["PermissionInstaller"]),
        .library(name: "PermissionInstallerPlugin", targets: ["PermissionInstallerPlugin"]),
    ],
    targets: [
        .target(
            name: "PermissionKit",
            dependencies: ["PermissionKitProbe"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .target(
            name: "PermissionKitProbe",
            linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("IOKit")]
        ),
        .testTarget(name: "PermissionKitTests", dependencies: ["PermissionKit"]),
        .target(
            name: "PermissionInstaller",
            dependencies: ["PermissionKit"],
            linkerSettings: [.linkedFramework("NetworkExtension")]
        ),
        // Objective-C, because Swift can't import InstallerPlugins (its module map says `requires !swift`).
        .target(
            name: "InstallerPluginBridge",
            linkerSettings: [.linkedFramework("InstallerPlugins")]
        ),
        .target(
            name: "PermissionInstallerPlugin",
            dependencies: ["PermissionInstaller", "InstallerPluginBridge"]
        ),
    ]
)
