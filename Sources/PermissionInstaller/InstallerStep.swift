import Foundation
import PermissionGuide

/// One pane in the installer's setup section.
public struct InstallerStep: Identifiable, Sendable {
    public enum Requirement: Sendable {
        /// Continue stays disabled until the step is done.
        case required
        /// Continue is enabled from the start, so the user can skip it.
        case optional
    }

    /// Names the step when the installer asks the app about it, so it has to be unique
    /// within a setup and the same in the app and the plugin.
    public let id: String
    public var requirement: Requirement
    /// Short name, shown in Installer's sidebar and the intro list.
    public var title: String
    /// SF Symbol at the top of the pane. `nil` uses one that fits the step.
    public var symbolName: String?
    /// Large text at the top of the pane. `nil` uses a default.
    public var heading: String?
    /// Explanation under the heading. `nil` uses a default.
    public var message: String?
    /// Title of the button that starts the step. `nil` uses a default.
    public var actionTitle: String?

    package let kind: Kind

    package enum Kind: Sendable {
        case permission(Permission)
        case systemExtension(SystemExtension)
        case networkConfiguration(NetworkConfiguration)
        case certificate(TrustedCertificate)
        case custom(check: @MainActor @Sendable () async -> Bool?, perform: @MainActor @Sendable () async throws -> Void)
    }

    private init(
        id: String, requirement: Requirement, title: String, kind: Kind,
        heading: String? = nil, message: String? = nil, actionTitle: String? = nil
    ) {
        self.id = id
        self.requirement = requirement
        self.title = title
        self.kind = kind
        self.heading = heading
        self.message = message
        self.actionTitle = actionTitle
    }

    /// A System Settings permission. Privacy permissions are granted by dragging the app
    /// into the list; system extensions are installed, then switched on.
    ///
    /// `heading`, `message` and `actionTitle` replace the pane's default text.
    public static func permission(
        _ permission: Permission,
        _ requirement: Requirement = .required,
        heading: String? = nil,
        message: String? = nil,
        actionTitle: String? = nil
    ) -> InstallerStep {
        switch permission {
        case .systemExtension(let ext):
            InstallerStep(id: "sysext.\(ext.identifier)", requirement: requirement, title: ext.displayName,
                          kind: .systemExtension(ext), heading: heading, message: message, actionTitle: actionTitle)
        default:
            InstallerStep(id: "permission.\(permission.stepKey)", requirement: requirement, title: permission.displayName,
                          kind: .permission(permission), heading: heading, message: message, actionTitle: actionTitle)
        }
    }

    /// Saves a VPN or proxy configuration, which shows macOS's "Add VPN Configurations" prompt.
    ///
    /// `heading`, `message` and `actionTitle` replace the pane's default text.
    public static func networkConfiguration(
        _ configuration: NetworkConfiguration,
        _ requirement: Requirement = .required,
        heading: String? = nil,
        message: String? = nil,
        actionTitle: String? = nil
    ) -> InstallerStep {
        InstallerStep(id: "network.\(configuration.kind.stepKey).\(configuration.providerBundleIdentifier)",
                      requirement: requirement, title: "\(configuration.kind.displayName) Configuration",
                      kind: .networkConfiguration(configuration), heading: heading, message: message, actionTitle: actionTitle)
    }

    /// Adds a root certificate to the keychain and marks it trusted, which asks for the
    /// user's password or Touch ID.
    ///
    /// `heading`, `message` and `actionTitle` replace the pane's default text.
    public static func certificate(
        _ certificate: TrustedCertificate,
        _ requirement: Requirement = .required,
        heading: String? = nil,
        message: String? = nil,
        actionTitle: String? = nil
    ) -> InstallerStep {
        InstallerStep(id: "certificate.\(certificate.resourceName).\(certificate.resourceExtension)",
                      requirement: requirement, title: "Certificate",
                      kind: .certificate(certificate), heading: heading, message: message, actionTitle: actionTitle)
    }

