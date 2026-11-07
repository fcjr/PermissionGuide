import Foundation
import Security

/// A root certificate bundled in your app's Resources, to add to the keychain and trust.
public struct TrustedCertificate: Sendable {
    public enum Domain: Sendable {
        /// Trusted for the current user. Asks for the user's password or Touch ID.
        case user
        /// Trusted for every user. Asks for an administrator's password or Touch ID.
        case admin
    }

    /// File name in the app's Resources, without extension.
    public var resourceName: String
    /// Extension of a DER-encoded certificate file.
    public var resourceExtension: String
    public var domain: Domain

    public init(resourceName: String, extension resourceExtension: String = "cer", domain: Domain = .user) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.domain = domain
    }

    enum Failure: LocalizedError {
        case missing(String)
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missing(let name): "The app doesn't contain the certificate \(name)."
            case .status(let status): SecCopyErrorMessageString(status, nil) as String? ?? "Security error \(status)."
            }
        }
    }

    /// In a keychain and trusted as an anchor. A trust setting alone (with the
    /// certificate missing from every keychain) doesn't count.
    func isTrusted() throws -> Bool {
        let cert = try load()
        return isInKeychain(cert) && isTrustedAnchor(cert)
    }

    func trust() throws {
        let cert = try load()
        let add = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: cert] as CFDictionary, nil)
        guard add == errSecSuccess || add == errSecDuplicateItem else { throw Failure.status(add) }

        let settings: [[String: Any]] = [
            [kSecTrustSettingsPolicy as String: SecPolicyCreateBasicX509()],
            [kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil)],
        ]
        let status = SecTrustSettingsSetTrustSettings(cert, domain == .admin ? .admin : .user, settings as CFArray)
        switch status {
        case errSecSuccess: return
        case errAuthorizationCanceled: throw InstallerStepError.denied
        default: throw Failure.status(status)
        }
    }

    private func load() throws -> SecCertificate {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url),
              let cert = SecCertificateCreateWithData(nil, data as CFData)
        else { throw Failure.missing("\(resourceName).\(resourceExtension)") }
        return cert
    }

    private func isInKeychain(_ cert: SecCertificate) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecMatchItemList: [cert],
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func isTrustedAnchor(_ cert: SecCertificate) -> Bool {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
