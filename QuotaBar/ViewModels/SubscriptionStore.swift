import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable {
    case expanded
    case compact
}

@Observable
@MainActor
final class SubscriptionStore {
    var accounts: [Account] = []
    var refreshingIds: Set<UUID> = []
    var viewMode: ViewMode = .expanded
    var showWeeklyLimit: Bool = false

    let githubAuth: GitHubAuthService
    let claudeAuth: AnthropicAuthService
    let openaiAuth: OpenAIAuthService
    let geminiAuth: GeminiAuthService
    let kimiAuth: KimiAuthService
    private let githubUsage: GitHubUsageService
    private let claudeUsage: AnthropicUsageService
    private let openaiUsage: OpenAIUsageService
    private let geminiUsage: GeminiUsageService
    private let kimiUsage: KimiUsageService
    private let storageKey = "accounts_data_v3"

    init() {
        let gh = GitHubAuthService()
        let cl = AnthropicAuthService()
        let oa = OpenAIAuthService()
        let ge = GeminiAuthService()
        let ki = KimiAuthService()
        self.githubAuth = gh
        self.claudeAuth = cl
        self.openaiAuth = oa
        self.geminiAuth = ge
        self.kimiAuth = ki
        self.githubUsage = GitHubUsageService(authService: gh)
        self.claudeUsage = AnthropicUsageService(authService: cl)
        self.openaiUsage = OpenAIUsageService(authService: oa)
        self.geminiUsage = GeminiUsageService(authService: ge)
        self.kimiUsage = KimiUsageService(authService: ki)
        if let mode = UserDefaults.standard.string(forKey: "viewMode"),
           let m = ViewMode(rawValue: mode) {
            viewMode = m
        }
        showWeeklyLimit = UserDefaults.standard.bool(forKey: "showWeeklyLimit")
        load()
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data)
        else { return }
        accounts = decoded
    }

    // MARK: - Account Management

    @discardableResult
    func addAccount(serviceType: ServiceType, authMethod: AuthMethod = .oauth) -> Account {
        let existingCount = accounts.filter { $0.serviceType == serviceType }.count
        let label = existingCount > 0 ? "Account \(existingCount + 1)" : ""

        let account = Account(
            id: UUID(),
            serviceType: serviceType,
            authMethod: authMethod,
            label: label,
            currentUsage: 0,
            usageLimit: serviceType.defaultLimit,
            usageUnit: serviceType.defaultUsageUnit,
            resetDate: .now
        )
        accounts.append(account)
        save()
        return account
    }

    func removeAccount(id: UUID) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        switch account.serviceType {
        case .claude: claudeAuth.disconnect(accountId: id)
        case .copilot: githubAuth.disconnect(accountId: id)
        case .chatgpt: openaiAuth.disconnect(accountId: id)
        case .gemini: geminiAuth.disconnect(accountId: id)
        case .kimi: kimiAuth.disconnect(accountId: id)
        }
        accounts.removeAll { $0.id == id }
        save()
    }

    /// Disconnect an account (remove tokens but keep the account entry)
    func disconnectAccount(id: UUID) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        switch account.serviceType {
        case .claude: claudeAuth.disconnect(accountId: id)
        case .copilot: githubAuth.disconnect(accountId: id)
        case .chatgpt: openaiAuth.disconnect(accountId: id)
        case .gemini: geminiAuth.disconnect(accountId: id)
        case .kimi: kimiAuth.disconnect(accountId: id)
        }
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index].username = nil
            accounts[index].avatarURL = nil
            accounts[index].currentUsage = 0
            save()
        }
    }

    func updateAccountAfterConnect(id: UUID, username: String?, avatarURL: String?, authMethod: AuthMethod? = nil) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index].username = username
            accounts[index].avatarURL = avatarURL
            if let authMethod {
                accounts[index].authMethod = authMethod
            }
            if let username, accounts[index].label.isEmpty {
                accounts[index].label = username
            }
            save()
        }
    }

    func renameAccount(id: UUID, label: String) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index].label = label
            save()
        }
    }

    // MARK: - Refresh

    func refreshAccount(_ account: Account) async {
        refreshingIds.insert(account.id)
        defer { refreshingIds.remove(account.id) }

        switch account.serviceType {
        case .copilot:
            if let usage = await githubUsage.fetchCopilotUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageLimit = usage.entitlement
                    accounts[index].currentUsage = usage.used
                    accounts[index].usageUnit = "premium requests"
                    if let reset = usage.resetDate {
                        accounts[index].resetDate = reset
                    }
                    save()
                }
            }

        case .claude:
            if account.authMethod == .apiKey {
                // API key: verify it's still valid
                let valid = await claudeAuth.verifyAPIKey(for: account.id)
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = valid ? "Connected" : "Inactive"
                    save()
                }
            } else if let usage = await claudeUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    // Store both windows (API returns percentages directly, e.g. 31.0 = 31%)
                    accounts[index].fiveHourUsage = usage.fiveHourUtilization
                    accounts[index].fiveHourResetDate = usage.fiveHourResetsAt
                    accounts[index].sevenDayUsage = usage.sevenDayUtilization
                    accounts[index].sevenDayResetDate = usage.sevenDayResetsAt

                    // Show the binding constraint (whichever window is fuller)
                    if usage.sevenDayUtilization >= usage.fiveHourUtilization {
                        accounts[index].currentUsage = usage.sevenDayUtilization
                        if let reset = usage.sevenDayResetsAt {
                            accounts[index].resetDate = reset
                        }
                    } else {
                        accounts[index].currentUsage = usage.fiveHourUtilization
                        if let reset = usage.fiveHourResetsAt {
                            accounts[index].resetDate = reset
                        }
                    }
                    accounts[index].usageLimit = 100
                    accounts[index].usageUnit = "% used"
                    save()
                }
            }

        case .chatgpt:
            if account.authMethod == .apiKey {
                // API key: verify it's still valid
                let valid = await openaiAuth.verifyAPIKey(for: account.id)
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = valid ? "Connected" : "Inactive"
                    save()
                }
            } else if let status = await openaiUsage.fetchStatus(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = status.planName
                    save()
                }
            }

        case .kimi:
            if let usage = await kimiUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = usage.isActive ? "Connected" : "Inactive"
                    save()
                }
            }

        case .gemini:
            if let status = await geminiUsage.fetchStatus(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    if status.isActive {
                        let label = status.hasProModels
                            ? "\(status.modelCount) models · Pro"
                            : "\(status.modelCount) models"
                        accounts[index].usageUnit = label
                    } else {
                        accounts[index].usageUnit = "Inactive"
                    }
                    save()
                }
            }
        }
    }

    func refreshAll() async {
        for account in accounts where isConnected(for: account) {
            await refreshAccount(account)
        }
    }

    // MARK: - Status

    func isConnected(for account: Account) -> Bool {
        switch account.serviceType {
        case .claude: claudeAuth.isAuthenticated(for: account.id)
        case .copilot: githubAuth.isAuthenticated(for: account.id)
        case .chatgpt: openaiAuth.isAuthenticated(for: account.id)
        case .gemini: geminiAuth.isAuthenticated(for: account.id)
        case .kimi: kimiAuth.isAuthenticated(for: account.id)
        }
    }

    func isRefreshing(for account: Account) -> Bool {
        refreshingIds.contains(account.id)
    }

    var menuBarLabel: String {
        let connected = accounts.filter { isConnected(for: $0) }
        guard !connected.isEmpty else { return "—" }
        let atLimit = connected.filter(\.isAtLimit)
        if !atLimit.isEmpty {
            return "\(atLimit.count) at limit"
        }
        let maxUsage = connected.map(\.usagePercentage).max() ?? 0
        return "\(Int(maxUsage * 100))%"
    }

    func toggleViewMode() {
        viewMode = viewMode == .expanded ? .compact : .expanded
        UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
    }

    /// Accounts grouped by service type
    var groupedAccounts: [(ServiceType, [Account])] {
        let types = ServiceType.allCases
        return types.compactMap { type in
            let matching = accounts.filter { $0.serviceType == type }
            return matching.isEmpty ? nil : (type, matching)
        }
    }
}
