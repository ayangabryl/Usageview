import Foundation
import Security

struct GeminiAccountInfo: Sendable {
    var name: String?
    var email: String?
    var isOAuth: Bool = false
}

@Observable
@MainActor
final class GeminiAuthService: Sendable {

    let oauthService = GeminiOAuthService()

    // MARK: - Multi-Account Auth

    func isAuthenticated(for accountId: UUID) -> Bool {
        // Check API key first, then OAuth marker
        loadToken(key: apiKey(for: accountId)) != nil
            || loadToken(key: oauthMarker(for: accountId)) != nil
    }

    /// Whether this account uses Gemini CLI OAuth
    func isOAuthAccount(for accountId: UUID) -> Bool {
        loadToken(key: oauthMarker(for: accountId)) != nil
    }

    /// Store the user-provided API key
    func saveAPIKey(_ key: String, for accountId: UUID) -> GeminiAccountInfo {
        saveToken(key: apiKey(for: accountId), value: key)
        // Remove OAuth marker if switching
        removeToken(key: oauthMarker(for: accountId))
        let masked = key.count > 8
            ? String(key.prefix(8)) + "..."
            : key
        return GeminiAccountInfo(name: masked)
    }

    /// Connect via Gemini CLI OAuth (reads ~/.gemini/oauth_creds.json)
    func connectOAuth(for accountId: UUID) async throws -> GeminiAccountInfo {
        guard oauthService.hasOAuthCredentials() else {
            throw GeminiOAuthError.notLoggedIn
        }

        // Test that we can actually fetch quota
        let snapshot = try await oauthService.fetchQuota()

        // Store an OAuth marker so we know this account uses OAuth
        saveToken(key: oauthMarker(for: accountId), value: "oauth-connected")
        // Remove API key if switching
        removeToken(key: apiKey(for: accountId))

        return GeminiAccountInfo(
            name: snapshot.accountEmail ?? snapshot.accountPlan ?? "Gemini Pro",
            email: snapshot.accountEmail,
            isOAuth: true
        )
    }

    /// Retrieve the stored API key
    func getAPIKey(for accountId: UUID) -> String? {
        loadToken(key: apiKey(for: accountId))
    }

    func disconnect(accountId: UUID) {
        removeToken(key: apiKey(for: accountId))
        removeToken(key: oauthMarker(for: accountId))
    }

    // MARK: - Key Helpers

    private func apiKey(for id: UUID) -> String {
        "com.ayangabryl.usage.gemini-apikey-\(id.uuidString)"
    }

    private func oauthMarker(for id: UUID) -> String {
        "com.ayangabryl.usage.gemini-oauth-\(id.uuidString)"
    }

    // MARK: - Keychain Storage

    private func saveToken(key: String, value: String) {
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
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
