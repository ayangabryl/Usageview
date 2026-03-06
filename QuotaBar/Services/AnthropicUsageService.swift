import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "AnthropicUsage")

struct ClaudeUsageData: Sendable {
    var fiveHourUtilization: Double
    var fiveHourResetsAt: Date?
    var sevenDayUtilization: Double
    var sevenDayResetsAt: Date?
}

@MainActor
final class AnthropicUsageService: Sendable {
    private let authService: AnthropicAuthService

    init(authService: AnthropicAuthService) {
        self.authService = authService
    }

    func fetchUsage(for accountId: UUID) async -> ClaudeUsageData? {
        guard let token = await authService.getValidToken(for: accountId) else {
            logger.error("No valid token for account \(accountId.uuidString)")
            return nil
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        // Retry up to 5 times on 429 (rate limit on the usage endpoint itself)
        for attempt in 0..<5 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 200 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    logger.info("Usage response: \(bodyStr.prefix(500))")
                    return parseUsageResponse(data: data)
                } else if http.statusCode == 429 {
                    // Rate limited on the usage endpoint — wait and retry
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { Double($0) } ?? 3.0
                    let delay = max(retryAfter, 3.0) // at least 3s
                    logger.info("Usage endpoint 429, retry-after=\(retryAfter), attempt \(attempt + 1)/5")
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                } else {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    logger.error("Usage endpoint status \(http.statusCode): \(bodyStr.prefix(300))")
                    return nil
                }
            } catch {
                logger.error("Usage fetch error: \(error.localizedDescription)")
                return nil
            }
        }

        logger.error("Usage fetch exhausted retries for \(accountId.uuidString)")
        return nil
    }

    private func parseUsageResponse(data: Data) -> ClaudeUsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String?) -> Date? {
            guard let str else { return nil }
            return formatter.date(from: str) ?? formatterNoFrac.date(from: str)
        }

        // API response: { "five_hour": { "utilization": 31.0, "resets_at": "..." }, "seven_day": { ... } }
        let fiveHour = json["five_hour"] as? [String: Any]
        let sevenDay = json["seven_day"] as? [String: Any]

        guard fiveHour != nil || sevenDay != nil else {
            logger.warning("Unknown usage response keys: \(json.keys.sorted())")
            return nil
        }

        return ClaudeUsageData(
            fiveHourUtilization: fiveHour?["utilization"] as? Double ?? 0,
            fiveHourResetsAt: parseDate(fiveHour?["resets_at"] as? String),
            sevenDayUtilization: sevenDay?["utilization"] as? Double ?? 0,
            sevenDayResetsAt: parseDate(sevenDay?["resets_at"] as? String)
        )
    }
}
