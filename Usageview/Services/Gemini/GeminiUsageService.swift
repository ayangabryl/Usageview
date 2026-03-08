import Foundation
import os

private let geminiUsageLogger = Logger(subsystem: "com.ayangabryl.usage", category: "GeminiUsage")

struct GeminiUsageData: Sendable {
    var modelCount: Int
    var isActive: Bool
    var hasProModels: Bool
    var topModels: [String]
}

/// Real Gemini quota data from the OAuth-backed private API
struct GeminiOAuthUsageData: Sendable {
    var proPercentUsed: Double     // 0–100
    var flashPercentUsed: Double?  // 0–100
    var proResetDate: Date?
    var flashResetDate: Date?
    var accountEmail: String?
    var planName: String?
    var modelQuotas: [GeminiModelQuota]

    /// The binding constraint (whichever is higher)
    var primaryPercentUsed: Double {
        if let flash = flashPercentUsed {
            return max(proPercentUsed, flash)
        }
        return proPercentUsed
    }

    var primaryResetDate: Date? {
        if let flash = flashPercentUsed, flash > proPercentUsed {
            return flashResetDate
        }
        return proResetDate
    }
}

@MainActor
final class GeminiUsageService: Sendable {
    private let authService: GeminiAuthService

    init(authService: GeminiAuthService) {
        self.authService = authService
    }

    /// Fetch real quota data using Gemini CLI OAuth credentials
    func fetchOAuthUsage(for accountId: UUID) async -> GeminiOAuthUsageData? {
        guard authService.isOAuthAccount(for: accountId) else { return nil }

        do {
            let snapshot = try await authService.oauthService.fetchQuota()

            let proUsed = snapshot.proPercentLeft.map { 100 - $0 } ?? 0
            let flashUsed = snapshot.flashPercentLeft.map { 100 - $0 }

            return GeminiOAuthUsageData(
                proPercentUsed: proUsed,
                flashPercentUsed: flashUsed,
                proResetDate: snapshot.proResetTime,
                flashResetDate: snapshot.flashResetTime,
                accountEmail: snapshot.accountEmail,
                planName: snapshot.accountPlan,
                modelQuotas: snapshot.modelQuotas
            )
        } catch {
            geminiUsageLogger.error("Gemini OAuth usage fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Verify the API key is valid and gather model info (legacy API key path)
    func fetchStatus(for accountId: UUID) async -> GeminiUsageData? {
        guard let apiKey = authService.getAPIKey(for: accountId) else { return nil }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 429 {
                return GeminiUsageData(modelCount: 0, isActive: true, hasProModels: false, topModels: ["Rate limited"])
            }

            guard http.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["displayName"] as? String }
                let hasProModels = modelNames.contains { $0.lowercased().contains("pro") || $0.lowercased().contains("ultra") }
                let topModels = Array(modelNames.prefix(5))
                return GeminiUsageData(
                    modelCount: models.count,
                    isActive: true,
                    hasProModels: hasProModels,
                    topModels: topModels
                )
            }

            return GeminiUsageData(modelCount: 0, isActive: true, hasProModels: false, topModels: [])
        } catch {
            return nil
        }
    }
}
