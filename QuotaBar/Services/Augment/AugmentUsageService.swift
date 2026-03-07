import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "AugmentUsage")

struct AugmentUsageData: Sendable {
    var isActive: Bool
}

@MainActor
final class AugmentUsageService: Sendable {
    private let authService: AugmentAuthService

    init(authService: AugmentAuthService) {
        self.authService = authService
    }

    /// For now, just verify the token is stored. Future: call auggie or use cookies.
    func fetchStatus(for accountId: UUID) async -> AugmentUsageData? {
        guard authService.getAPIKey(for: accountId) != nil else { return nil }
        return AugmentUsageData(isActive: true)
    }
}
