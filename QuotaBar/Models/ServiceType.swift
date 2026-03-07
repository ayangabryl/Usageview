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
        case .chatgpt: "OpenAI"
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
