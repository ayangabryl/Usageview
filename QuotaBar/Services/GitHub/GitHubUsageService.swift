import Foundation

struct CopilotUsageData: Sendable {
    var entitlement: Double
    var remaining: Double
    var used: Double
    var percentRemaining: Double
    var resetDate: Date?
    var plan: String?
}

@MainActor
final class GitHubUsageService: Sendable {
    private let authService: GitHubAuthService

    init(authService: GitHubAuthService) {
        self.authService = authService
    }

    func fetchCopilotUsage(for accountId: UUID) async -> CopilotUsageData? {
        guard let token = authService.token(for: accountId) else { return nil }

        let url = URL(string: "https://api.github.com/copilot_internal/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return parseResponse(data: data)
        } catch {
            return nil
        }
    }

    private func parseResponse(data: Data) -> CopilotUsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let quotaSnapshots = json["quota_snapshots"] as? [String: Any]
        let premium = quotaSnapshots?["premium_interactions"] as? [String: Any]
        guard let premium else { return nil }

        let entitlement = premium["entitlement"] as? Double ?? 0
        let remaining = premium["remaining"] as? Double ?? premium["quota_remaining"] as? Double ?? 0
        let percentRemaining = premium["percent_remaining"] as? Double ?? 0
        let unlimited = premium["unlimited"] as? Bool ?? false

        let resetDateStr = json["quota_reset_date_utc"] as? String ?? json["quota_reset_date"] as? String
        var resetDate: Date?
        if let resetDateStr {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetDate = isoFormatter.date(from: resetDateStr)
            if resetDate == nil {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                resetDate = dateFormatter.date(from: resetDateStr)
            }
        }

        let plan = json["copilot_plan"] as? String
        let effectiveEntitlement = unlimited ? 0 : entitlement
        let used = effectiveEntitlement - remaining

        return CopilotUsageData(
            entitlement: effectiveEntitlement,
            remaining: remaining,
            used: max(0, used),
            percentRemaining: percentRemaining,
            resetDate: resetDate,
            plan: plan
        )
    }
}
