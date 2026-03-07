import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "OpenAIUsage")

struct ChatGPTUsageData: Sendable {
    var planName: String
    var isSubscribed: Bool

    // Rate limit windows (from /wham/usage)
    var fiveHourUsedPercent: Int?
    var fiveHourResetAt: Date?
    var weeklyUsedPercent: Int?
    var weeklyResetAt: Date?

    // Credits
    var hasCredits: Bool = false
    var creditsUnlimited: Bool = false
    var creditsBalance: Double?
}

@MainActor
final class OpenAIUsageService: Sendable {
    private let authService: OpenAIAuthService

    init(authService: OpenAIAuthService) {
        self.authService = authService
    }

    /// Fetch ChatGPT usage data (rate limits + plan info)
    func fetchStatus(for accountId: UUID) async -> ChatGPTUsageData? {
        // Try OAuth token first, fall back to API key
        let token: String? = await authService.getValidToken(for: accountId)
        let apiKey: String? = authService.getAPIKey(for: accountId)

        logger.info("ChatGPT fetchStatus: hasOAuthToken=\(token != nil) hasAPIKey=\(apiKey != nil)")

        guard let bearer = token ?? apiKey else {
            logger.error("ChatGPT: no valid token or API key available")
            return nil
        }

        // If we have an OAuth token, try /wham/usage for rate limit data
        if token != nil {
            logger.info("ChatGPT: trying /wham/usage with OAuth token")
            if let usageData = await fetchWhamUsage(bearer: bearer, accountId: accountId) {
                return usageData
            }
            logger.info("ChatGPT: /wham/usage failed, falling back to /me")
        }

        // Fallback: verify connection via /me
        return await fetchMeStatus(bearer: bearer, accountId: accountId)
    }

    /// Fetch rate limit usage from the wham/usage endpoint (same as CodexBar)
    private func fetchWhamUsage(bearer: String, accountId: UUID) async -> ChatGPTUsageData? {
        // Try primary URL, fall back to alternative
        let urls = [
            "https://chatgpt.com/backend-api/wham/usage",
            "https://chatgpt.com/api/codex/usage"
        ]

        let chatgptAccId = authService.chatgptAccountId(for: accountId)
        logger.info("ChatGPT: fetching usage (chatgpt_account_id=\(chatgptAccId != nil))")

        for urlStr in urls {
            guard let url = URL(string: urlStr) else { continue }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            if let chatgptAccId {
                request.setValue(chatgptAccId, forHTTPHeaderField: "ChatGPT-Account-Id")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                let body = String(data: data, encoding: .utf8) ?? ""

                guard http.statusCode == 200 else {
                    logger.warning("ChatGPT \(urlStr) failed (HTTP \(http.statusCode)): \(body.prefix(300), privacy: .public)")
                    continue
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.warning("ChatGPT \(urlStr): not valid JSON: \(body.prefix(200), privacy: .public)")
                    continue
                }

                logger.info("ChatGPT usage response from \(urlStr): \(body.prefix(500), privacy: .public)")

                let planType = json["plan_type"] as? String ?? "free"

                var result = ChatGPTUsageData(planName: planType, isSubscribed: true)

                // Parse rate_limit
                if let rateLimit = json["rate_limit"] as? [String: Any] {
                    // Primary window (5-hour)
                    if let primary = rateLimit["primary_window"] as? [String: Any] {
                        result.fiveHourUsedPercent = primary["used_percent"] as? Int
                        if let resetAt = primary["reset_at"] as? Int {
                            result.fiveHourResetAt = Date(timeIntervalSince1970: TimeInterval(resetAt))
                        } else if let resetAt = primary["reset_at"] as? Double {
                            result.fiveHourResetAt = Date(timeIntervalSince1970: resetAt)
                        }
                    }

                    // Secondary window (weekly)
                    if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                        result.weeklyUsedPercent = secondary["used_percent"] as? Int
                        if let resetAt = secondary["reset_at"] as? Int {
                            result.weeklyResetAt = Date(timeIntervalSince1970: TimeInterval(resetAt))
                        } else if let resetAt = secondary["reset_at"] as? Double {
                            result.weeklyResetAt = Date(timeIntervalSince1970: resetAt)
                        }
                    }
                }

                // Parse credits
                if let credits = json["credits"] as? [String: Any] {
                    result.hasCredits = credits["has_credits"] as? Bool ?? false
                    result.creditsUnlimited = credits["unlimited"] as? Bool ?? false
                    if let balance = credits["balance"] as? Double {
                        result.creditsBalance = balance
                    } else if let balanceStr = credits["balance"] as? String,
                              let balance = Double(balanceStr) {
                        result.creditsBalance = balance
                    }
                }

                // If we got rate limit data, great — return it
                if result.fiveHourUsedPercent != nil || result.weeklyUsedPercent != nil {
                    logger.info("ChatGPT usage: plan=\(planType) 5h=\(result.fiveHourUsedPercent ?? -1)% weekly=\(result.weeklyUsedPercent ?? -1)%")
                    return result
                }

                // Got a 200 with plan_type but no rate_limit — still useful
                logger.info("ChatGPT usage: plan=\(planType) but no rate_limit data")
                return result

            } catch {
                logger.error("ChatGPT \(urlStr) error: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        return nil
    }

    /// Fallback: just verify the token via /me and get the plan name
    private func fetchMeStatus(bearer: String, accountId: UUID) async -> ChatGPTUsageData? {
        let url = URL(string: "https://chatgpt.com/backend-api/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        if let chatgptAccountId = authService.chatgptAccountId(for: accountId) {
            request.setValue(chatgptAccountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let plan = json["plan_type"] as? String
                    ?? json["plan"] as? String
                    ?? "Connected"
                return ChatGPTUsageData(planName: plan, isSubscribed: true)
            }
            return ChatGPTUsageData(planName: "Connected", isSubscribed: true)
        } catch {
            logger.error("ChatGPT /me error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
