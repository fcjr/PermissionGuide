import AppKit
import PermissionInstaller
import PermissionGuide

extension InstallerSetup {
    public static let demo = InstallerSetup(
        appName: "InstallerDemo",
        steps: [
            .permission(.fullDiskAccess),
            .custom(
                id: "library",
                title: "App Library",
                symbolName: "folder.badge.plus",
                heading: "Create the InstallerDemo library",
                message: "InstallerDemo keeps its data in Application Support. This is a custom step that runs inside the app.",
                actionTitle: "Create Library",
                check: { FileManager.default.fileExists(atPath: libraryURL.path) },
                perform: { try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true) }
            ),
            .permission(.accessibility, .optional),
            .permission(.screenRecording, .optional),
            .permission(.developerTools, .optional),
            // These need a real, signed system extension and the Network Extension
            // entitlement, which this demo doesn't have. They show the panes and how an
            // optional step fails without blocking setup.
            .permission(.systemExtension(.init(identifier: "com.example.installerdemo.tunnel", category: .networkExtension, displayName: "InstallerDemo VPN")), .optional),
            .permission(.systemExtension(.init(identifier: "com.example.installerdemo.security", category: .endpointSecurity, displayName: "InstallerDemo Security")), .optional),
            .networkConfiguration(.init(.packetTunnel, providerBundleIdentifier: "com.example.installerdemo.tunnel"), .optional),
            .certificate(.init(resourceName: "DemoRootCA"), .optional),
        ],
        tint: .systemIndigo
    )

    static let libraryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/InstallerDemo")
}
