import Foundation
import os

private let geminiOAuthLogger = Logger(subsystem: "com.ayangabryl.usage", category: "GeminiOAuth")

// MARK: - Data Models

struct GeminiOAuthCredentials {
    let accessToken: String?
    let idToken: String?
    let refreshToken: String?
    let expiryDate: Date?
}

struct GeminiOAuthClientCredentials {
    let clientId: String
    let clientSecret: String
}

struct GeminiTokenClaims {
    let email: String?
    let hostedDomain: String?
}

enum GeminiUserTier: String, Sendable {
    case free = "free-tier"
    case legacy = "legacy-tier"
    case standard = "standard-tier"
}

struct GeminiModelQuota: Sendable {
    let modelId: String
    let percentLeft: Double
    let resetTime: Date?
    let resetDescription: String?
}

struct GeminiQuotaSnapshot: Sendable {
    let modelQuotas: [GeminiModelQuota]
    let accountEmail: String?
    let accountPlan: String?

    /// Lowest percent left across all models (binding constraint)
    var lowestPercentLeft: Double? {
        modelQuotas.min(by: { $0.percentLeft < $1.percentLeft })?.percentLeft
    }

    /// Pro model quotas (primary)
    var proQuotas: [GeminiModelQuota] {
        modelQuotas.filter { $0.modelId.lowercased().contains("pro") }
    }

    /// Flash model quotas (secondary)
    var flashQuotas: [GeminiModelQuota] {
        modelQuotas.filter { $0.modelId.lowercased().contains("flash") }
    }

    /// Lowest Pro model percent left
    var proPercentLeft: Double? {
        proQuotas.min(by: { $0.percentLeft < $1.percentLeft })?.percentLeft
    }

    /// Lowest Flash model percent left
    var flashPercentLeft: Double? {
        flashQuotas.min(by: { $0.percentLeft < $1.percentLeft })?.percentLeft
    }

    /// Earliest reset time across all models
    var earliestReset: Date? {
        modelQuotas.compactMap(\.resetTime).min()
    }

    /// Pro model reset time
    var proResetTime: Date? {
        proQuotas.compactMap(\.resetTime).min()
    }

    /// Flash model reset time
    var flashResetTime: Date? {
        flashQuotas.compactMap(\.resetTime).min()
    }
}

enum GeminiOAuthError: LocalizedError {
    case geminiCLINotInstalled
    case notLoggedIn
    case unsupportedAuthType(String)
    case tokenExpiredNoRefresh
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .geminiCLINotInstalled:
            "Gemini CLI is not installed. Run 'npm install -g @google/gemini-cli' first."
        case .notLoggedIn:
            "Not logged in to Gemini. Run 'gemini' in Terminal to authenticate."
        case .unsupportedAuthType(let type):
            "Gemini \(type) auth not supported. Use Google account (OAuth) instead."
        case .tokenExpiredNoRefresh:
            "Token expired and no refresh token available. Run 'gemini' to re-authenticate."
        case .apiError(let msg):
            "Gemini API error: \(msg)"
        case .parseFailed(let msg):
            "Could not parse Gemini response: \(msg)"
        }
    }
}

// MARK: - OAuth Service

@MainActor
final class GeminiOAuthService: Sendable {

    private static let credentialsPath = "/.gemini/oauth_creds.json"
    private static let settingsPath = "/.gemini/settings.json"
    private static let quotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private static let projectsEndpoint = "https://cloudresourcemanager.googleapis.com/v1/projects"
    private static let tokenRefreshEndpoint = "https://oauth2.googleapis.com/token"
    private static let timeout: TimeInterval = 10.0

    // MARK: - Check if Gemini CLI OAuth is available

    /// Check if Gemini CLI OAuth credentials exist
    func hasOAuthCredentials() -> Bool {
        let credsPath = NSHomeDirectory() + Self.credentialsPath
        return FileManager.default.fileExists(atPath: credsPath)
    }

    /// Read the current auth type from Gemini CLI settings
    func currentAuthType() -> String? {
        let settingsURL = URL(fileURLWithPath: NSHomeDirectory() + Self.settingsPath)
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let security = json["security"] as? [String: Any],
              let auth = security["auth"] as? [String: Any],
              let selectedType = auth["selectedType"] as? String
        else {
            return nil
        }
        return selectedType
    }

    // MARK: - Fetch Quota

