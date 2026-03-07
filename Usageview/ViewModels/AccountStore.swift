import Foundation
import SwiftUI
import AppKit
import os

private let storeLogger = Logger(subsystem: "com.ayangabryl.usage", category: "AccountStore")

enum ViewMode: String, CaseIterable {
    case expanded
    case compact
}

@Observable
@MainActor
final class AccountStore {
    var accounts: [Account] = []
    var refreshingIds: Set<UUID> = []
    var viewMode: ViewMode = .expanded
    var showWeeklyLimit: Bool = false
    /// Incremented after every save to force SwiftUI re-render in MenuBarExtra
    var dataVersion: Int = 0

    /// The account pinned to the menu bar icon. When set, the gauge tracks this account only.
    var pinnedAccountId: UUID? {
        didSet {
            if let id = pinnedAccountId {
                UserDefaults.standard.set(id.uuidString, forKey: "pinnedAccountId")
            } else {
                UserDefaults.standard.removeObject(forKey: "pinnedAccountId")
            }
            dataVersion += 1
        }
    }

    /// The menu bar icon style.
    var menuBarIconStyle: MenuBarIconStyle = .dynamic {
        didSet {
            UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle")
            dataVersion += 1
        }
    }

    /// Custom display order of accounts (by UUID). Persisted to UserDefaults.
    var accountOrder: [UUID] = [] {
        didSet {
            let strings = accountOrder.map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: "accountOrder")
            dataVersion += 1
        }
    }

    /// Custom color for the "Colored" icon style. Stored as hex string.
    var menuBarIconColor: Color = Color(red: 0.38, green: 0.52, blue: 1.0) {
        didSet {
            if let hex = menuBarIconColor.toHex() {
                UserDefaults.standard.set(hex, forKey: "menuBarIconColor")
            }
            dataVersion += 1
        }
    }

    let githubAuth: GitHubAuthService
    let claudeAuth: AnthropicAuthService
    let openaiAuth: OpenAIAuthService
    let geminiAuth: GeminiAuthService
    let kimiAuth: KimiAuthService
    let cursorAuth: CursorAuthService
    let openrouterAuth: OpenRouterAuthService
    let kiroAuth: KiroAuthService
    let augmentAuth: AugmentAuthService
    let jetbrainsAuth: JetBrainsAuthService
    private let githubUsage: GitHubUsageService
    private let claudeUsage: AnthropicUsageService
    private let openaiUsage: OpenAIUsageService
    private let geminiUsage: GeminiUsageService
    private let kimiUsage: KimiUsageService
    private let cursorUsage: CursorUsageService
    private let openrouterUsage: OpenRouterUsageService
    private let kiroUsage: KiroUsageService
    private let augmentUsage: AugmentUsageService
    private let jetbrainsUsage: JetBrainsUsageService
    private let storageKey = "accounts_data_v3"

    init() {
        let gh = GitHubAuthService()
        let cl = AnthropicAuthService()
        let oa = OpenAIAuthService()
        let ge = GeminiAuthService()
        let ki = KimiAuthService()
        let cu = CursorAuthService()
        let or = OpenRouterAuthService()
        let kr = KiroAuthService()
        let au = AugmentAuthService()
        let jb = JetBrainsAuthService()
        self.githubAuth = gh
        self.claudeAuth = cl
        self.openaiAuth = oa
        self.geminiAuth = ge
        self.kimiAuth = ki
        self.cursorAuth = cu
        self.openrouterAuth = or
        self.kiroAuth = kr
        self.augmentAuth = au
        self.jetbrainsAuth = jb
        self.githubUsage = GitHubUsageService(authService: gh)
        self.claudeUsage = AnthropicUsageService(authService: cl)
        self.openaiUsage = OpenAIUsageService(authService: oa)
        self.geminiUsage = GeminiUsageService(authService: ge)
        self.kimiUsage = KimiUsageService(authService: ki)
        self.cursorUsage = CursorUsageService(authService: cu)
        self.openrouterUsage = OpenRouterUsageService(authService: or)
        self.kiroUsage = KiroUsageService(authService: kr)
        self.augmentUsage = AugmentUsageService(authService: au)
        self.jetbrainsUsage = JetBrainsUsageService(authService: jb)
        if let mode = UserDefaults.standard.string(forKey: "viewMode"),
           let m = ViewMode(rawValue: mode) {
            viewMode = m
        }
        showWeeklyLimit = UserDefaults.standard.bool(forKey: "showWeeklyLimit")
        if let pinStr = UserDefaults.standard.string(forKey: "pinnedAccountId"),
           let pinId = UUID(uuidString: pinStr) {
            pinnedAccountId = pinId
        }
        if let styleStr = UserDefaults.standard.string(forKey: "menuBarIconStyle"),
           let style = MenuBarIconStyle(rawValue: styleStr) {
            menuBarIconStyle = style
        }
        if let hex = UserDefaults.standard.string(forKey: "menuBarIconColor") {
            menuBarIconColor = Color(hex: hex)
        }
        if let orderStrings = UserDefaults.standard.stringArray(forKey: "accountOrder") {
            accountOrder = orderStrings.compactMap { UUID(uuidString: $0) }
        }
        load()
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        dataVersion += 1
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
        let account = Account(
            id: UUID(),
            serviceType: serviceType,
            authMethod: authMethod,
            label: "",
            currentUsage: 0,
            usageLimit: serviceType.defaultLimit,
            usageUnit: serviceType.defaultUsageUnit,
            resetDate: .now
        )
        accounts.append(account)
        accountOrder.append(account.id)
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
        case .cursor: cursorAuth.disconnect(accountId: id)
        case .openrouter: openrouterAuth.disconnect(accountId: id)
        case .kiro: kiroAuth.disconnect(accountId: id)
        case .augment: augmentAuth.disconnect(accountId: id)
        case .jetbrainsAI: jetbrainsAuth.disconnect(accountId: id)
        }
        accounts.removeAll { $0.id == id }
        accountOrder.removeAll { $0 == id }
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
        case .cursor: cursorAuth.disconnect(accountId: id)
        case .openrouter: openrouterAuth.disconnect(accountId: id)
        case .kiro: kiroAuth.disconnect(accountId: id)
        case .augment: augmentAuth.disconnect(accountId: id)
        case .jetbrainsAI: jetbrainsAuth.disconnect(accountId: id)
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
                    accounts[index].planName = usage.plan?.capitalized
                    if let reset = usage.resetDate {
                        accounts[index].resetDate = reset
                    }
                    // Store chat quota
                    if let chatPct = usage.chatPercentRemaining {
                        accounts[index].chatPercentRemaining = chatPct
                        accounts[index].chatLimit = usage.chatEntitlement
                        accounts[index].chatUsage = max(0, 100 - chatPct)
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
            } else {
                // Fetch usage
                let usage = await claudeUsage.fetchUsage(for: account.id)

                if let usage {
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

                        // Plan tier from usage response
                        if let plan = usage.planTier {
                            accounts[index].planName = plan
                        }
                        if let org = usage.organizationName {
                            accounts[index].organizationName = org
                        }
                    }
                }
                save()
            }

        case .chatgpt:
            storeLogger.info("ChatGPT refresh: authMethod=\(account.authMethod.rawValue, privacy: .public) id=\(account.id)")
            if account.authMethod == .apiKey {
                // API key: verify it's still valid
                let valid = await openaiAuth.verifyAPIKey(for: account.id)
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = valid ? "Connected" : "Inactive"
                    save()
                }
            } else if let status = await openaiUsage.fetchStatus(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    storeLogger.info("ChatGPT store: plan=\(status.planName, privacy: .public) 5h=\(status.fiveHourUsedPercent ?? -1) weekly=\(status.weeklyUsedPercent ?? -1)")
                    accounts[index].planName = status.planName

                    // Store rate limit windows (reuse Claude's dual window fields)
                    if let fiveHour = status.fiveHourUsedPercent {
                        accounts[index].fiveHourUsage = Double(fiveHour)
                        accounts[index].fiveHourResetDate = status.fiveHourResetAt

                        // Primary usage for progress bar
                        accounts[index].currentUsage = Double(fiveHour)
                        accounts[index].usageLimit = 100
                        accounts[index].usageUnit = "% used"
                        if let reset = status.fiveHourResetAt {
                            accounts[index].resetDate = reset
                        }
                    }
                    if let weekly = status.weeklyUsedPercent {
                        accounts[index].sevenDayUsage = Double(weekly)
                        accounts[index].sevenDayResetDate = status.weeklyResetAt
                    }

                    // If no rate limit data, fall back to status display
                    if status.fiveHourUsedPercent == nil {
                        accounts[index].usageUnit = status.planName
                    }

                    let storedAccount = accounts[index]
                    storeLogger.info("ChatGPT stored: fiveHour=\(storedAccount.fiveHourUsage ?? -1) sevenDay=\(storedAccount.sevenDayUsage ?? -1) isStatusOnly=\(storedAccount.isStatusOnly) hasDualWindows=\(storedAccount.hasDualWindows)")
                    save()
                } else {
                    storeLogger.error("ChatGPT store: account NOT FOUND in array!")
                }
            } else {
                storeLogger.warning("ChatGPT refresh: fetchStatus returned nil")
            }

        case .kimi:
            if let usage = await kimiUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    if usage.hasQuotaData {
                        // Real billing data from Kimi API
                        accounts[index].kimiWeeklyUsed = usage.weeklyUsed
                        accounts[index].kimiWeeklyLimit = usage.weeklyLimit
                        accounts[index].kimiWeeklyResetDate = usage.weeklyResetDate
                        accounts[index].kimiRateLimitUsed = usage.rateLimitUsed
                        accounts[index].kimiRateLimitMax = usage.rateLimitMax
                        accounts[index].kimiRateLimitResetDate = usage.rateLimitResetDate

                        // Use weekly quota as primary usage
                        let weeklyPct = usage.weeklyLimit > 0
                            ? (usage.weeklyUsed / usage.weeklyLimit) * 100
                            : 0
                        accounts[index].currentUsage = weeklyPct
                        accounts[index].usageLimit = 100
                        accounts[index].usageUnit = "% used"
                        if let reset = usage.weeklyResetDate {
                            accounts[index].resetDate = reset
                        }
                    } else {
                        accounts[index].usageUnit = usage.isActive ? "Connected" : "Inactive"
                    }
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
                        accounts[index].planName = status.hasProModels ? "Pro" : "Free"
                    } else {
                        accounts[index].usageUnit = "Inactive"
                    }
                    save()
                }
            }

        case .cursor:
            if let usage = await cursorUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    if usage.limitCents > 0 {
                        accounts[index].currentUsage = usage.usedCents
                        accounts[index].usageLimit = usage.limitCents
                        accounts[index].usageUnit = "requests"
                        accounts[index].planName = usage.planName
                        if let reset = usage.billingCycleEnd {
                            accounts[index].resetDate = reset
                        }
                    } else {
                        accounts[index].usageUnit = usage.planName ?? "Connected"
                    }
                    save()
                }
            }

        case .openrouter:
            if let usage = await openrouterUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    if usage.totalCredits > 0 {
                        accounts[index].openRouterTotalCredits = usage.totalCredits
                        accounts[index].openRouterTotalUsage = usage.totalUsage
                        let remaining = max(0, usage.totalCredits - usage.totalUsage)
                        let pct = (usage.totalUsage / usage.totalCredits) * 100
                        accounts[index].currentUsage = pct
                        accounts[index].usageLimit = 100
                        accounts[index].usageUnit = String(format: "$%.2f remaining", remaining)
                    } else {
                        accounts[index].usageUnit = "Connected"
                    }
                    save()
                }
            }

        case .kiro:
            if let usage = await kiroUsage.fetchStatus(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = usage.isActive ? "Connected" : "Inactive"
                    save()
                }
            }

        case .augment:
            if let usage = await augmentUsage.fetchStatus(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].usageUnit = usage.isActive ? "Connected" : "Inactive"
                    save()
                }
            }

        case .jetbrainsAI:
            if let usage = await jetbrainsUsage.fetchUsage(for: account.id) {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    if usage.maximum > 0 {
                        accounts[index].jetbrainsQuotaCurrent = usage.currentUsed
                        accounts[index].jetbrainsQuotaMaximum = usage.maximum
                        accounts[index].jetbrainsQuotaResetDate = usage.resetDate
                        accounts[index].currentUsage = usage.usagePercent
                        accounts[index].usageLimit = 100
                        accounts[index].usageUnit = "% used"
                        if let reset = usage.resetDate {
                            accounts[index].resetDate = reset
                        }
                        if let ide = usage.ideName {
                            accounts[index].planName = ide
                        }
                    } else {
                        accounts[index].usageUnit = usage.isActive ? "Connected" : "Inactive"
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
        case .cursor: cursorAuth.isAuthenticated(for: account.id)
        case .openrouter: openrouterAuth.isAuthenticated(for: account.id)
        case .kiro: kiroAuth.isAuthenticated(for: account.id)
        case .augment: augmentAuth.isAuthenticated(for: account.id)
        case .jetbrainsAI: jetbrainsAuth.isAuthenticated(for: account.id)
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

    /// Accounts sorted by user-defined order.
    var orderedAccounts: [Account] {
        // Ensure every account has an order entry; append any missing ones
        let knownIds = Set(accountOrder)
        let missing = accounts.filter { !knownIds.contains($0.id) }
        if !missing.isEmpty {
            // Side-effect free: caller should call ensureOrderIntegrity() on load
            return accountOrder.compactMap { id in accounts.first { $0.id == id } } + missing
        }
        return accountOrder.compactMap { id in accounts.first { $0.id == id } }
    }

    /// Ensure every account is in accountOrder and remove stale entries.
    func ensureOrderIntegrity() {
        let accountIds = Set(accounts.map { $0.id })
        var order = accountOrder.filter { accountIds.contains($0) }
        for account in accounts where !order.contains(account.id) {
            order.append(account.id)
        }
        if order != accountOrder {
            accountOrder = order
        }
    }

    /// Move an account up (earlier) in the display order.
    func moveAccountUp(id: UUID) {
        ensureOrderIntegrity()
        guard let idx = accountOrder.firstIndex(of: id), idx > 0 else { return }
        accountOrder.swapAt(idx, idx - 1)
    }

    /// Move an account down (later) in the display order.
    func moveAccountDown(id: UUID) {
        ensureOrderIntegrity()
        guard let idx = accountOrder.firstIndex(of: id), idx < accountOrder.count - 1 else { return }
        accountOrder.swapAt(idx, idx + 1)
    }

    /// Whether the account can be moved up.
    func canMoveUp(id: UUID) -> Bool {
        guard let idx = accountOrder.firstIndex(of: id) else { return false }
        return idx > 0
    }

    /// Whether the account can be moved down.
    func canMoveDown(id: UUID) -> Bool {
        guard let idx = accountOrder.firstIndex(of: id) else { return false }
        return idx < accountOrder.count - 1
    }

    // MARK: - Dynamic Menu Bar Icon

    /// The usage percentage (0–100) for a specific account, using the most relevant metric.
    func accountUsagePercent(_ account: Account) -> Double {
        if let fiveHour = account.fiveHourUsage {
            return fiveHour
        } else if account.usageLimit > 0 {
            return account.usagePercentage * 100
        }
        return 0
    }

    /// The worst-off (highest usage) connected account's percentage (0–100).
    var worstUsagePercent: Double? {
        let connected = accounts.filter { isConnected(for: $0) && !$0.isStatusOnly }
        guard !connected.isEmpty else { return nil }

        var worst: Double = 0
        for account in connected {
            worst = max(worst, accountUsagePercent(account))
        }
        return worst
    }

    /// The percentage to display in the menu bar gauge.
    /// If a specific account is pinned, use that account's usage; otherwise use worst-of-all.
    var menuBarPercent: Double? {
        if let pinnedId = pinnedAccountId,
           let account = accounts.first(where: { $0.id == pinnedId }),
           isConnected(for: account) {
            return accountUsagePercent(account)
        }
        return worstUsagePercent
    }

    /// Whether the given account is pinned to the menu bar icon.
    func isPinnedToMenuBar(_ account: Account) -> Bool {
        pinnedAccountId == account.id
    }

    /// Pin or unpin an account from the menu bar icon.
    func togglePinToMenuBar(_ account: Account) {
        if pinnedAccountId == account.id {
            pinnedAccountId = nil
        } else {
            pinnedAccountId = account.id
        }
    }

    /// Generate the current dynamic menu bar icon
    var menuBarIcon: NSImage {
        MenuBarIconRenderer.icon(
            percent: menuBarPercent,
            style: menuBarIconStyle,
            customColor: menuBarIconStyle == .colored ? NSColor(menuBarIconColor) : nil,
            isStale: accounts.isEmpty || accounts.allSatisfy { !isConnected(for: $0) }
        )
    }
}
