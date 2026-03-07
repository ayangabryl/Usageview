import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "KimiUsage")

struct KimiUsageData: Sendable {
    var isActive: Bool
    var hasQuotaData: Bool = false

    // Weekly quota
    var weeklyUsed: Double = 0
    var weeklyLimit: Double = 0
    var weeklyResetDate: Date?

    // 5-hour rate limit
    var rateLimitUsed: Double = 0
    var rateLimitMax: Double = 0
    var rateLimitResetDate: Date?
}

@MainActor
final class KimiUsageService: Sendable {
    private let authService: KimiAuthService

    init(authService: KimiAuthService) {
        self.authService = authService
    }

    /// Fetch usage from Kimi billing API (gRPC-Web endpoint), falling back to key validation
    func fetchUsage(for accountId: UUID) async -> KimiUsageData? {
        guard let apiKey = authService.getAPIKey(for: accountId) else { return nil }

        // Try the Kimi billing API first (web-style, same endpoint CodexBar uses)
        if let billingData = await fetchBillingUsage(token: apiKey) {
            return billingData
        }

        // Fallback: verify key via Moonshot API
        return await verifyMoonshotKey(apiKey: apiKey)
    }

    /// Call the Kimi billing API endpoint (gRPC-Web style)
    private func fetchBillingUsage(token: String) async -> KimiUsageData? {
        guard let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("en-US", forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")

        // Add session info from JWT if decodable
        if let sessionInfo = decodeJWTSessionInfo(from: token) {
            if let deviceId = sessionInfo["device_id"] {
                request.setValue(deviceId, forHTTPHeaderField: "x-msh-device-id")
            }
            if let sessionId = sessionInfo["ssid"] {
                request.setValue(sessionId, forHTTPHeaderField: "x-msh-session-id")
            }
            if let trafficId = sessionInfo["sub"] {
                request.setValue(trafficId, forHTTPHeaderField: "x-traffic-id")
            }
        }

        let body: [String: Any] = ["scope": ["FEATURE_CODING"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard http.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                logger.info("Kimi billing API \(http.statusCode): \(bodyStr.prefix(200))")
                return nil
            }

            return parseBillingResponse(data: data)
        } catch {
            logger.error("Kimi billing fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseBillingResponse(data: Data) -> KimiUsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usages = json["usages"] as? [[String: Any]]
        else {
            return nil
        }

        // Find FEATURE_CODING scope
        guard let codingUsage = usages.first(where: { ($0["scope"] as? String) == "FEATURE_CODING" }) else {
            return nil
        }

        var result = KimiUsageData(isActive: true, hasQuotaData: true)

        // Parse weekly detail
        if let detail = codingUsage["detail"] as? [String: Any] {
            result.weeklyUsed = parseNumber(detail["used"]) ?? 0
            result.weeklyLimit = parseNumber(detail["limit"]) ?? 0
            result.weeklyResetDate = parseISO8601(detail["resetTime"] as? String)
        }

        // Parse rate limit (5-hour window)
        if let limits = codingUsage["limits"] as? [[String: Any]],
           let firstLimit = limits.first,
           let limitDetail = firstLimit["detail"] as? [String: Any] {
            result.rateLimitUsed = parseNumber(limitDetail["used"]) ?? 0
            result.rateLimitMax = parseNumber(limitDetail["limit"]) ?? 0
            result.rateLimitResetDate = parseISO8601(limitDetail["resetTime"] as? String)
        }

        logger.info("Kimi billing: \(Int(result.weeklyUsed), privacy: .public)/\(Int(result.weeklyLimit), privacy: .public) weekly, \(Int(result.rateLimitUsed), privacy: .public)/\(Int(result.rateLimitMax), privacy: .public) rate limit")

        return result
    }

    /// Fallback: verify Moonshot API key validity
    private func verifyMoonshotKey(apiKey: String) async -> KimiUsageData? {
        let url = URL(string: "https://api.moonshot.cn/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return KimiUsageData(isActive: true)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func parseNumber(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func parseISO8601(_ str: String?) -> Date? {
        guard let str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    /// Decode JWT payload to extract session-specific headers
    private func decodeJWTSessionInfo(from jwt: String) -> [String: String]? {
        let parts = jwt.split(separator: ".", maxSplits: 2)
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }

        guard let payloadData = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }

        var result: [String: String] = [:]
        if let v = json["device_id"] as? String { result["device_id"] = v }
        if let v = json["ssid"] as? String { result["ssid"] = v }
        if let v = json["sub"] as? String { result["sub"] = v }
        return result.isEmpty ? nil : result
    }
}
