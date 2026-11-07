import AppKit
import InstallerPluginBridge
import PermissionInstaller

/// Subclass this in your installer plugin and return your setup. Name the subclass in
/// the plugin's Info.plist under `PermissionInstallerProvider`.
///
/// ```swift
/// @objc(MyAppInstallerPlugin)
/// final class MyAppInstallerPlugin: InstallerPlugin {
///     override var setup: InstallerSetup { .myApp }
/// }
/// ```
@MainActor
open class InstallerPlugin: NSObject, PKPaneProvider {
    open var setup: InstallerSetup {
        fatalError("Override InstallerPlugin.setup")
    }

    public func makePaneControllers() -> [any PKPaneController] {
        let session = SetupSession(setup: setup)
        var panes: [any PKPaneController] = []
        if setup.showsIntroduction { panes.append(IntroPane(session: session)) }
        panes += session.steps
        panes.append(DonePane(session: session))
        return panes
    }
}

/// State shared by the section's panes.
@MainActor
final class SetupSession {
    let setup: InstallerSetup
    private(set) var steps: [StepPane] = []
    private var started = false

    init(setup: InstallerSetup) {
        self.setup = setup
        steps = setup.steps.map { StepPane(step: $0, session: self) }
    }

    /// Called when the section first appears, after Install. Checks every step at once,
    /// so panes for steps that are already done are skipped without being shown.
    func start() {
        guard !started else { return }
        started = true
        if let marker {
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? String(getpid()).write(to: marker, atomically: true, encoding: .utf8)
        }
        steps.forEach { $0.check() }
    }

    func finish() {
        if let marker { try? FileManager.default.removeItem(at: marker) }
    }

    /// Brings Installer back after System Settings or a system prompt had focus. Opening
    /// it through Launch Services works even though this process is in the background.
    func focusInstaller() {
        guard let installer = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.installer").first,
              !installer.isActive,
              let url = installer.bundleURL
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private var marker: URL? {
        Bundle(url: setup.resolvedAppURL)?.bundleIdentifier.map { InstallerProtocol.setupMarker(bundleIdentifier: $0) }
    }
}

/// Lists the steps ahead and whether each can be skipped.
@MainActor
final class IntroPane: NSObject, PKPaneController {
    private let session: SetupSession
    private var setup: InstallerSetup { session.setup }
    private weak var host: (any PKPaneHost)?

    init(session: SetupSession) {
        self.session = session
    }

    var shouldSkip: Bool { host?.installSucceeded != true }

    var title: String { "Set Up" }

    lazy var view: NSView = {
        let hasOptional = setup.steps.contains { $0.requirement == .optional }
        let pane = PaneView(
            image: NSWorkspace.shared.icon(forFile: setup.resolvedAppURL.path),
            heading: "Finish setting up \(setup.appName)",
            message: setup.introduction ?? (hasOptional
                ? "\(setup.appName) needs a few things from macOS. Optional steps can be set up later."
                : "\(setup.appName) needs a few things from macOS.")
        )
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 5
        for step in setup.steps {
            let icon = NSImageView(image: NSImage(systemSymbolName: step.resolvedSymbolName(), accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? NSImage())
            icon.contentTintColor = .controlAccentColor
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let title = NSTextField(labelWithString: step.title)
            let row = NSStackView(views: [icon, title])
            row.spacing = 6
            if step.requirement == .optional {
                let tag = NSTextField(labelWithString: "Optional")
                tag.textColor = .secondaryLabelColor
                tag.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                row.addArrangedSubview(tag)
            }
            list.addArrangedSubview(row)
        }
        pane.add(list)
        return pane.view
    }()

    func attach(_ host: any PKPaneHost) {
        self.host = host
    }

    func willEnterForward(_ forward: Bool) {
        guard host?.installSucceeded == true else {
            host?.nextEnabled = true
            _ = host?.gotoNextPane()
            return
        }
        session.start()
        didEnterForward(forward)
    }

    func didEnterForward(_ forward: Bool) {
        host?.previousEnabled = false
        host?.nextEnabled = true
    }

    func shouldExitForward(_ forward: Bool) -> Bool { true }
    func didExit() {}
}

/// Confirms setup, mentions skipped steps and opens the app.
@MainActor
final class DonePane: NSObject, PKPaneController {
    private let session: SetupSession
    private var setup: InstallerSetup { session.setup }
    private weak var host: (any PKPaneHost)?
    private let message = PaneView.label("", color: .secondaryLabelColor)
    private var launched = false

    init(session: SetupSession) {
        self.session = session
    }

    var shouldSkip: Bool { host?.installSucceeded != true }

    var title: String { "Done" }

    lazy var view: NSView = {
        let pane = PaneView(image: PaneView.symbol("checkmark.circle.fill", color: .systemGreen),
                            heading: "\(setup.appName) is ready", message: "")
        pane.add(message)
        return pane.view
    }()

    func attach(_ host: any PKPaneHost) {
        self.host = host
    }

    func willEnterForward(_ forward: Bool) {
        guard host?.installSucceeded == true else {
            host?.nextEnabled = true
            _ = host?.gotoNextPane()
            return
        }
        var text = setup.launchesApp ? "\(setup.appName) is opening. You can close the installer." : "You can close the installer."
        session.finish()
        let skipped = session.steps.filter { !$0.isDone }.map(\.step.title)
        if !skipped.isEmpty {
            text += "\n\nYou skipped \(ListFormatter.localizedString(byJoining: skipped)). You can set "
                + (skipped.count == 1 ? "it" : "them") + " up later in \(setup.appName)."
        }
        message.stringValue = text
        didEnterForward(forward)

        if forward, setup.launchesApp, !launched {
            launched = true
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: setup.resolvedAppURL, configuration: configuration)
        }
    }

    func didEnterForward(_ forward: Bool) {
        host?.previousEnabled = false
        host?.nextEnabled = true
    }

    func shouldExitForward(_ forward: Bool) -> Bool { true }
    func didExit() {}
}
