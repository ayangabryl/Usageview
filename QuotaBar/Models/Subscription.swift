import Foundation
import SwiftUI

// MARK: - Service Type

enum ServiceType: String, Codable, CaseIterable, Sendable {
    case claude
    case copilot
    case chatgpt
    case gemini
    case kimi

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "GitHub Copilot"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        case .kimi: "Kimi AI"
        }
    }

    /// Asset catalog image name for the bundled brand logo
    var assetName: String {
        switch self {
        case .claude: "AnthropicLogo"
        case .copilot: "GitHubLogo"
        case .chatgpt: "OpenAILogo"
        case .gemini: "GeminiLogo"
        case .kimi: "KimiLogo"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(hex: "#D97706")
        case .copilot: Color(hex: "#6366F1")
        case .chatgpt: Color(hex: "#10A37F")
        case .gemini: Color(hex: "#4285F4")
        case .kimi: Color(hex: "#000000")
        }
    }

    var authDescription: String {
        switch self {
        case .claude: "OAuth or API key"
        case .copilot: "Device flow sign-in"
        case .chatgpt: "OAuth or API key"
        case .gemini: "API key"
        case .kimi: "API key"
        }
    }

    /// Whether this service supports multiple auth methods
    var supportsMultipleAuthMethods: Bool {
        switch self {
        case .claude, .chatgpt: true
        case .copilot, .gemini, .kimi: false
        }
    }

    var defaultUsageUnit: String {
        switch self {
        case .claude: "% used"
        case .copilot: "premium requests"
        case .chatgpt: "premium requests"
        case .gemini: "requests"
        case .kimi: "tokens"
        }
    }

    var defaultLimit: Double {
        switch self {
        case .claude: 100
        case .copilot: 300
        case .chatgpt: 0
        case .gemini: 0
        case .kimi: 0
        }
    }
}

// MARK: - Auth Method

enum AuthMethod: String, Codable, Sendable {
    case oauth
    case apiKey
}

// MARK: - Account

struct Account: Codable, Identifiable, Sendable {
    var id: UUID
    var serviceType: ServiceType
    var authMethod: AuthMethod
    var label: String
    var currentUsage: Double
    var usageLimit: Double
    var usageUnit: String
    var resetDate: Date
    var username: String?
    var avatarURL: String?

    // Claude dual rate windows
    var fiveHourUsage: Double?
    var fiveHourResetDate: Date?
    var sevenDayUsage: Double?
    var sevenDayResetDate: Date?

    init(id: UUID, serviceType: ServiceType, authMethod: AuthMethod = .oauth, label: String, currentUsage: Double, usageLimit: Double, usageUnit: String, resetDate: Date, username: String? = nil, avatarURL: String? = nil) {
        self.id = id
        self.serviceType = serviceType
        self.authMethod = authMethod
        self.label = label
        self.currentUsage = currentUsage
        self.usageLimit = usageLimit
        self.usageUnit = usageUnit
        self.resetDate = resetDate
        self.username = username
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        serviceType = try container.decode(ServiceType.self, forKey: .serviceType)
        authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .oauth
        label = try container.decode(String.self, forKey: .label)
        currentUsage = try container.decode(Double.self, forKey: .currentUsage)
        usageLimit = try container.decode(Double.self, forKey: .usageLimit)
        usageUnit = try container.decode(String.self, forKey: .usageUnit)
        resetDate = try container.decode(Date.self, forKey: .resetDate)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        fiveHourUsage = try container.decodeIfPresent(Double.self, forKey: .fiveHourUsage)
        fiveHourResetDate = try container.decodeIfPresent(Date.self, forKey: .fiveHourResetDate)
        sevenDayUsage = try container.decodeIfPresent(Double.self, forKey: .sevenDayUsage)
        sevenDayResetDate = try container.decodeIfPresent(Date.self, forKey: .sevenDayResetDate)
    }

    /// Whether this account only shows connection status (no real usage tracking)
    var isStatusOnly: Bool {
        switch (serviceType, authMethod) {
        case (.gemini, _), (.kimi, _): return true
        case (.claude, .apiKey), (.chatgpt, .apiKey): return true
        default: return false
        }
    }

    var usagePercentage: Double {
        guard usageLimit > 0 else { return 0 }
        return min(currentUsage / usageLimit, 1.0)
    }

    var isAtLimit: Bool {
        guard usageLimit > 0 else { return false }
        return currentUsage >= usageLimit
    }

    /// Whether this is a Claude OAuth account with dual rate windows
    var hasDualWindows: Bool {
        serviceType == .claude && authMethod == .oauth && fiveHourUsage != nil && sevenDayUsage != nil
    }

    /// Whether a reset date is plausible for a given rate window.
    /// The 5-hour window shouldn't show resets > 6h away; the 7-day window shouldn't show > 8d.
    static func isResetReasonable(_ date: Date?, maxHours: Double) -> Bool {
        guard let date else { return false }
        let interval = date.timeIntervalSince(.now)
        return interval > 0 && interval < maxHours * 3600
    }

    /// Format a reset date as a short label
    static func resetLabel(for date: Date?) -> String {
        guard let date, date.timeIntervalSince(.now) > 0 else { return "now" }
        let totalMinutes = Int(date.timeIntervalSince(.now)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            return "\(hours / 24)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Smart reset label: hours/minutes when < 24h, days otherwise
    var resetLabel: String {
        let interval = resetDate.timeIntervalSince(.now)
        guard interval > 0 else { return "now" }
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            return "\(hours / 24)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var formattedUsage: String {
        if isStatusOnly {
            return usageUnit  // "Connected" / "Inactive" / etc.
        }
        if usageUnit == "% used" {
            return "\(Int(currentUsage))% used"
        }
        return "\(Int(currentUsage))/\(Int(usageLimit)) \(usageUnit)"
    }

    var accentColor: Color {
        serviceType.accentColor
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double((rgbValue & 0x0000FF)) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
