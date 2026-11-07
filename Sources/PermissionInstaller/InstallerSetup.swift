import AppKit
import PermissionKit

/// The setup section your installer shows after Install. Define it once, in code that
/// both your app and your installer plugin compile.
///
/// ```swift
/// extension InstallerSetup {
///     static let myApp = InstallerSetup(appName: "MyApp", steps: [
///         .permission(.fullDiskAccess),
///         .permission(.screenRecording, .optional),
///     ])
/// }
/// ```
// NSColor is immutable, so sharing a setup across threads is safe.
public struct InstallerSetup: @unchecked Sendable {
    public var appName: String
    public var steps: [InstallerStep]
    /// Where the app is installed. `nil` looks in /Applications, then ~/Applications.
    public var appURL: URL?
    /// Color of the System Settings highlight. The installer's own panes use system colors.
    public var tint: NSColor
    /// Whether the first pane lists the steps ahead.
    public var showsIntroduction: Bool
    /// Text on the first pane. `nil` uses a default.
    public var introduction: String?
    /// Whether the last pane opens the app.
    public var launchesApp: Bool

    public init(
        appName: String,
        steps: [InstallerStep],
        appURL: URL? = nil,
        tint: NSColor = .controlAccentColor,
        showsIntroduction: Bool = true,
        introduction: String? = nil,
        launchesApp: Bool = true
    ) {
        self.appName = appName
        self.steps = steps
        self.appURL = appURL
        self.tint = tint
        self.showsIntroduction = showsIntroduction
        self.introduction = introduction
        self.launchesApp = launchesApp
    }

    package var resolvedAppURL: URL {
        if let appURL { return appURL }
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(appName).app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(appName).app"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }
}

/// How the installer and the app talk: the installer runs the app's executable with
/// `--permission-installer <check|perform> <step id>` and reads its exit status.
package enum InstallerProtocol {
    package static let flag = "--permission-installer"

    /// Exists while the installer's setup section is open, holding the plugin's process ID.
    /// System Settings' "Quit & Reopen" relaunches the app normally; the app reads this to
    /// tell that relaunch apart from the user opening it, and quits.
    package static func setupMarker(bundleIdentifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(bundleIdentifier).permission-installer")
    }

    package static func isSetupRunning(bundleIdentifier: String) -> Bool {
        guard let text = try? String(contentsOf: setupMarker(bundleIdentifier: bundleIdentifier), encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return kill(pid, 0) == 0
    }

    package enum Exit: Int32 {
        case done = 0
        case failed = 1
        case notDone = 2
        case unknown = 3
    }
}