    /// Main entry point: fetch Gemini quota data using CLI OAuth credentials
    func fetchQuota() async throws -> GeminiQuotaSnapshot {
        // Check auth type
        let authType = currentAuthType()
        if authType == "api-key" {
            throw GeminiOAuthError.unsupportedAuthType("API key")
        }
        if authType == "vertex-ai" {
            throw GeminiOAuthError.unsupportedAuthType("Vertex AI")
        }

        // Load credentials
        let creds = try loadCredentials()

        guard let storedAccessToken = creds.accessToken, !storedAccessToken.isEmpty else {
            throw GeminiOAuthError.notLoggedIn
        }

        // Refresh token if expired
        var accessToken = storedAccessToken
        if let expiry = creds.expiryDate, expiry < Date() {
            geminiOAuthLogger.info("Gemini OAuth: token expired, refreshing...")
            guard let refreshToken = creds.refreshToken else {
                throw GeminiOAuthError.tokenExpiredNoRefresh
            }
            accessToken = try await refreshAccessToken(refreshToken: refreshToken)
        }

        // Extract email from JWT
        let claims = extractClaimsFromToken(creds.idToken)

        // Load Code Assist status for project ID and tier
        let caStatus = await loadCodeAssistStatus(accessToken: accessToken)

        // Discover project ID if not from loadCodeAssist
        var projectId = caStatus.projectId
        if projectId == nil {
            projectId = try? await discoverGeminiProjectId(accessToken: accessToken)
        }

        // Fetch quota
        let snapshot = try await fetchQuotaAPI(accessToken: accessToken, projectId: projectId, email: claims.email)

        // Determine plan
        let plan: String? = switch (caStatus.tier, claims.hostedDomain) {
        case (.standard, _): "Paid"
        case (.free, .some(_)): "Workspace"
        case (.free, .none): "Free"
        case (.legacy, _): "Legacy"
        case (.none, _): nil
        }

        return GeminiQuotaSnapshot(
            modelQuotas: snapshot.modelQuotas,
            accountEmail: snapshot.accountEmail,
            accountPlan: plan ?? snapshot.accountPlan
        )
    }

    // MARK: - Load Credentials

    private func loadCredentials() throws -> GeminiOAuthCredentials {
        let credsURL = URL(fileURLWithPath: NSHomeDirectory() + Self.credentialsPath)

        guard FileManager.default.fileExists(atPath: credsURL.path) else {
            throw GeminiOAuthError.notLoggedIn
        }

        let data = try Data(contentsOf: credsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiOAuthError.parseFailed("Invalid credentials file")
        }

        let accessToken = json["access_token"] as? String
        let idToken = json["id_token"] as? String
        let refreshToken = json["refresh_token"] as? String

        var expiryDate: Date?
        if let expiryMs = json["expiry_date"] as? Double {
            expiryDate = Date(timeIntervalSince1970: expiryMs / 1000)
        }

        return GeminiOAuthCredentials(
            accessToken: accessToken,
            idToken: idToken,
            refreshToken: refreshToken,
            expiryDate: expiryDate
        )
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: Self.tokenRefreshEndpoint) else {
            throw GeminiOAuthError.apiError("Invalid token refresh URL")
        }

