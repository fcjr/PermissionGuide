import AppKit
import InstallerPluginBridge
import PermissionInstaller

/// One setup step. Checks it on entry and skips ahead if it's already done. A required
/// step keeps Continue disabled until it's done; an optional one can be skipped.
///
/// The work happens in the installed app, which the pane runs in the background: it
/// checks the step, and performs it (showing the System Settings guide or a system
/// prompt) as the app itself.
@MainActor
final class StepPane: NSObject, PKPaneController {
    let step: InstallerStep
    private unowned let session: SetupSession
    private var setup: InstallerSetup { session.setup }
    private weak var host: (any PKPaneHost)?

    private(set) var isDone = false
    private var isActive = false
    private var isChecking = false
    private var hasChecked = false
    /// The app performing the step, which stops when the user leaves the pane.
    private var running: AppProcess?

    private let actionButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let doneIcon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
    private let statusLabel = PaneView.label("", small: true, color: .secondaryLabelColor)
    private let errorLabel = PaneView.label("", small: true, color: .systemRed)
    private lazy var statusRow = NSStackView(views: [spinner, doneIcon, statusLabel])

    init(step: InstallerStep, session: SetupSession) {
        self.step = step
        self.session = session
    }

    var title: String { step.title }

    var shouldSkip: Bool { host?.installSucceeded != true || isDone }

    lazy var view: NSView = {
        let pane = PaneView(
            image: PaneView.symbol(step.resolvedSymbolName(), color: .controlAccentColor),
            heading: step.resolvedHeading(appName: setup.appName),
            message: step.resolvedMessage(appName: setup.appName)
        )

        // The one thing to do on this pane, so it's prominent: Installer's own buttons
        // stay at the bottom for moving on.
        actionButton.title = step.resolvedActionTitle()
        actionButton.bezelStyle = .push
        actionButton.controlSize = .large
        actionButton.bezelColor = .controlAccentColor
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        pane.add(actionButton, spacingAfter: 12)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        doneIcon.contentTintColor = .systemGreen
        doneIcon.isHidden = true
        statusRow.spacing = 6
        pane.add(statusRow)
        pane.add(errorLabel, spacingAfter: 14)

        pane.add(PaneView.label(step.requirement == .required
            ? "Required to finish setting up \(setup.appName)."
            : "Optional. You can set this up later in \(setup.appName).",
            small: true, color: .tertiaryLabelColor))
        refreshLabels()
        return pane.view
    }()

    func attach(_ host: any PKPaneHost) {
        self.host = host
    }

    func willEnterForward(_ forward: Bool) {
        isActive = true
        guard host?.installSucceeded == true else {
            host?.nextEnabled = true
            _ = host?.gotoNextPane()
            return
        }
        // Normally started by the intro pane; this covers setups without one.
        session.start()
        updateButtons()
        if forward && !isDone && !hasChecked && !isChecking {
            check()
        }
    }

    func didEnterForward(_ forward: Bool) {
        // Installer sometimes drops button state set before the pane appears.
        updateButtons()
    }

    func shouldExitForward(_ forward: Bool) -> Bool {
        !forward || isDone || step.requirement == .optional
    }

    func didExit() {
        isActive = false
        running?.terminate()
    }

    // MARK: - Running the app

    func check() {
        guard !isChecking, !hasChecked, !isDone else { return }
        isChecking = true
        setStatus("Checking…", working: true)
        Task {
            let status = await runApp("check").status
            isChecking = false
            hasChecked = true
            if running == nil { setStatus("") }
            if status == .done { markDone() }
        }
    }

    @objc private func actionClicked() {
        running?.terminate()
        errorLabel.stringValue = ""
        setStatus(workingHint, working: true)
        let watcher = watchForGrant()
        Task {
            let process = AppProcess()
            running = process
            let result = await runApp("perform", in: process)
            if running === process { running = nil }
            watcher?.cancel()
            guard !isDone else { return }
            setStatus("")
            session.focusInstaller()
            switch result.status {
            case .done:
                markDone()
            case .notDone:
                // System Settings' "Quit & Reopen" kills the app mid-guide, even though
                // the grant went through. Ask a fresh copy of the app.
                if await runApp("check").status == .done {
                    markDone()
                } else if isActive {
                    setStatus(notDoneHint)
                }
            default:
                errorLabel.stringValue = result.message.isEmpty ? "Something went wrong. Try again." : result.message
                refreshLabels()
            }
        }
    }

    /// For System Settings permissions, checks from a fresh copy of the app while the
    /// guide runs. A running app can't always see its own new grant (Screen Recording
    /// needs a relaunch), so this is what notices it.
    private func watchForGrant() -> Task<Void, Never>? {
        guard case .permission = step.kind else { return nil }
        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, !self.isDone else { return }
                if await self.runApp("check").status == .done, !Task.isCancelled {
                    self.markDone()
                    self.running?.terminate()
                    self.session.focusInstaller()
                    return
                }
            }
        }
    }

    private var workingHint: String {
        switch step.kind {
        case .permission: "Drag \(setup.appName) into the highlighted list in System Settings. This continues automatically."
        case .systemExtension: "Approve the prompt, then turn on the switch in System Settings. This continues automatically."
        default: "Approve the prompt that appears to continue."
        }
    }

    private var notDoneHint: String {
        switch step.kind {
        case .permission(let p): "\(p.localizedName) isn't on yet. Click \(step.resolvedActionTitle()) to try again."
        default: "That wasn't allowed. Click \(step.resolvedActionTitle()) to try again."
        }
    }

    private func runApp(_ action: String, in process: AppProcess = AppProcess()) async -> AppProcess.Result {
        guard let executable = Bundle(url: setup.resolvedAppURL)?.executableURL else {
            return AppProcess.Result(status: .failed, message: "Couldn't find \(setup.appName) at \(setup.resolvedAppURL.path).")
        }
        return await process.run(executable, [InstallerProtocol.flag, action, step.id])
    }

    // MARK: - State

    private func markDone() {
        guard !isDone else { return }
        isDone = true
        actionButton.isHidden = true
        errorLabel.stringValue = ""
        setStatus("Done")
        doneIcon.isHidden = false
        updateButtons()
        guard isActive else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if isActive { _ = host?.gotoNextPane() }
        }
    }

    private func setStatus(_ text: String, working: Bool = false) {
        statusLabel.stringValue = text
        spinner.isHidden = !working
        if working { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        refreshLabels()
    }

    /// Hidden views drop out of the stack, so empty labels don't leave gaps.
    private func refreshLabels() {
        statusRow.isHidden = statusLabel.stringValue.isEmpty
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
    }

    private func updateButtons() {
        host?.previousEnabled = false
        host?.nextEnabled = isDone || step.requirement == .optional
    }
}
