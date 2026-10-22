import Foundation
import Security

/// Session token kept in the login keychain, never in UserDefaults.
enum CredentialStore {
    /// The bundle identifier, so a renamed or demo build never reads another build's session.
    private static let service = Bundle.main.bundleIdentifier ?? "Macfin"
    private static let account = "session"

    static func load() -> Credentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func save(_ credentials: Credentials) {
        delete()
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account,
                                   kSecAttrLabel as String: "Macfin Jellyfin session",
                                   kSecValueData as String: data]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
