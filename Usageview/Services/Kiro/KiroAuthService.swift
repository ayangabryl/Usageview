import Foundation
import Security

struct KiroAccountInfo: Sendable {
    var name: String?
}

@Observable
@MainActor
final class KiroAuthService: Sendable {

    func isAuthenticated(for accountId: UUID) -> Bool {
        loadToken(key: apiKey(for: accountId)) != nil
    }

    func saveAPIKey(_ key: String, for accountId: UUID) -> KiroAccountInfo {
        saveToken(key: apiKey(for: accountId), value: key)
        let masked = key.count > 8
            ? String(key.prefix(8)) + "..."
            : key
        return KiroAccountInfo(name: masked)
    }

    func getAPIKey(for accountId: UUID) -> String? {
        loadToken(key: apiKey(for: accountId))
    }

    func disconnect(accountId: UUID) {
        removeToken(key: apiKey(for: accountId))
    }

    private func apiKey(for id: UUID) -> String {
        "com.ayangabryl.usage.kiro-apikey-\(id.uuidString)"
    }

    // MARK: - Keychain

    // MARK: - Keychain Storage

    private func saveToken(key: String, value: String) { KeychainHelper.save(value, forKey: key) }
    private func loadToken(key: String) -> String? { KeychainHelper.load(forKey: key) }
    private func removeToken(key: String) { KeychainHelper.remove(forKey: key) }
}
