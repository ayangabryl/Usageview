import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "OpenAIUsage")

struct ChatGPTUsageData: Sendable {
    var planName: String
    var isSubscribed: Bool
}

@MainActor
final class OpenAIUsageService: Sendable {
    private let authService: OpenAIAuthService

    init(authService: OpenAIAuthService) {
        self.authService = authService
    }

    /// ChatGPT doesn't expose a usage/quota API like Claude or Copilot.
    /// We verify the token is valid and return the subscription status.
    func fetchStatus(for accountId: UUID) async -> ChatGPTUsageData? {
        guard let token = await authService.getValidToken(for: accountId) else {
            logger.error("ChatGPT: no valid token available")
            return nil
        }

        // Verify token by calling the session endpoint
        let url = URL(string: "https://chatgpt.com/backend-api/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let chatgptAccountId = authService.chatgptAccountId(for: accountId) {
            request.setValue(chatgptAccountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.error("ChatGPT /me failed (HTTP \(http.statusCode)): \(body.prefix(200), privacy: .public)")
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let plan = json["plan_type"] as? String
                    ?? json["plan"] as? String
                    ?? "Connected"
                logger.info("ChatGPT: plan=\(plan, privacy: .public)")
                return ChatGPTUsageData(planName: plan, isSubscribed: true)
            }

            return ChatGPTUsageData(planName: "Connected", isSubscribed: true)
        } catch {
            logger.error("ChatGPT fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
