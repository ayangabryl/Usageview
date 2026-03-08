import Foundation
import SwiftUI

// MARK: - Service Type

enum ServiceType: String, Codable, CaseIterable, Sendable {
    case claude
    case copilot
    case chatgpt
    case gemini
    case kimi
    case cursor
    case openrouter
    case kiro
    case augment
    case jetbrainsAI

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "GitHub Copilot"
        case .chatgpt: "OpenAI"
        case .gemini: "Gemini"
        case .kimi: "Kimi AI"
        case .cursor: "Cursor"
        case .openrouter: "OpenRouter"
        case .kiro: "Kiro"
        case .augment: "Augment"
        case .jetbrainsAI: "JetBrains AI"
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
        case .cursor: "CursorLogo"
        case .openrouter: "OpenRouterLogo"
        case .kiro: "KiroLogo"
        case .augment: "AugmentLogo"
        case .jetbrainsAI: "JetBrainsLogo"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: Color(hex: "#D97706")
        case .copilot: Color(hex: "#6366F1")
        case .chatgpt: Color(hex: "#10A37F")
        case .gemini: Color(hex: "#4285F4")
        case .kimi: Color(hex: "#000000")
        case .cursor: Color(hex: "#00D4AA")
        case .openrouter: Color(hex: "#6467F2")
        case .kiro: Color(hex: "#FF9900")
        case .augment: Color(hex: "#7C3AED")
        case .jetbrainsAI: Color(hex: "#FE315D")
        }
    }

    var authDescription: String {
        switch self {
        case .claude: "OAuth or API key"
        case .copilot: "Device flow sign-in"
        case .chatgpt: "OAuth or API key"
        case .gemini: "Gemini CLI or API key"
        case .kimi: "API key"
        case .cursor: "Session token"
        case .openrouter: "API key"
        case .kiro: "API key"
        case .augment: "API key"
        case .jetbrainsAI: "Auto-detect from IDE"
        }
    }

    /// Whether this service supports multiple auth methods
    var supportsMultipleAuthMethods: Bool {
        switch self {
        case .claude, .chatgpt, .gemini: true
        case .copilot, .kimi, .cursor, .openrouter, .kiro, .augment, .jetbrainsAI: false
        }
    }

    var defaultUsageUnit: String {
        switch self {
        case .claude: "% used"
        case .copilot: "premium requests"
        case .chatgpt: "premium requests"
        case .gemini: "requests"
        case .kimi: "tokens"
        case .cursor: "requests"
        case .openrouter: "credits"
        case .kiro: "credits"
        case .augment: "credits"
        case .jetbrainsAI: "credits"
        }
    }

    var defaultLimit: Double {
        switch self {
        case .claude: 100
        case .copilot: 300
        case .chatgpt: 0
        case .gemini: 0
        case .kimi: 0
        case .cursor: 0
        case .openrouter: 0
        case .kiro: 0
        case .augment: 0
        case .jetbrainsAI: 0
        }
    }
}
