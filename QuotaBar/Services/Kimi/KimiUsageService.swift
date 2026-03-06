import Foundation

struct KimiUsageData: Sendable {
    var balanceAvailable: Double
    var balanceTotal: Double
    var isActive: Bool
}

@MainActor
final class KimiUsageService: Sendable {
    private let authService: KimiAuthService

    init(authService: KimiAuthService) {
        self.authService = authService
    }

    /// Fetch balance / usage info from Moonshot API
    func fetchUsage(for accountId: UUID) async -> KimiUsageData? {
        guard let apiKey = authService.getAPIKey(for: accountId) else { return nil }

        // Moonshot / Kimi uses the OpenAI-compatible API format
        // Try to get model list to verify the key is valid
        let url = URL(string: "https://api.moonshot.cn/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            // Key is valid - return connected status
            return KimiUsageData(balanceAvailable: 0, balanceTotal: 0, isActive: true)
        } catch {
            return nil
        }
    }
}
