import AppKit
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import IOKit.hid
import ServiceManagement

/// A permission the user grants by adding the app to, or switching it on in, System Settings.
///
/// Covers the privacy panes with an app list that has a "+" button, plus system
/// extensions (VPN and content-filter network extensions, Endpoint Security clients,
/// drivers, camera extensions) that the user must switch on before they run.
/// Prompt-only permissions like Camera and Microphone are out of scope: apps appear in
/// those lists only after asking through the framework's own API.
///
/// `backgroundItem` covers a launchd daemon the app registers with `SMAppService`, which
/// the user switches on under Login Items & Extensions → Allow in the Background.
public enum Permission: Hashable, Sendable {
    case fullDiskAccess
    case screenRecording
    case accessibility
    case inputMonitoring
    case developerTools
    case appManagement
    case bluetooth
    case systemExtension(SystemExtension)
    /// A launch daemon in the app's `Contents/Library/LaunchDaemons`, by plist name.
    case backgroundItem(daemonPlist: String)

    /// Every privacy pane permission, in System Settings order.
    public static let privacyPermissions: [Permission] = [
        .accessibility, .appManagement, .bluetooth, .developerTools,
        .fullDiskAccess, .inputMonitoring, .screenRecording,
    ]

    /// The name System Settings uses for the pane.
    public var localizedName: String {
        switch self {
        case .fullDiskAccess: "Full Disk Access"
        case .screenRecording: "Screen & System Audio Recording"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .developerTools: "Developer Tools"
        case .appManagement: "App Management"
        case .bluetooth: "Bluetooth"
        case .systemExtension(let ext): ext.displayName
        case .backgroundItem: "Allow in the Background"
        }
    }

    /// Deep link to the permission's pane in System Settings.
    public var settingsURL: URL {
        let path = switch self {
        case .fullDiskAccess: "com.apple.preference.security?Privacy_AllFiles"
        case .screenRecording: "com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility: "com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring: "com.apple.preference.security?Privacy_ListenEvent"
        case .developerTools: "com.apple.preference.security?Privacy_DevTools"
        case .appManagement: "com.apple.preference.security?Privacy_AppBundles"
        case .bluetooth: "com.apple.preference.security?Privacy_Bluetooth"
        case .systemExtension(let ext):
            "com.apple.ExtensionsPreferences?extensionPointIdentifier=\(ext.category.extensionPointIdentifier)"
        case .backgroundItem: "com.apple.LoginItems-Settings.extension"
        }
        return URL(string: "x-apple.systempreferences:\(path)")!
    }

    /// Whether a grant can take effect only after the app relaunches. System Settings
    /// offers to quit and reopen the app after granting these, and until then the running
    /// app may still read them as not granted. `PermissionManager` checks them from a
    /// fresh copy of the app instead, and reports the wait through `needsRelaunch(_:)`.
    public var mayNeedRelaunch: Bool {
        switch self {
        case .fullDiskAccess, .screenRecording, .inputMonitoring: true
        default: false
        }
    }

    /// The current process's status, checked without ever showing a system prompt.
    /// `nil` for system extensions, whose status is asynchronous (see `PermissionManager`).
    package var currentStatus: PermissionStatus? {
        switch self {
        case .fullDiskAccess:
            // TCC.db exists on every Mac and can only be opened with Full Disk Access.
            // May keep failing until the app relaunches.
            let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
            guard let handle = FileHandle(forReadingAtPath: path) else { return .notGranted }
            try? handle.close()
            return .granted
        case .screenRecording:
            // May keep reporting false until the app relaunches.
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ? .granted : .notGranted
        case .bluetooth:
            return CBManager.authorization == .allowedAlways ? .granted : .notGranted
        case .developerTools, .appManagement:
            // No public API reports these.
            return .unknown
        case .systemExtension:
            return nil
        case .backgroundItem(let plist):
            return switch SMAppService.daemon(plistName: plist).status {
            case .enabled: .granted
            case .notFound: .unknown
            default: .notGranted
            }
        }
    }
}

extension Permission: Identifiable {
    public var id: Self { self }
}

public enum PermissionStatus: Sendable {
    case granted
    case notGranted
    /// macOS offers no way to check this permission.
    case unknown
}

/// A system extension embedded in the app's `Contents/Library/SystemExtensions`.
public struct SystemExtension: Hashable, Sendable {
    public enum Category: Hashable, Sendable {
        /// VPN providers, content filters, DNS proxies.
        case networkExtension
        case endpointSecurity
        case driverExtension
        case cameraExtension

        /// The extension type's name in System Settings.
        public var localizedName: String {
            switch self {
            case .networkExtension: "Network Extension"
            case .endpointSecurity: "Endpoint Security Extension"
            case .driverExtension: "Driver Extension"
            case .cameraExtension: "Camera Extension"
            }
        }

        var extensionPointIdentifier: String {
            switch self {
            case .networkExtension: "com.apple.system_extension.network_extension.extension-point"
            case .endpointSecurity: "com.apple.system_extension.endpoint_security.extension-point"
            case .driverExtension: "com.apple.system_extension.driver_extension.extension-point"
            case .cameraExtension: "com.apple.system_extension.cmio.extension-point"
            }
        }
    }

    public var identifier: String
    public var category: Category
    /// The name shown next to the extension's switch in System Settings, usually the app's name.
    public var displayName: String

    public init(identifier: String, category: Category, displayName: String) {
        self.identifier = identifier
        self.category = category
        self.displayName = displayName
    }
}

/// How a `request` or `guide(to:)` call ended.
public enum PermissionResult: Sendable {
    /// macOS (or your `isGranted` check) reports the permission granted. For a permission
    /// that only applies after a relaunch, check `PermissionManager.needsRelaunch(_:)`.
    case granted
    /// The user clicked Done for a permission that can't be checked.
    case confirmed
    /// The user clicked Cancel, you called `cancel()`, the calling task was cancelled,
    /// or another request replaced this one.
    case cancelled
    /// System extension activation failed.
    case failed(any Error)

    /// `true` for `.granted` and `.confirmed`.
    public var isGranted: Bool {
        switch self {
        case .granted, .confirmed: true
        case .cancelled, .failed: false
        }
    }
}

/// The answer the guide suggests when System Settings asks to quit and reopen the app.
public enum RelaunchChoice: Sendable {
    /// The app relaunches, so permissions that need a restart (like Screen Recording)
    /// take effect right away.
    case quitAndReopen
    /// The app keeps running. Choose this when relaunching would interrupt something,
    /// such as an installer. The request still returns `.granted`, and
    /// `needsRelaunch(_:)` reports that the app hasn't picked the grant up yet.
    case later
}
