import Foundation
import Security
import AppKit

struct GitHubAccountInfo: Sendable {
    var username: String
    var avatarURL: String?
}

@Observable
@MainActor
final class GitHubAuthService: Sendable {
    var isLoading: Bool = false
    var userCode: String?

    private let clientId = "Iv1.b507a08c87ecfe98"

    // MARK: - Multi-Account Auth

    func isAuthenticated(for accountId: UUID) -> Bool {
        loadToken(key: tokenKey(for: accountId)) != nil
    }

    func token(for accountId: UUID) -> String? {
        loadToken(key: tokenKey(for: accountId))
    }

    /// Start the GitHub Device Flow for a specific account
    func startDeviceFlow(for accountId: UUID) async -> GitHubAccountInfo? {
        isLoading = true
        defer {
            isLoading = false
            userCode = nil
        }

        // Step 1: Request device + user codes
        let codeURL = URL(string: "https://github.com/login/device/code")!
        var codeRequest = URLRequest(url: codeURL)
        codeRequest.httpMethod = "POST"
        codeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        codeRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        codeRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": clientId,
            "scope": "read:user"
        ])

        guard let (codeData, _) = try? await URLSession.shared.data(for: codeRequest),
              let codeJSON = try? JSONSerialization.jsonObject(with: codeData) as? [String: Any],
              let dCode = codeJSON["device_code"] as? String,
              let uCode = codeJSON["user_code"] as? String,
              let verificationURI = codeJSON["verification_uri"] as? String,
              let interval = codeJSON["interval"] as? Int
        else { return nil }

        userCode = uCode

        // Step 2: Open browser
        if let url = URL(string: verificationURI) {
            NSWorkspace.shared.open(url)
        }

        // Step 3: Poll for access token
        let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

        while true {
            try? await Task.sleep(for: .seconds(interval))

            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            tokenRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
                "client_id": clientId,
                "device_code": dCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])

            guard let (tokenData, _) = try? await URLSession.shared.data(for: tokenRequest),
                  let tokenJSON = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any]
            else { continue }

            if let accessToken = tokenJSON["access_token"] as? String {
                saveToken(key: tokenKey(for: accountId), value: accessToken)
                return await fetchUserInfo(token: accessToken)
            }

            if let error = tokenJSON["error"] as? String {
                if error == "authorization_pending" { continue }
                return nil
            }
        }
    }

    func disconnect(accountId: UUID) {
        removeToken(key: tokenKey(for: accountId))
    }

    // MARK: - Helpers

    private func fetchUserInfo(token: String) async -> GitHubAccountInfo? {
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String
        else { return nil }

        let avatarURL = json["avatar_url"] as? String
        return GitHubAccountInfo(username: login, avatarURL: avatarURL)
    }

    private func tokenKey(for id: UUID) -> String {
        "com.ayangabryl.usage.github-token-\(id.uuidString)"
    }

    // MARK: - Token Storage

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
