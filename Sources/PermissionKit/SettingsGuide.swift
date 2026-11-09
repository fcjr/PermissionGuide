import AppKit

/// Keeps the spotlight overlay and sidecar attached to the System Settings window.
@MainActor
final class SettingsGuide {
    enum Mode {
        /// Drag the app into a privacy pane's list. `confirmManually` adds a Done button
        /// for when the grant can't be detected.
        case drag(Permission, confirmManually: Bool)
        /// Switch on a system extension.
        case toggle(Permission, confirmManually: Bool)

        var permission: Permission {
            switch self {
            case .drag(let p, _), .toggle(let p, _): p
            }
        }

        var confirmManually: Bool {
            switch self {
            case .drag(_, let c), .toggle(_, let c): c
            }
        }
    }

    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?
    /// The "Quit & Reopen" alert closed and the app is still running: the user clicked
    /// Later. Call `resumeInstructions()` if the grant turns out not to have gone through.
    var onRelaunchDeferred: (() -> Void)?

    private var mode: Mode?
    private var overlay: SpotlightOverlay?
    private var sidecar: SidecarPanel?
    private var ghost: GhostFlight?
    private var timer: Timer?
    private var lastLayout: [NSRect] = []
    private var ticksSinceLayout = 0
    private var isDragging = false
    private var relaunch = RelaunchChoice.quitAndReopen
    private var appName = ""
    private var instructions = (title: "", message: "")
    private var prompts = PromptTracker()
    /// The phase the sidecar's text was last set for.
    private var shownPhase = PromptTracker.Phase.instructions

    /// Whether System Settings' "Quit & Reopen" alert is up. Finishing now would close the
    /// guide while the alert still waits for an answer.
    var isShowingRelaunchPrompt: Bool { prompts.isShowingRelaunchPrompt }

    /// Shows the instructions again after `onRelaunchDeferred`.
    func resumeInstructions() {
        prompts.resume()
    }

    func start(_ mode: Mode, appURL: URL, tint: NSColor, relaunch: RelaunchChoice) {
        stop()
        self.mode = mode
        self.relaunch = relaunch
        appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let name = mode.permission.localizedName

        let sidecar: SidecarPanel
        switch mode {
        case .drag(_, let confirmManually):
            sidecar = SidecarPanel(
                title: "Grant \(name)",
                message: "Drag this icon into the highlighted list in System Settings.",
                icon: icon, dragURL: appURL, showsDone: confirmManually, tint: tint)
        case .toggle(let permission, let confirmManually):
            let kind = if case .systemExtension(let ext) = permission { ext.category.localizedName } else { name }
            sidecar = SidecarPanel(
                title: "Allow \(kind)",
                message: "Turn on the switch next to \(name) in System Settings.",
                icon: icon, dragURL: nil, showsDone: confirmManually, tint: tint)
        }
        instructions = (sidecar.instructionTitle, sidecar.instructionMessage)
        sidecar.onCancel = { [weak self] in self?.onCancel?() }
        sidecar.onDone = { [weak self] in self?.onDone?() }
        sidecar.iconView.onDragChanged = { [weak self] dragging in
            self?.isDragging = dragging
            self?.overlay?.setDragging(dragging)
            // Once the user has tried it themselves, the demo has done its job.
            self?.ghost?.orderOut(nil)
            self?.ghost = nil
        }

        overlay = SpotlightOverlay(tint: tint)
        if case .drag = mode, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            ghost = GhostFlight(icon: icon)
        }
        self.sidecar = sidecar

