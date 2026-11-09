import AppKit
import Observation

/// Tracks permission status and runs the guided grant flow.
///
/// ```swift
/// let permissions = PermissionManager()
/// if await permissions.request(.fullDiskAccess).isGranted {
///     // granted
/// }
/// ```
@MainActor
@Observable
public final class PermissionManager {
    /// The permissions whose status is kept up to date.
    public let permissions: [Permission]

    /// Latest known status of each tracked permission.
    public private(set) var statuses: [Permission: PermissionStatus] = [:]

    /// The permission whose guide is showing, if any.
    public private(set) var pending: Permission?

    /// Permissions that are granted in System Settings but that this process can't use
    /// until it relaunches. Their status reads `.granted`. See `needsRelaunch(_:)`.
    public private(set) var relaunchPending: Set<Permission> = []

    /// What the guide tells the user when System Settings offers to quit and reopen the
    /// app after a grant.
    @ObservationIgnored public var relaunchChoice = RelaunchChoice.quitAndReopen

    @ObservationIgnored private let guide = SettingsGuide()
    @ObservationIgnored private var continuation: CheckedContinuation<PermissionResult, Never>?
    @ObservationIgnored private var pendingCheck: (@MainActor () -> Bool)?
    @ObservationIgnored private var extensionQueries: Set<SystemExtension> = []
    @ObservationIgnored private var lastExtensionQuery = Date.distantPast
    /// Grants a fresh process has seen that this one can't until it relaunches.
    @ObservationIgnored private var probedGrants: Set<Permission> = []
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var lastProbe = Date.distantPast
    /// When the pending permission's grant was first seen by a probe only.
    @ObservationIgnored private var probedGrantSince: Date?
    @ObservationIgnored private var isTerminating = false

    /// - Parameters:
    ///   - permissions: Permissions to keep `statuses` current for.
    ///   - pollInterval: How often to re-check status.
    public init(permissions: [Permission] = Permission.privacyPermissions, pollInterval: TimeInterval = 0.75) {
        self.permissions = permissions
        guide.onCancel = { [weak self] in self?.finish(.cancelled) }
        guide.onDone = { [weak self] in self?.finish(.confirmed) }
        guide.onRelaunchDeferred = { [weak self] in self?.relaunchDeferred() }
        // "Quit & Reopen" quits the app mid-guide. Close the guide on the way out.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillTerminate() }
        }
        refresh()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    public func status(of permission: Permission) -> PermissionStatus {
        if probedGrants.contains(permission) { return .granted }
        return statuses[permission] ?? permission.currentStatus ?? .unknown
    }

    /// Whether `permission` is granted but this process can't use it until the app
    /// relaunches, such as after the user clicked Later on System Settings' "Quit &
    /// Reopen" alert. Offer to restart the app.
    public func needsRelaunch(_ permission: Permission) -> Bool {
        relaunchPending.contains(permission)
    }

    /// Re-checks every tracked permission now.
    public func refresh() {
        for permission in permissions {
            if let status = permission.currentStatus {
                set(probedGrants.contains(permission) ? .granted : status, for: permission)
            }
        }
        let waiting = probedGrants.filter { $0.currentStatus != .granted }
        if waiting != relaunchPending { relaunchPending = waiting }
        refreshSystemExtensions()
        probe()
        checkPending()
    }

    /// Grants a permission with the user's help.
    ///
    /// For a privacy pane, this is the same as `guide(to:)`. For a system extension, it
    /// submits the activation request first, and shows the guide only if macOS needs
    /// the user's approval.
    ///
    /// - Returns: How the request ended. See `PermissionResult`.
    @discardableResult
    public func request(
        _ permission: Permission,
        dragging appURL: URL = Bundle.main.bundleURL,
        tint: NSColor = .controlAccentColor,
        isGranted: (@MainActor () -> Bool)? = nil
    ) async -> PermissionResult {
        guard case .systemExtension(let ext) = permission else {
            return await guide(to: permission, dragging: appURL, tint: tint, isGranted: isGranted)
        }
        if status(of: permission) == .granted { return .granted }

        begin(permission, isGranted: isGranted)
        SystemExtensionRequest.activate(ext.identifier) { [weak self] event in
            guard let self, self.pending == permission else { return }
            switch event {
            case .needsUserApproval:
                self.showGuide(for: permission, appURL: appURL, tint: tint, isGranted: isGranted)
            case .activated:
                self.set(.granted, for: permission)
                self.finish(.granted)
            case .failed(let error):
                self.finish(.failed(error))
            case .properties:
                break
            }
        }
        return await waitForGrant()
    }

