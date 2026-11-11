// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PermissionGuide",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionGuide", targets: ["PermissionGuide"]),
        .library(name: "PermissionInstaller", targets: ["PermissionInstaller"]),
        .library(name: "PermissionInstallerPlugin", targets: ["PermissionInstallerPlugin"]),
    ],
    targets: [
        .target(
            name: "PermissionGuide",
            dependencies: ["PermissionGuideProbe"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .target(
            name: "PermissionGuideProbe",
            linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("IOKit")]
        ),
        .testTarget(name: "PermissionGuideTests", dependencies: ["PermissionGuide"]),
        .target(
            name: "PermissionInstaller",
            dependencies: ["PermissionGuide"],
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
        .testTarget(
            name: "PermissionInstallerTests",
            dependencies: ["PermissionInstaller", "PermissionInstallerPlugin"]
        ),
    ]
)
