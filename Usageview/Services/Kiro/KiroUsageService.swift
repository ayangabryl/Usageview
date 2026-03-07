import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "KiroUsage")

struct KiroUsageData: Sendable {
    var isActive: Bool
}

@MainActor
final class KiroUsageService: Sendable {
    private let authService: KiroAuthService

    init(authService: KiroAuthService) {
        self.authService = authService
    }

    /// For now, just verify the token is stored. Future: call kiro-cli /usage
    func fetchStatus(for accountId: UUID) async -> KiroUsageData? {
        guard authService.getAPIKey(for: accountId) != nil else { return nil }
        return KiroUsageData(isActive: true)
    }
}