    /// Opens System Settings at the permission's pane and walks the user through it,
    /// without requesting anything from macOS.
    ///
    /// For a privacy pane, the user drags `appURL` into the highlighted list. For a system
    /// extension, the user turns on its switch; use this when your app submits its own
    /// `OSSystemExtensionRequest` and gets `requestNeedsUserApproval`.
    ///
    /// - Parameters:
    ///   - appURL: The bundle the user drags into System Settings. Pass a helper's URL when
    ///     a helper, not the main app, is the process that needs the permission.
    ///   - tint: Color of the highlight and sidecar border.
    ///   - isGranted: How to tell the permission was granted, for when the default check
    ///     can't see it (such as a helper's permissions). When neither this nor macOS can
    ///     report status, the sidecar shows a Done button instead.
    /// - Returns: How the guide ended. See `PermissionResult`.
    @discardableResult
    public func guide(
        to permission: Permission,
        dragging appURL: URL = Bundle.main.bundleURL,
        tint: NSColor = .controlAccentColor,
        isGranted: (@MainActor () -> Bool)? = nil
    ) async -> PermissionResult {
        if let isGranted, isGranted() { return .granted }
        let isOwnApp = isGranted == nil && appURL == Bundle.main.bundleURL
        if isOwnApp, status(of: permission) == .granted { return .granted }
        // Granted earlier, but this process can't see it until it relaunches.
        if isOwnApp, permission.mayNeedRelaunch {
            await probe(force: true, including: permission)?.value
            if status(of: permission) == .granted { return .granted }
        }

        begin(permission, isGranted: isGranted)
        showGuide(for: permission, appURL: appURL, tint: tint, isGranted: isGranted)
        return await waitForGrant()
    }

    /// Dismisses the guide and returns to the app.
    public func cancel() {
        finish(.cancelled)
    }

    private func begin(_ permission: Permission, isGranted: (@MainActor () -> Bool)?) {
        finish(.cancelled, activate: false)
        pending = permission
        pendingCheck = isGranted
    }

    private func showGuide(for permission: Permission, appURL: URL, tint: NSColor, isGranted: (@MainActor () -> Bool)?) {
        let isOwnApp = appURL == Bundle.main.bundleURL
        let canVerify = isGranted != nil || (isOwnApp && status(of: permission) != .unknown)
        let mode: SettingsGuide.Mode = if case .systemExtension = permission {
            .toggle(permission, confirmManually: !canVerify)
        } else {
            .drag(permission, confirmManually: !canVerify)
        }
        SystemSettings.open(permission.settingsURL)
        guide.start(mode, appURL: appURL, tint: tint, relaunch: relaunchChoice)
    }

    private func waitForGrant() async -> PermissionResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    private func set(_ status: PermissionStatus, for permission: Permission) {
        if statuses[permission] != status { statuses[permission] = status }
    }

    private func isPendingGranted(_ permission: Permission) -> Bool {
        pendingCheck?() ?? (status(of: permission) == .granted)
    }

    /// Finishes the request once its permission is granted, unless System Settings'
    /// "Quit & Reopen" alert is up (or likely about to be): the guide stays to walk the
    /// user through it, and finishes when it closes (`relaunchDeferred`).
    private func checkPending() {
        guard let pending, isPendingGranted(pending) else {
            probedGrantSince = nil
            return
        }
        if guide.isShowingRelaunchPrompt { return }
        // A probe can see the grant a moment before System Settings shows the alert.
        if pendingCheck == nil, needsRelaunch(pending) {
            let since = probedGrantSince ?? Date()
            probedGrantSince = since
            if Date().timeIntervalSince(since) < 1 { return }
        }
        finish(.granted)
    }

