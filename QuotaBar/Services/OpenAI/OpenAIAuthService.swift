import Foundation
import Security
import CryptoKit
import AppKit

struct OpenAIAccountInfo: Sendable {
    var email: String?
    var name: String?
    var accountId: String?
}

@Observable
@MainActor
final class OpenAIAuthService: Sendable {
    var isLoading: Bool = false
    var userCode: String?

    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let issuer = "https://auth.openai.com"

    // MARK: - Multi-Account Auth

    func isAuthenticated(for accountId: UUID) -> Bool {
        loadToken(key: refreshKey(for: accountId)) != nil
            || loadToken(key: apiKeyKey(for: accountId)) != nil
    }

    // MARK: - API Key Auth

    /// Store a user-provided OpenAI API key
    func saveAPIKey(_ key: String, for accountId: UUID) -> OpenAIAccountInfo {
        saveToken(key: apiKeyKey(for: accountId), value: key)
        let masked = key.count > 8
            ? String(key.prefix(8)) + "..."
            : key
        return OpenAIAccountInfo(email: nil, name: masked, accountId: nil)
    }

    /// Retrieve the stored API key
    func getAPIKey(for accountId: UUID) -> String? {
        loadToken(key: apiKeyKey(for: accountId))
    }

    /// Verify an OpenAI API key is valid by calling /v1/models
    func verifyAPIKey(for accountId: UUID) async -> Bool {
        guard let key = getAPIKey(for: accountId) else { return false }

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    func token(for accountId: UUID) -> String? {
        loadToken(key: accessKey(for: accountId))
    }

    /// Start OpenAI device code flow
    func startDeviceFlow(for accountId: UUID) async -> OpenAIAccountInfo? {
        isLoading = true
        defer {
            isLoading = false
            userCode = nil
        }

        // Step 1: Request device + user codes
        let codeURL = URL(string: "\(issuer)/api/accounts/deviceauth/usercode")!
        var codeRequest = URLRequest(url: codeURL)
        codeRequest.httpMethod = "POST"
        codeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        codeRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        codeRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": clientId
        ])

        guard let (codeData, _) = try? await URLSession.shared.data(for: codeRequest),
              let codeJSON = try? JSONSerialization.jsonObject(with: codeData) as? [String: Any],
              let uCode = codeJSON["user_code"] as? String,
              let deviceAuthId = codeJSON["device_auth_id"] as? String
        else { return nil }

        userCode = uCode

        // Step 2: Open browser for user to enter code
        if let url = URL(string: "\(issuer)/codex/device") {
            NSWorkspace.shared.open(url)
        }

        // Step 3: Poll for authorization
        let intervalStr = codeJSON["interval"] as? String
        let intervalNum = codeJSON["interval"] as? Int
        let interval = intervalNum ?? (Int(intervalStr ?? "") ?? 5)
        let tokenURL = URL(string: "\(issuer)/api/accounts/deviceauth/token")!
        let startDate = Date()
        let maxWait: TimeInterval = 15 * 60 // 15 minutes

