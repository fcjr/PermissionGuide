import Foundation
import Security

extension SystemExtension {
    /// A reason macOS will refuse to activate the extension.
    public enum SetupIssue: Hashable, Sendable, CustomStringConvertible {
        /// System extensions only activate from apps in /Applications.
        case appNotInApplicationsFolder
        /// No `.systemextension` with this identifier in `Contents/Library/SystemExtensions`.
        case extensionNotEmbedded
        /// The app lacks `com.apple.developer.system-extension.install`.
        case appMissingInstallEntitlement
        /// The extension lacks the entitlement its category needs.
        case extensionMissingEntitlement(String)

        public var description: String {
            switch self {
            case .appNotInApplicationsFolder:
                "Move the app to /Applications. macOS only activates system extensions from there."
            case .extensionNotEmbedded:
                "No system extension with this identifier in Contents/Library/SystemExtensions."
            case .appMissingInstallEntitlement:
                "The app needs the com.apple.developer.system-extension.install entitlement."
            case .extensionMissingEntitlement(let name):
                "The extension needs the \(name) entitlement."
            }
        }
    }

    /// Checks the setup macOS requires before it will activate the extension.
    ///
    /// Catches the common mistakes early. An empty result doesn't guarantee activation:
    /// macOS also checks the Developer ID signature, notarization and provisioning profile.
    public func setupIssues(in bundle: Bundle = .main) -> [SetupIssue] {
        var issues: [SetupIssue] = []

        let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        if !applications.contains(where: { bundle.bundleURL.path.hasPrefix($0.path + "/") }) {
            issues.append(.appNotInApplicationsFolder)
        }
        if entitlements(of: bundle.bundleURL)?["com.apple.developer.system-extension.install"] as? Bool != true {
            issues.append(.appMissingInstallEntitlement)
        }

        guard let extensionURL = embeddedURL(in: bundle) else {
            issues.append(.extensionNotEmbedded)
            return issues
        }
        if let required = category.requiredEntitlement,
           entitlements(of: extensionURL)?[required] == nil {
            issues.append(.extensionMissingEntitlement(required))
        }
        return issues
    }

    /// The embedded `.systemextension` bundle, if present.
    public func embeddedURL(in bundle: Bundle = .main) -> URL? {
        let directory = bundle.bundleURL.appending(path: "Contents/Library/SystemExtensions")
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { url in
            url.pathExtension == "systemextension" && Bundle(url: url)?.bundleIdentifier == identifier
        }
    }

    private func entitlements(of url: URL) -> [String: Any]? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }
        return info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    }
}

extension SystemExtension.Category {
    /// The entitlement the extension itself must be signed with.
    var requiredEntitlement: String? {
        switch self {
        case .networkExtension: "com.apple.developer.networking.networkextension"
        case .endpointSecurity: "com.apple.developer.endpoint-security.client"
        case .driverExtension: "com.apple.developer.driverkit"
        case .cameraExtension: nil
        }
    }
}