    /// The user clicked Later on the "Quit & Reopen" alert, so the grant went through but
    /// the app keeps running. Finish as granted once a probe confirms it.
    private func relaunchDeferred() {
        guard let permission = pending else { return }
        Task {
            // Quit & Reopen also closes the alert, then quits the app. Give it a moment.
            try? await Task.sleep(for: .milliseconds(500))
            guard pending == permission, !isTerminating else { return }
            await probe(force: true)?.value
            guard pending == permission, !isTerminating else { return }
            if isPendingGranted(permission) {
                finish(.granted)
            } else if pendingCheck != nil || status(of: permission) != .unknown {
                // It didn't go through after all (the user switched it back off), so
                // point at the list again. Permissions that can't be checked keep their
                // Done button instead.
                guide.resumeInstructions()
            }
        }
    }

    private func appWillTerminate() {
        isTerminating = true
        guard let pending else { return }
        finish(status(of: pending) == .granted ? .granted : .cancelled, activate: false)
    }

    /// Some grants (see `Permission.mayNeedRelaunch`) read as denied in a running app
    /// until it relaunches. While one matters (it's tracked or being granted), ask a
    /// fresh copy of the app instead: every 1.5 seconds during a request, and every 5
    /// otherwise. Returns the probe in flight, if any.
    @discardableResult
    private func probe(force: Bool = false, including extra: Permission? = nil) -> Task<Void, Never>? {
        if let probeTask { return probeTask }
        let wanted = (permissions + [pending, extra].compactMap { $0 }).filter {
            $0.mayNeedRelaunch && !probedGrants.contains($0) && $0.currentStatus == .notGranted
        }
        let interval: TimeInterval = pending == nil ? 5 : 1.5
        guard !wanted.isEmpty, Probe.isAvailable,
              force || Date().timeIntervalSince(lastProbe) > interval,
              let executable = Bundle.main.executableURL
        else { return nil }
        lastProbe = Date()
        let task = Task {
            let granted = await Probe.run(wanted, executable: executable)
            probeTask = nil
            lastProbe = Date()
            if let granted, !granted.isEmpty {
                probedGrants.formUnion(granted)
                refresh()
            }
        }
        probeTask = task
        return task
    }

    private func refreshSystemExtensions() {
        guard Date().timeIntervalSince(lastExtensionQuery) > 3 else { return }
        lastExtensionQuery = Date()
        for permission in permissions + [pending].compactMap({ $0 }) {
            guard case .systemExtension(let ext) = permission, !extensionQueries.contains(ext) else { continue }
            extensionQueries.insert(ext)
            SystemExtensionRequest.properties(ext.identifier) { [weak self] event in
                guard let self else { return }
                self.extensionQueries.remove(ext)
                switch event {
                case .properties(let found):
                    self.set(found.contains { $0.isEnabled } ? .granted : .notGranted, for: permission)
                case .failed:
                    self.set(.unknown, for: permission)
                default:
                    break
                }
            }
        }
    }

    private func finish(_ result: PermissionResult, activate: Bool = true) {
        guard pending != nil else { return }
        guide.stop()
        pending = nil
        pendingCheck = nil
        probedGrantSince = nil
        continuation?.resume(returning: result)
        continuation = nil
        if activate, !isTerminating { bringAppForward() }
    }

    private func bringAppForward() {
        NSApp.windows.first { $0.canBecomeMain && $0.isVisible }?.makeKeyAndOrderFront(nil)
        // macOS ignores activate() from an app in the background while System Settings is
        // in front. Opening the app through Launch Services brings it forward regardless.
        guard NSApp.activationPolicy() == .regular else {
            NSApp.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }
}
