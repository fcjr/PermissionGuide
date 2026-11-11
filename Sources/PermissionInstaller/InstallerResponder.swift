import AppKit
import PermissionGuide

extension InstallerSetup {
    /// Call this first thing when your app launches, before any UI. When the installer
    /// launched the app to check or perform a step, it does that and exits. Otherwise it
    /// returns immediately.
    ///
    /// The installer runs these as your app, not as Installer, so permission checks,
    /// system extensions and network configurations all belong to your app. For System
    /// Settings permissions, the app shows PermissionGuide's guide itself, without a Dock icon.
    @MainActor
    public func handleInstallerLaunch() {
        let arguments = CommandLine.arguments
        guard let i = arguments.firstIndex(of: InstallerProtocol.flag), i + 2 < arguments.count else {
            // System Settings' "Quit & Reopen" relaunches the app normally. Mid-setup that
            // would open the app's windows over the installer, so step aside instead.
            if let id = Bundle.main.bundleIdentifier, InstallerProtocol.isSetupRunning(bundleIdentifier: id) {
                returnToInstaller()
                Foundation.exit(0)
            }
            return
        }
        let action = arguments[i + 1]
        guard let step = steps.first(where: { $0.id == arguments[i + 2] }) else {
            exit(.failed, "Unknown step \(arguments[i + 2]).")
        }

        // AppKit swallows SIGTERM, but it's how the installer stops a step the user left
        // (or one that's already done), so exit on it ourselves.
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminate.setEventHandler { Foundation.exit(InstallerProtocol.Exit.notDone.rawValue) }
        terminate.resume()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let (status, message) = switch action {
            case "check": await check(step)
            case "perform": await perform(step)
            default: (InstallerProtocol.Exit.failed, "Unknown action \(action).")
            }
            if action == "perform" { returnToInstaller() }
            exit(status, message)
        }
        app.run()
        withExtendedLifetime(terminate) {}
        exit(.failed, "The app stopped unexpectedly.")
    }

    @MainActor
    private func check(_ step: InstallerStep) async -> (InstallerProtocol.Exit, String) {
        do {
            let done: Bool? = switch step.kind {
            case .permission(let permission):
                switch permission.currentStatus {
                case .granted: true
                case .notGranted: false
                case .unknown, nil: nil
                }
            case .systemExtension(let ext): await isEnabled(ext)
            case .networkConfiguration(let config): try await config.isSaved()
            case .certificate(let cert): try cert.isTrusted()
            case .custom(let check, _): await check()
            }
            return switch done {
            case true?: (.done, "")
            case false?: (.notDone, "")
            case nil: (.unknown, "")
            }
        } catch {
            return (.failed, error.localizedDescription)
        }
    }

    @MainActor
    private func perform(_ step: InstallerStep) async -> (InstallerProtocol.Exit, String) {
        do {
            switch step.kind {
            case .permission(let permission):
                return await request(permission)
            case .systemExtension(let ext):
                return await request(.systemExtension(ext))
            case .networkConfiguration(let config):
                try await config.save(appName: appName)
            case .certificate(let cert):
                try cert.trust()
            case .custom(_, let perform):
                try await perform()
            }
            return (.done, "")
        } catch InstallerStepError.denied {
            return (.notDone, "")
        } catch {
            return (.failed, error.localizedDescription)
        }
    }

    @MainActor
    private func isEnabled(_ ext: SystemExtension) async -> Bool {
        await withCheckedContinuation { continuation in
            SystemExtensionRequest.properties(ext.identifier) { event in
                if case .properties(let found) = event {
                    continuation.resume(returning: found.contains { $0.isEnabled })
                } else if case .failed = event {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Guides the user through System Settings, installing a system extension first.
    @MainActor
    private func request(_ permission: Permission) async -> (InstallerProtocol.Exit, String) {
        let manager = PermissionManager(permissions: [permission])
        // Relaunching would kill this process mid-step. The installer checks the grant
        // from a fresh process, so the app doesn't need to restart to see it.
        manager.relaunchChoice = .later
        return switch await manager.request(permission, tint: tint) {
        case .granted, .confirmed: (.done, "")
        case .cancelled: (.notDone, "")
        case .failed(let error): (.failed, error.localizedDescription)
        }
    }

    /// Hands focus back to Installer. Installer can't take it from the app on its own.
    @MainActor
    private func returnToInstaller() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.installer").first?
            .activate(from: .current, options: [])
    }

    private func exit(_ status: InstallerProtocol.Exit, _ message: String) -> Never {
        if !message.isEmpty { FileHandle.standardError.write(Data((message + "\n").utf8)) }
        Foundation.exit(status.rawValue)
    }
}
