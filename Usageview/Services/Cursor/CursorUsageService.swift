import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "CursorUsage")

struct CursorUsageData: Sendable {
    var isActive: Bool
    var planName: String?
    var usedCents: Double = 0
    var limitCents: Double = 0
    var onDemandUsedCents: Double = 0
    var billingCycleEnd: Date?

    var usagePercent: Double {
        guard limitCents > 0 else { return 0 }
        return (usedCents / limitCents) * 100
    }
}

@MainActor
final class CursorUsageService: Sendable {
    private let authService: CursorAuthService

    init(authService: CursorAuthService) {
        self.authService = authService
    }

    /// Fetch Cursor usage summary using stored session token
    func fetchUsage(for accountId: UUID) async -> CursorUsageData? {
        guard let token = authService.getToken(for: accountId) else { return nil }

        // Try /api/usage-summary first
        if let usage = await fetchUsageSummary(token: token) {
            return usage
        }

        // Fallback: just verify token is valid via /api/auth/me
        return await verifySession(token: token)
    }

    private func fetchUsageSummary(token: String) async -> CursorUsageData? {
        guard let url = URL(string: "https://www.cursor.com/api/usage-summary") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Token can be a Cookie header value or a raw session token
        if token.contains("=") {
            request.setValue(token, forHTTPHeaderField: "Cookie")
        } else {
            request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        }
        request.setValue("https://www.cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard http.statusCode == 200 else {
                logger.info("Cursor usage-summary: HTTP \(http.statusCode)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var result = CursorUsageData(isActive: true)

            if let membership = json["membershipType"] as? String {
                result.planName = membership.capitalized
            }

            if let cycleEnd = json["billingCycleEnd"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result.billingCycleEnd = formatter.date(from: cycleEnd)
            }

            if let individualUsage = json["individualUsage"] as? [String: Any],
               let plan = individualUsage["plan"] as? [String: Any] {
                result.usedCents = (plan["used"] as? Double) ?? 0
                result.limitCents = (plan["limit"] as? Double) ?? 0

                if let onDemand = individualUsage["onDemand"] as? [String: Any] {
                    result.onDemandUsedCents = (onDemand["used"] as? Double) ?? 0
                }
            }

            return result
        } catch {
            logger.error("Cursor usage fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func verifySession(token: String) async -> CursorUsageData? {
        guard let url = URL(string: "https://www.cursor.com/api/auth/me") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if token.contains("=") {
            request.setValue(token, forHTTPHeaderField: "Cookie")
        } else {
            request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return CursorUsageData(isActive: true)
        } catch {
            return nil
        }
    }
}