        guard let oauthCreds = extractOAuthClientCredentials() else {
            geminiOAuthLogger.error("Could not extract OAuth credentials from Gemini CLI")
            throw GeminiOAuthError.apiError("Could not find Gemini CLI OAuth configuration. Is the Gemini CLI installed?")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout

        let body = [
            "client_id=\(oauthCreds.clientId)",
            "client_secret=\(oauthCreds.clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiOAuthError.apiError("Invalid refresh response")
        }

        guard http.statusCode == 200 else {
            geminiOAuthLogger.error("Token refresh failed: HTTP \(http.statusCode)")
            throw GeminiOAuthError.notLoggedIn
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String
        else {
            throw GeminiOAuthError.parseFailed("Could not parse refresh response")
        }

        // Update stored credentials
        try updateStoredCredentials(json)

        geminiOAuthLogger.info("Gemini OAuth: token refreshed successfully")
        return newAccessToken
    }

    private func updateStoredCredentials(_ refreshResponse: [String: Any]) throws {
        let credsURL = URL(fileURLWithPath: NSHomeDirectory() + Self.credentialsPath)

        guard let existingCreds = try? Data(contentsOf: credsURL),
              var json = try? JSONSerialization.jsonObject(with: existingCreds) as? [String: Any]
        else { return }

        if let accessToken = refreshResponse["access_token"] {
            json["access_token"] = accessToken
        }
        if let expiresIn = refreshResponse["expires_in"] as? Double {
            json["expiry_date"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        if let idToken = refreshResponse["id_token"] {
            json["id_token"] = idToken
        }

        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try updatedData.write(to: credsURL, options: .atomic)
    }

    // MARK: - OAuth Client Credentials Extraction

    /// Extract OAuth client ID/secret from the installed Gemini CLI binary
    private func extractOAuthClientCredentials() -> GeminiOAuthClientCredentials? {
        // Find gemini binary
        let geminiPath = findGeminiBinary()
        guard let geminiPath else {
            geminiOAuthLogger.warning("Gemini CLI binary not found")
            return nil
        }

        let fm = FileManager.default

        // Resolve symlinks
        var realPath = geminiPath
        if let resolved = try? fm.destinationOfSymbolicLink(atPath: geminiPath) {
            if resolved.hasPrefix("/") {
                realPath = resolved
            } else {
                realPath = (geminiPath as NSString).deletingLastPathComponent + "/" + resolved
            }
        }

        let binDir = (realPath as NSString).deletingLastPathComponent
        let baseDir = (binDir as NSString).deletingLastPathComponent

        let oauthFile = "dist/src/code_assist/oauth2.js"
        let possiblePaths = [
            // Homebrew nested structure
            "\(baseDir)/libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            "\(baseDir)/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            // Nix package layout
            "\(baseDir)/share/gemini-cli/node_modules/@google/gemini-cli-core/\(oauthFile)",
            // Bun/npm sibling structure
            "\(baseDir)/../gemini-cli-core/\(oauthFile)",
            // npm nested inside gemini-cli
            "\(baseDir)/node_modules/@google/gemini-cli-core/\(oauthFile)",
        ]

        for path in possiblePaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                if let creds = parseOAuthClientCredentials(from: content) {
                    geminiOAuthLogger.info("Extracted OAuth credentials from: \(path)")
                    return creds
                }
            }
        }

        geminiOAuthLogger.warning("Could not find oauth2.js in any known location")
        return nil
    }

    private func findGeminiBinary() -> String? {
        let env = ProcessInfo.processInfo.environment
        let pathDirs = (env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin").components(separatedBy: ":")

        for dir in pathDirs {
            let candidate = "\(dir)/gemini"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Check common locations
        let commonPaths = [
            "/usr/local/bin/gemini",
            "/opt/homebrew/bin/gemini",
            "\(NSHomeDirectory())/.bun/bin/gemini",
            "\(NSHomeDirectory())/.npm-global/bin/gemini",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin/gemini",
        ]

        for path in commonPaths {
            // Handle glob patterns
            if path.contains("*") {
                let dir = (path as NSString).deletingLastPathComponent
                let baseName = (path as NSString).lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: (dir as NSString).deletingLastPathComponent) {
                    for entry in contents {
                        let candidate = "\((dir as NSString).deletingLastPathComponent)/\(entry)/\(baseName)"
                        if FileManager.default.isExecutableFile(atPath: candidate) {
                            return candidate
                        }
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func parseOAuthClientCredentials(from content: String) -> GeminiOAuthClientCredentials? {
        let clientIdPattern = #"OAUTH_CLIENT_ID\s*=\s*['"]([\w\-\.]+)['"]\s*;"#
        let secretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*['"]([\w\-]+)['"]\s*;"#

        guard let clientIdRegex = try? NSRegularExpression(pattern: clientIdPattern),
              let secretRegex = try? NSRegularExpression(pattern: secretPattern)
        else { return nil }

        let range = NSRange(content.startIndex..., in: content)

        guard let clientIdMatch = clientIdRegex.firstMatch(in: content, range: range),
              let clientIdRange = Range(clientIdMatch.range(at: 1), in: content),
              let secretMatch = secretRegex.firstMatch(in: content, range: range),
              let secretRange = Range(secretMatch.range(at: 1), in: content)
        else { return nil }

        let clientId = String(content[clientIdRange])
        let clientSecret = String(content[secretRange])

        return GeminiOAuthClientCredentials(clientId: clientId, clientSecret: clientSecret)
    }

    // MARK: - JWT Claims

    private func extractClaimsFromToken(_ idToken: String?) -> GeminiTokenClaims {
        guard let token = idToken else { return GeminiTokenClaims(email: nil, hostedDomain: nil) }

        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return GeminiTokenClaims(email: nil, hostedDomain: nil) }

        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return GeminiTokenClaims(email: nil, hostedDomain: nil)
        }

        return GeminiTokenClaims(
            email: json["email"] as? String,
            hostedDomain: json["hd"] as? String
        )
    }

    // MARK: - Code Assist Status (Tier + Project)

    private struct CodeAssistStatus {
        let tier: GeminiUserTier?
        let projectId: String?

        static let empty = CodeAssistStatus(tier: nil, projectId: nil)
    }

    private func loadCodeAssistStatus(accessToken: String) async -> CodeAssistStatus {
        guard let url = URL(string: Self.loadCodeAssistEndpoint) else { return .empty }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8)
        request.timeoutInterval = Self.timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .empty
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .empty
            }

            // Extract project ID
            let rawProjectId: String? = {
                if let project = json["cloudaicompanionProject"] as? String {
                    return project
                }
                if let project = json["cloudaicompanionProject"] as? [String: Any] {
                    if let projectId = project["id"] as? String { return projectId }
                    if let projectId = project["projectId"] as? String { return projectId }
                }
                return nil
            }()
            let projectId: String? = {
                guard let raw = rawProjectId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { return nil }
                return raw
            }()

            // Extract tier
            let tierId = (json["currentTier"] as? [String: Any])?["id"] as? String
            let tier = tierId.flatMap { GeminiUserTier(rawValue: $0) }

            geminiOAuthLogger.info("Gemini loadCodeAssist: tier=\(tierId ?? "nil"), project=\(projectId ?? "nil")")
            return CodeAssistStatus(tier: tier, projectId: projectId)

        } catch {
            geminiOAuthLogger.warning("Gemini loadCodeAssist failed: \(error)")
            return .empty
        }
    }

    // MARK: - Project Discovery

    private func discoverGeminiProjectId(accessToken: String) async throws -> String? {
        guard let url = URL(string: Self.projectsEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]]
        else { return nil }

        for project in projects {
            guard let projectId = project["projectId"] as? String else { continue }

            if projectId.hasPrefix("gen-lang-client") {
                return projectId
            }

            if let labels = project["labels"] as? [String: String],
               labels["generative-language"] != nil {
                return projectId
            }
        }

        return nil
    }

    // MARK: - Quota API

    private func fetchQuotaAPI(accessToken: String, projectId: String?, email: String?) async throws -> GeminiQuotaSnapshot {
        guard let url = URL(string: Self.quotaEndpoint) else {
            throw GeminiOAuthError.apiError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout

        if let projectId {
            request.httpBody = Data("{\"project\": \"\(projectId)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiOAuthError.apiError("Invalid response")
        }

        if http.statusCode == 401 {
            throw GeminiOAuthError.notLoggedIn
        }

        guard http.statusCode == 200 else {
            throw GeminiOAuthError.apiError("HTTP \(http.statusCode)")
        }

        return try parseQuotaResponse(data, email: email)
    }

    // MARK: - Response Parsing

    private struct QuotaBucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelId: String?
        let tokenType: String?
    }

    private struct QuotaResponse: Decodable {
        let buckets: [QuotaBucket]?
    }

    private func parseQuotaResponse(_ data: Data, email: String?) throws -> GeminiQuotaSnapshot {
        let response = try JSONDecoder().decode(QuotaResponse.self, from: data)

        guard let buckets = response.buckets, !buckets.isEmpty else {
            throw GeminiOAuthError.parseFailed("No quota buckets in response")
        }

        // Group quotas by model, keeping lowest per model
        var modelQuotaMap: [String: (fraction: Double, resetString: String?)] = [:]

        for bucket in buckets {
            guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }

            if let existing = modelQuotaMap[modelId] {
                if fraction < existing.fraction {
                    modelQuotaMap[modelId] = (fraction, bucket.resetTime)
                }
            } else {
                modelQuotaMap[modelId] = (fraction, bucket.resetTime)
            }
        }

        let quotas = modelQuotaMap
            .sorted { $0.key < $1.key }
            .map { modelId, info in
                let resetDate = info.resetString.flatMap { parseResetTime($0) }
                return GeminiModelQuota(
                    modelId: modelId,
                    percentLeft: info.fraction * 100,
                    resetTime: resetDate,
                    resetDescription: info.resetString.flatMap { formatResetTime($0) }
                )
            }

        return GeminiQuotaSnapshot(
            modelQuotas: quotas,
            accountEmail: email,
            accountPlan: nil
        )
    }

    // MARK: - Time Formatting

    private func parseResetTime(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    private func formatResetTime(_ isoString: String) -> String {
        guard let resetDate = parseResetTime(isoString) else { return "Resets soon" }

        let interval = resetDate.timeIntervalSince(Date())
        if interval <= 0 { return "Resets soon" }

        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}