    /// Your own step. Both closures run inside your app, which the installer launches
    /// in the background.
    ///
    /// - Parameters:
    ///   - id: Names the step when the installer asks the app about it. Unique among your
    ///     custom steps.
    ///   - check: Whether the step is done. Return `nil` if you can't tell.
    ///   - perform: Does the step. Throw `InstallerStepError.denied` if the user declined.
    public static func custom(
        id: String,
        title: String,
        symbolName: String? = nil,
        heading: String,
        message: String,
        actionTitle: String,
        _ requirement: Requirement = .required,
        check: @escaping @MainActor @Sendable () async -> Bool?,
        perform: @escaping @MainActor @Sendable () async throws -> Void
    ) -> InstallerStep {
        var step = InstallerStep(id: "custom.\(id)", requirement: requirement, title: title,
                                 kind: .custom(check: check, perform: perform),
                                 heading: heading, message: message, actionTitle: actionTitle)
        step.symbolName = symbolName
        return step
    }
}

/// Thrown from a custom step's `perform` closure.
public enum InstallerStepError: Error {
    /// The user declined. The pane offers to try again.
    case denied
}

// MARK: - Default text

extension InstallerStep {
    package func resolvedHeading(appName: String) -> String {
        if let heading { return heading }
        return switch kind {
        case .permission(.backgroundItem): "Allow \(appName) in the background"
        case .permission(let p): "Allow \(p.displayName)"
        case .systemExtension(let ext): "Allow the \(ext.category.displayName.lowercased())"
        case .networkConfiguration(let c): "Add the \(c.kind.lowercasedName) configuration"
        case .certificate: "Trust the \(appName) certificate"
        case .custom: title
        }
    }

    package func resolvedMessage(appName: String) -> String {
        if let message { return message }
        return switch kind {
        case .permission(.backgroundItem):
            "\(appName) runs a helper in the background. Click below, then turn on \(appName) under Allow in the Background in System Settings."
        case .permission(let p):
            "\(appName) needs \(p.displayName). Click below, then drag \(appName) into the highlighted list in System Settings."
        case .systemExtension(let ext):
            "macOS will ask you to allow \(ext.displayName). Click below, approve the prompt, then turn it on in System Settings."
        case .networkConfiguration(let c):
            "macOS will ask permission to add \(appName)'s \(c.kind.lowercasedName) configuration. Click below and choose Allow."
        case .certificate:
            "\(appName) uses a local certificate. Click below and approve with your password or Touch ID to trust it."
        case .custom:
            ""
        }
    }

    package func resolvedSymbolName() -> String {
        if let symbolName { return symbolName }
        return switch kind {
        case .permission(let p): p.symbolName
        case .systemExtension(let ext): ext.category.symbolName
        case .networkConfiguration: "network"
        case .certificate: "checkmark.shield"
        case .custom: "gearshape"
        }
    }

    package func resolvedActionTitle() -> String {
        if let actionTitle { return actionTitle }
        return switch kind {
        case .permission: "Open System Settings"
        case .systemExtension: "Allow Extension"
        case .networkConfiguration: "Add Configuration"
        case .certificate: "Trust Certificate"
        case .custom: "Continue"
        }
    }
}

extension Permission {
    /// Part of a step's `id`. Spelled out so it can't change with how Swift prints the case.
    var stepKey: String {
        switch self {
        case .fullDiskAccess: "fullDiskAccess"
        case .screenRecording: "screenRecording"
        case .accessibility: "accessibility"
        case .inputMonitoring: "inputMonitoring"
        case .developerTools: "developerTools"
        case .appManagement: "appManagement"
        case .bluetooth: "bluetooth"
        case .systemExtension(let ext): "systemExtension.\(ext.identifier)"
        case .backgroundItem(let plist): "backgroundItem.\(plist)"
        }
    }

    var symbolName: String {
        switch self {
        case .fullDiskAccess: "externaldrive"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        case .developerTools: "hammer"
        case .appManagement: "app.badge.checkmark"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .systemExtension(let ext): ext.category.symbolName
        case .backgroundItem: "gearshape.2"
        }
    }
}

extension SystemExtension.Category {
    var symbolName: String {
        switch self {
        case .networkExtension: "network.badge.shield.half.filled"
        case .endpointSecurity: "shield.lefthalf.filled"
        case .driverExtension: "cpu"
        case .cameraExtension: "camera"
        }
    }
}
