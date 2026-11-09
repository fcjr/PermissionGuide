import AppKit

/// Follows the prompts System Settings shows during one guide, and decides what the guide
/// is waiting for. Fed once per tick.
struct PromptTracker {
    enum Prompt: Equatable {
        case authentication(NSRect)
        case relaunch(NSRect)

        var frame: NSRect {
            switch self {
            case .authentication(let frame), .relaunch(let frame): frame
            }
        }
    }

    enum Phase: Equatable {
        /// Waiting for the user to drag the app in or turn on the switch.
        case instructions
        /// A prompt is up, and answering it is the next step.
        case prompt(Prompt)
        /// The password or Touch ID prompt just closed. The "Quit & Reopen" alert may
        /// follow, so the guide holds still briefly instead of pointing back at the list.
        case afterAuthentication(ticks: Int)
        /// The "Quit & Reopen" alert closed without quitting the app (the user clicked
        /// Later), so the grant went through. The guide waits for the app to see it, and
        /// highlights nothing: the app's row is already in the list and switched on.
        case granted

        var isAfterAuthentication: Bool {
            if case .afterAuthentication = self { true } else { false }
        }
    }

    /// Ticks to wait after authentication before showing the instructions again.
    static let authenticationGapTicks = 30

    private(set) var phase = Phase.instructions
    /// Whether macOS has asked the user to authenticate during this guide.
    private var sawAuthentication = false

    var isShowingRelaunchPrompt: Bool {
        if case .prompt(.relaunch) = phase { true } else { false }
    }

    /// Takes the prompt over System Settings this tick, if any. Returns `true` when the
    /// relaunch alert has just closed.
    mutating func update(_ seen: SystemSettings.Prompt?) -> Bool {
        if let seen {
            // The same window as last tick is the same prompt.
            if case .prompt(let shown) = phase, shown.frame == seen.frame { return false }
            phase = .prompt(classify(seen))
            return false
        }
        switch phase {
        case .prompt(.relaunch):
            phase = .granted
            return true
        case .prompt(.authentication):
            phase = .afterAuthentication(ticks: 0)
        case .afterAuthentication(let ticks):
            phase = ticks + 1 >= Self.authenticationGapTicks ? .instructions : .afterAuthentication(ticks: ticks + 1)
        case .instructions, .granted:
            break
        }
        return false
    }

    /// Back to the instructions, when it turns out the grant didn't go through.
    mutating func resume() {
        if phase == .granted { phase = .instructions }
    }

    /// System Settings shows both its Touch ID/password panel and its "Quit & Reopen" alert
    /// as same-sized, centered, untitled windows. Quit & Reopen only ever follows a
    /// successful authentication, so the first panel is authentication. After that, a
    /// retry is the tall one: Touch ID is 273 pt and the password form taller, while the
    /// alert is about 220 pt.
    private mutating func classify(_ prompt: SystemSettings.Prompt) -> Prompt {
        switch prompt {
        case .authentication(let frame):
            sawAuthentication = true
            return .authentication(frame)
        case .panel(let frame):
            if !sawAuthentication || frame.height >= 250 {
                sawAuthentication = true
                return .authentication(frame)
            }
            return .relaunch(frame)
        }
    }
}
