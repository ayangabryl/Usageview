import Foundation
import Security

struct OpenRouterAccountInfo: Sendable {
    var name: String?
}

@Observable
@MainActor
final class OpenRouterAuthService: Sendable {

    // MARK: - Multi-Account Auth

    func isAuthenticated(for accountId: UUID) -> Bool {
        loadToken(key: apiKey(for: accountId)) != nil
    }

    /// Store the user-provided API key
    func saveAPIKey(_ key: String, for accountId: UUID) -> OpenRouterAccountInfo {
        saveToken(key: apiKey(for: accountId), value: key)
        let masked = key.count > 12
            ? String(key.prefix(12)) + "..."
            : key
        return OpenRouterAccountInfo(name: masked)
    }

    /// Retrieve the stored API key
    func getAPIKey(for accountId: UUID) -> String? {
        loadToken(key: apiKey(for: accountId))
    }

    func disconnect(accountId: UUID) {
        removeToken(key: apiKey(for: accountId))
    }

    // MARK: - Key Helpers

    private func apiKey(for id: UUID) -> String {
        "com.ayangabryl.usage.openrouter-apikey-\(id.uuidString)"
    }

    // MARK: - Keychain Storage

    private func saveToken(key: String, value: String) { KeychainHelper.save(value, forKey: key) }
    private func loadToken(key: String) -> String? { KeychainHelper.load(forKey: key) }
    private func removeToken(key: String) { KeychainHelper.remove(forKey: key) }
}
