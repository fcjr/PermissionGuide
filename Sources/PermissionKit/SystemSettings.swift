import AppKit
import ApplicationServices

/// Locates the System Settings window and the control the user needs to reach.
///
/// The window frame comes from `CGWindowListCopyWindowInfo`, which needs no permission.
/// The target inside it is read through Accessibility when the app is trusted, and
/// otherwise placed from System Settings' layout (measured on macOS 27).
enum SystemSettings {
    static let bundleID = "com.apple.systempreferences"
    static let sidebarWidth: CGFloat = 232
    private static let contentInset: CGFloat = 20
    private static let rowHeight: CGFloat = 40

    static var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Whether a separate authentication process (the password dialog) is in front.
    static var isAuthenticationFrontmost: Bool {
        let name = (NSWorkspace.shared.frontmostApplication?.localizedName ?? "").lowercased()
        return authenticationProcesses.contains(where: name.contains)
    }

    static let authenticationProcesses = ["securityagent", "coreauth", "localauthentication"]

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Opens a System Settings deep link.
    ///
    /// System Settings ignores deep links while a sheet is open (an extension list, or a
    /// sub-pane the user opened), and the sheet can't be closed without Accessibility.
    /// So when one is open, quit System Settings first and open the link fresh.
    @MainActor
    static func open(_ url: URL) {
        // Bring System Settings forward even though the request comes from a panel
        // that never activated this app.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let app, let window = windowFrame(), sheetFrame(in: window) != nil else {
            NSWorkspace.shared.open(url, configuration: configuration)
            return
        }
        app.terminate()
        Task { @MainActor in
            for _ in 0..<60 where !app.isTerminated {
                try? await Task.sleep(for: .milliseconds(50))
            }
            _ = try? await NSWorkspace.shared.open(url, configuration: configuration)
        }
    }

    /// The System Settings window, in Cocoa (bottom-left origin) screen coordinates.
    static func windowFrame() -> NSRect? {
        windowFrames().max { $0.width * $0.height < $1.width * $1.height }
    }

    /// A sheet open on `window`. Sheets are separate windows in the window list.
    static func sheetFrame(in window: NSRect) -> NSRect? {
        windowFrames().first { $0 != window && window.contains($0) }
    }

    /// `window` is the window number. Panels zoom in and out, so their frame changes from
    /// one tick to the next while the window stays the same.
    enum Prompt: Equatable {
        /// Touch ID or password, shown by a separate system process.
        case authentication(NSRect, window: Int)
        /// A small panel of System Settings' own: its Touch ID or password prompt, or the
        /// "Quit & Reopen" alert that can follow a grant. The window list can't tell them
        /// apart, so `PromptTracker` decides from the order they appear in.
        case panel(NSRect, window: Int)

        var frame: NSRect {
            switch self {
            case .authentication(let frame, _), .panel(let frame, _): frame
            }
        }

        var window: Int {
            switch self {
            case .authentication(_, let window), .panel(_, let window): window
            }
        }
    }

    /// A prompt the user has to answer before the grant goes through.
    static func prompt(over window: NSRect) -> Prompt? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for entry in info {
            guard let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 150, bounds.height > 80
            else { continue }
            let frame = cocoaRect(fromTopLeft: bounds)
            let number = entry[kCGWindowNumber as String] as? Int ?? 0
            let owner = (entry[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            if authenticationProcesses.contains(where: owner.contains) {
                return .authentication(frame, window: number)
            }
            if (entry[kCGWindowOwnerPID as String] as? pid_t) == app?.processIdentifier,
               frame != window, frame.width < 520, frame.height < 400, window.intersects(frame) {
                return .panel(frame, window: number)
            }
        }
        return nil
    }

    private static func windowFrames() -> [NSRect] {
        guard let app,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return info.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 300, bounds.height > 200
            else { return nil }
            return cocoaRect(fromTopLeft: bounds)
        }
    }

    /// The screen holding most of `frame`.
    static func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(frame), ib = b.frame.intersection(frame)
            return ia.width * ia.height < ib.width * ib.height
        } ?? NSScreen.main
    }

    /// Where the user drops the app or flips the switch, in Cocoa screen coordinates.
    static func targetRect(for permission: Permission, in window: NSRect) -> NSRect {
        if case .systemExtension = permission {
            return extensionListRect(in: window)
        }
        let visible = NSRect(x: window.minX, y: window.minY + 10, width: window.width, height: window.height - 62)
        if AXIsProcessTrusted(), let list = accessibilityListRect(in: window) {
            let clipped = list.intersection(visible)
            if !clipped.isEmpty { return clipped }
        }
        // Without Accessibility the row count is unknown, so cover the first two rows,
        // which hold an app in any list that isn't empty.
        let top = window.maxY - listTopOffset(for: permission)
        let height = min(rowHeight * 2, top - visible.minY)
        return NSRect(x: window.minX + sidebarWidth + contentInset,
                      y: top - height,
                      width: window.width - sidebarWidth - contentInset * 2,
                      height: height)
    }

    /// Distance from the window's top edge to the list, which sits below the pane's description.
    private static func listTopOffset(for permission: Permission) -> CGFloat {
        switch permission {
        case .fullDiskAccess, .accessibility: 133
        case .screenRecording: 119
        case .inputMonitoring, .developerTools: 117
        case .appManagement, .bluetooth: 101
        case .systemExtension: 0
        }
    }

    /// System extensions are switched on in a sheet (470×465, centered in the window when
    /// measured). The extension rows start 110pt below its top and scroll until 65pt above
    /// its bottom, where the Done button sits.
    private static func extensionListRect(in window: NSRect) -> NSRect {
        let sheet = sheetFrame(in: window) ?? NSRect(
            x: window.midX - 235, y: window.midY - 232.5, width: 470, height: 465)
        return NSRect(x: sheet.minX + contentInset,
                      y: sheet.minY + 65,
                      width: sheet.width - contentInset * 2,
                      height: sheet.height - 110 - 65)
    }

    /// The first list in the window's content pane, read through Accessibility.
    private static func accessibilityListRect(in window: NSRect) -> NSRect? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let root: AXUIElement = attribute(kAXFocusedWindowAttribute, of: appElement) else { return nil }

        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < 500 {
            let element = queue.removeFirst()
            visited += 1
            if attribute(kAXRoleAttribute, of: element) as String? == kAXOutlineRole as String,
               let rect = frame(of: element),
               rect.minX > window.minX + sidebarWidth - 1 {
                return rect
            }
            if let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: element) {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> NSRect? {
        guard let position: AXValue = attribute(kAXPositionAttribute, of: element),
              let size: AXValue = attribute(kAXSizeAttribute, of: element)
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return cocoaRect(fromTopLeft: CGRect(origin: origin, size: extent))
    }

    /// Converts global top-left-origin coordinates (CoreGraphics, Accessibility) to Cocoa's.
    private static func cocoaRect(fromTopLeft rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
