import Foundation
import NetworkExtension

/// A VPN or proxy configuration for your network extension.
public struct NetworkConfiguration: Sendable {
    public enum Kind: Sendable {
        case packetTunnel
        case appProxy
        case transparentProxy

        var displayName: String {
            switch self {
            case .packetTunnel: "VPN"
            case .appProxy, .transparentProxy: "Proxy"
            }
        }

        /// Part of a step's `id`.
        var stepKey: String {
            switch self {
            case .packetTunnel: "packetTunnel"
            case .appProxy: "appProxy"
            case .transparentProxy: "transparentProxy"
            }
        }

        /// For use mid-sentence.
        var lowercasedName: String {
            switch self {
            case .packetTunnel: "VPN"
            case .appProxy, .transparentProxy: "proxy"
            }
        }
    }

    public var kind: Kind
    public var providerBundleIdentifier: String
    /// The server shown in System Settings. macOS won't save a configuration without one,
    /// even for a proxy, so `nil` uses the app's name.
    public var serverAddress: String?
    /// Name shown in System Settings. Defaults to the app's name.
    public var localizedDescription: String?

    public init(_ kind: Kind, providerBundleIdentifier: String, serverAddress: String? = nil, localizedDescription: String? = nil) {
        self.kind = kind
        self.providerBundleIdentifier = providerBundleIdentifier
        self.serverAddress = serverAddress
        self.localizedDescription = localizedDescription
    }

    func isSaved() async throws -> Bool {
        guard let manager = try await existing() else { return false }
        return manager.isEnabled
    }

    /// Saves (or re-enables) the configuration. Throws `InstallerStepError.denied` when
    /// the user doesn't allow it.
    func save(appName: String) async throws {
        let manager = try await existing() ?? makeManager()
        if manager.protocolConfiguration == nil {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = providerBundleIdentifier
            proto.serverAddress = serverAddress ?? appName
            manager.protocolConfiguration = proto
            manager.localizedDescription = localizedDescription ?? appName
        }
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
        } catch let error as NSError {
            let denied = (error.domain == NEVPNErrorDomain && error.code == NEVPNError.configurationReadWriteFailed.rawValue)
                || error.localizedDescription.lowercased().contains("permission denied")
            throw denied ? InstallerStepError.denied : error
        }
    }

    private func existing() async throws -> NEVPNManager? {
        let managers: [NEVPNManager] = switch kind {
        case .packetTunnel: try await NETunnelProviderManager.loadAllFromPreferences()
        case .appProxy: try await NEAppProxyProviderManager.loadAllFromPreferences()
        case .transparentProxy: try await NETransparentProxyManager.loadAllFromPreferences()
        }
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleIdentifier
        }
    }

    private func makeManager() -> NEVPNManager {
        switch kind {
        case .packetTunnel: NETunnelProviderManager()
        case .appProxy: NEAppProxyProviderManager()
        case .transparentProxy: NETransparentProxyManager()
        }
    }
}