        // Common modes keep it ticking during a drag, which runs in the event tracking mode.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overlay?.orderOut(nil)
        sidecar?.orderOut(nil)
        ghost?.orderOut(nil)
        overlay = nil
        ghost = nil
        sidecar = nil
        mode = nil
        lastLayout = []
        isDragging = false
        prompts = PromptTracker()
        shownPhase = .instructions
    }

    private func tick() {
        guard let mode, let overlay, let sidecar else { return }
        let frame = SystemSettings.windowFrame()
        if prompts.update(frame.flatMap { SystemSettings.prompt(over: $0) }) {
            // Not from inside the tick: the handler may stop the guide.
            DispatchQueue.main.async { [weak self] in self?.onRelaunchDeferred?() }
        }
        let phase = prompts.phase
        let prompt: PromptTracker.Prompt? = if case .prompt(let p) = phase { p } else { nil }
        // Only while System Settings is in front, or a password dialog that took focus from
        // it. Any other app coming forward (like the one being granted) hides the guide.
        guard SystemSettings.isFrontmost || isDragging || SystemSettings.isAuthenticationFrontmost,
              let frame,
              let screen = SystemSettings.screen(for: frame)
        else {
            overlay.orderOut(nil)
            sidecar.orderOut(nil)
            ghost?.orderOut(nil)
            lastLayout = []
            return
        }

        // A prompt is the next thing to do, so it gets the highlight. Otherwise a sheet
        // over the pane (such as the "+" file picker) hides the list, so drop the
        // highlight until it closes. For extensions the sheet is the target instead.
        // Right after authenticating, and once granted, there's nothing to point at: the
        // list's first rows (the highlight without Accessibility) aren't the app's.
        let sheet = SystemSettings.sheetFrame(in: frame)
        let showsHighlight = switch phase {
        case .prompt: true
        case .afterAuthentication, .granted: false
        case .instructions: if case .toggle = mode { sheet != nil } else { sheet == nil }
        }
        let showsGhost = showsHighlight && prompt == nil && !isDragging
        // Right after authenticating, keep the last text until the next prompt shows.
        if phase != shownPhase, !phase.isAfterAuthentication {
            shownPhase = phase
            let text = text(for: phase, mode: mode)
            sidecar.show(title: text.title, message: text.message)
            lastLayout = []
        }

        // Re-layout when the window, sheet or displays change, and twice a second
        // otherwise so the highlight follows the list as rows are added.
        ticksSinceLayout += 1
        let layout = [frame, sheet ?? .zero, prompt?.frame ?? .zero] + NSScreen.screens.map(\.frame)
        if layout != lastLayout || ticksSinceLayout >= 30 {
            lastLayout = layout
            ticksSinceLayout = 0
            sidecar.position(beside: frame, on: screen)
            let target = prompt?.frame ?? SystemSettings.targetRect(for: mode.permission, in: frame)
            overlay.update(screen: screen, window: frame.union(prompt?.frame ?? frame), target: target)
            if showsGhost {
                ghost?.fly(from: sidecar.iconScreenCenter, to: NSPoint(x: target.midX, y: target.midY), on: screen)
            }
        }
        if showsHighlight {
            if !overlay.isVisible { overlay.orderFrontRegardless() }
        } else if overlay.isVisible {
            overlay.orderOut(nil)
        }
        if !sidecar.isVisible { sidecar.orderFrontRegardless() }
        if let ghost {
            if showsGhost {
                if !ghost.isVisible { ghost.orderFrontRegardless() }
            } else if ghost.isVisible {
                ghost.orderOut(nil)
                lastLayout = []
            }
        }
    }

    private func text(for phase: PromptTracker.Phase, mode: Mode) -> (title: String, message: String) {
        switch phase {
        case .prompt(.authentication):
            ("Confirm It's You", "Use Touch ID or enter your password to allow \(appName).")
        case .prompt(.relaunch):
            switch relaunch {
            case .quitAndReopen: ("Restart \(appName)", "Click Quit & Reopen so \(appName) can use its new permission.")
            case .later: ("Almost Done", "Click Later. \(appName) picks up the change on its own.")
            }
        case .granted:
            mode.confirmManually
                ? ("Almost Done", "Click Done to return to \(appName).")
                : ("Almost Done", "Returning to \(appName)…")
        case .instructions, .afterAuthentication:
            instructions
        }
    }
}