        while Date().timeIntervalSince(startDate) < maxWait {
            try? await Task.sleep(for: .seconds(interval))

            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            tokenRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
                "device_auth_id": deviceAuthId,
                "user_code": uCode
            ])

            guard let (tokenData, tokenResponse) = try? await URLSession.shared.data(for: tokenRequest)
            else { continue }

            let httpStatus = (tokenResponse as? HTTPURLResponse)?.statusCode ?? 0

            // 403/404 = authorization still pending, keep polling
            if httpStatus == 403 || httpStatus == 404 {
                continue
            }

            guard httpStatus == 200,
                  let tokenJSON = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any]
            else { continue }

            // Device flow returns authorization_code + code_verifier
            if let authCode = tokenJSON["authorization_code"] as? String,
               let codeVerifier = tokenJSON["code_verifier"] as? String {
                // Exchange the auth code for actual tokens
                let info = await exchangeDeviceCode(
                    authCode: authCode,
                    codeVerifier: codeVerifier,
                    accountId: accountId
                )
                return info
            }

            // Unexpected response
            return nil
        }

        // Timed out
        return nil
        }
    }

    /// Exchange device flow auth code for tokens
    private func exchangeDeviceCode(authCode: String, codeVerifier: String, accountId: UUID) async -> OpenAIAccountInfo? {
        let url = URL(string: "\(issuer)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": authCode,
            "code_verifier": codeVerifier,
            "redirect_uri": "\(issuer)/deviceauth/callback"
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String,
               let refreshToken = json["refresh_token"] as? String {

                let expiresIn = json["expires_in"] as? Double ?? 3600
                saveToken(key: accessKey(for: accountId), value: accessToken)
                saveToken(key: refreshKey(for: accountId), value: refreshToken)
                UserDefaults.standard.set(
                    Date.now.timeIntervalSince1970 + expiresIn,
                    forKey: expiresKey(for: accountId)
                )

                // Extract identity from JWT id_token or access_token
                let idToken = json["id_token"] as? String
                return extractIdentity(from: idToken ?? accessToken)
            }
        } catch {}
        return nil
    }

    /// Get a valid access token, refreshing if needed
    func getValidToken(for accountId: UUID) async -> String? {
        guard let refresh = loadToken(key: refreshKey(for: accountId)) else { return nil }

        let expiresAt = UserDefaults.standard.double(forKey: expiresKey(for: accountId))
        if let access = loadToken(key: accessKey(for: accountId)),
           Date.now.timeIntervalSince1970 < expiresAt {
            return access
        }

        // Refresh
        let url = URL(string: "\(issuer)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccess = json["access_token"] as? String {
                if let newRefresh = json["refresh_token"] as? String {
                    saveToken(key: refreshKey(for: accountId), value: newRefresh)
                }
                let expiresIn = json["expires_in"] as? Double ?? 3600
                saveToken(key: accessKey(for: accountId), value: newAccess)
                UserDefaults.standard.set(
                    Date.now.timeIntervalSince1970 + expiresIn,
                    forKey: expiresKey(for: accountId)
                )
                return newAccess
            }
        } catch {}
        return nil
    }

    /// Get the ChatGPT account ID (for API requests header)
    func chatgptAccountId(for accountId: UUID) -> String? {
        guard let token = loadToken(key: accessKey(for: accountId)) else { return nil }
        let info = extractIdentity(from: token)
        return info?.accountId
    }

    func disconnect(accountId: UUID) {
        removeToken(key: accessKey(for: accountId))
        removeToken(key: refreshKey(for: accountId))
        removeToken(key: apiKeyKey(for: accountId))
        UserDefaults.standard.removeObject(forKey: expiresKey(for: accountId))
    }

    // MARK: - JWT Identity Extraction

    /// Decode JWT payload to get email/name/account_id
    private func extractIdentity(from jwt: String) -> OpenAIAccountInfo? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        // Pad base64 string
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        // Convert base64url to base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let email = json["email"] as? String
        let name = json["name"] as? String
        let accountId = json["chatgpt_account_id"] as? String
            ?? json["https://api.openai.com/auth.chatgpt_account_id"] as? String

        return OpenAIAccountInfo(email: email, name: name, accountId: accountId)
    }

    // MARK: - Key Helpers

    private func accessKey(for id: UUID) -> String {
        "com.ayangabryl.usage.openai-access-\(id.uuidString)"
    }

    private func refreshKey(for id: UUID) -> String {
        "com.ayangabryl.usage.openai-refresh-\(id.uuidString)"
    }

    private func expiresKey(for id: UUID) -> String {
        "openai_token_expires_\(id.uuidString)"
    }

    private func apiKeyKey(for id: UUID) -> String {
        "com.ayangabryl.usage.openai-apikey-\(id.uuidString)"
    }

    // MARK: - Token Storage (Keychain)

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
