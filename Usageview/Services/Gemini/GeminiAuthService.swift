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
        loadToken(key: apiKey(for: accountId)) != nil
            || oauthService.hasCredentials(for: accountId)
    }

    /// Whether this account uses Google OAuth
    func isOAuthAccount(for accountId: UUID) -> Bool {
        oauthService.hasCredentials(for: accountId)
    }

    /// Store the user-provided API key
    func saveAPIKey(_ key: String, for accountId: UUID) -> GeminiAccountInfo {
        saveToken(key: apiKey(for: accountId), value: key)
        // Remove OAuth tokens if switching
        oauthService.removeTokens(for: accountId)
        let masked = key.count > 8
            ? String(key.prefix(8)) + "..."
            : key
        return GeminiAccountInfo(name: masked)
    }

    /// Start direct Google OAuth browser flow
    func startOAuth(for accountId: UUID) async throws -> GeminiAccountInfo {
        let (code, codeVerifier, redirectURI) = try await oauthService.startOAuthFlow()
        let info = try await oauthService.exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI,
            for: accountId
        )
        // Remove API key if switching
        removeToken(key: apiKey(for: accountId))
        return info
    }

    /// Cancel any in-progress OAuth flow
    func cancelOAuth() {
        oauthService.cancelOAuth()
    }

    /// Retrieve the stored API key
    func getAPIKey(for accountId: UUID) -> String? {
        loadToken(key: apiKey(for: accountId))
    }

    func disconnect(accountId: UUID) {
        removeToken(key: apiKey(for: accountId))
        oauthService.removeTokens(for: accountId)
    }

    // MARK: - Key Helpers

    private func apiKey(for id: UUID) -> String {
        "com.ayangabryl.usage.gemini-apikey-\(id.uuidString)"
    }

    // MARK: - Keychain Storage

    private func saveToken(key: String, value: String) { KeychainHelper.save(value, forKey: key) }
    private func loadToken(key: String) -> String? { KeychainHelper.load(forKey: key) }
    private func removeToken(key: String) { KeychainHelper.remove(forKey: key) }
}
