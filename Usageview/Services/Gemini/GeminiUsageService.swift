import Foundation

struct GeminiUsageData: Sendable {
    var modelCount: Int
    var isActive: Bool
    var hasProModels: Bool
    var topModels: [String]
}

@MainActor
final class GeminiUsageService: Sendable {
    private let authService: GeminiAuthService

    init(authService: GeminiAuthService) {
        self.authService = authService
    }

    /// Verify the API key is valid and gather model info
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
                // Get top unique model families
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
