import Foundation
import Security

struct CursorAccountInfo: Sendable {
    var name: String?
    var email: String?
}

@Observable
@MainActor
final class CursorAuthService: Sendable {

    // MARK: - Multi-Account Auth

    func isAuthenticated(for accountId: UUID) -> Bool {
        loadToken(key: tokenKey(for: accountId)) != nil
    }

    /// Store the user-provided session token (from browser Cookie header)
    func saveToken(_ token: String, for accountId: UUID) -> CursorAccountInfo {
        saveTokenValue(key: tokenKey(for: accountId), value: token)
        let masked = token.count > 12
            ? String(token.prefix(12)) + "..."
            : token
        return CursorAccountInfo(name: masked)
    }

    /// Retrieve the stored session token
    func getToken(for accountId: UUID) -> String? {
        loadToken(key: tokenKey(for: accountId))
    }

    func disconnect(accountId: UUID) {
        removeToken(key: tokenKey(for: accountId))
    }

    // MARK: - Key Helpers

    private func tokenKey(for id: UUID) -> String {
        "com.ayangabryl.usage.cursor-token-\(id.uuidString)"
    }

    // MARK: - Keychain Storage

    private func saveTokenValue(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadToken(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func removeToken(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
