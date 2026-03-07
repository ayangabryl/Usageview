import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "OpenRouterUsage")

struct OpenRouterUsageData: Sendable {
    var isActive: Bool
    var totalCredits: Double = 0   // Total purchased
    var totalUsage: Double = 0     // Total consumed

    var remainingCredits: Double {
        max(totalCredits - totalUsage, 0)
    }

    var usagePercent: Double {
        guard totalCredits > 0 else { return 0 }
        return (totalUsage / totalCredits) * 100
    }
}

@MainActor
final class OpenRouterUsageService: Sendable {
    private let authService: OpenRouterAuthService

    init(authService: OpenRouterAuthService) {
        self.authService = authService
    }

    /// Fetch OpenRouter credits usage
    func fetchUsage(for accountId: UUID) async -> OpenRouterUsageData? {
        guard let apiKey = authService.getAPIKey(for: accountId) else { return nil }

        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar", forHTTPHeaderField: "X-Title")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 401 || http.statusCode == 403 {
                return OpenRouterUsageData(isActive: false)
            }

            guard http.statusCode == 200 else {
                logger.info("OpenRouter credits: HTTP \(http.statusCode)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let creditData = json["data"] as? [String: Any] else {
                return nil
            }

            var result = OpenRouterUsageData(isActive: true)
            result.totalCredits = (creditData["total_credits"] as? Double) ?? 0
            result.totalUsage = (creditData["total_usage"] as? Double) ?? 0

            logger.info("OpenRouter: credits=\(result.totalCredits) usage=\(result.totalUsage) remaining=\(result.remainingCredits)")
            return result
        } catch {
            logger.error("OpenRouter fetch error: \(error.localizedDescription)")
            return nil
        }
    }
}
