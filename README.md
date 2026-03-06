# QuotaBar

A lightweight macOS menu bar app that tracks your AI service usage quotas at a glance.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar native** — lives in your menu bar, no Dock icon, minimal footprint
- **Multiple accounts** — track personal and work accounts side by side
- **Claude dual rate windows** — see both 5-hour and 7-day utilization with reset countdowns
- **GitHub Copilot** — premium request usage and entitlement tracking
- **ChatGPT** — plan detection (Free/Plus/Pro/Team/Enterprise) via OAuth
- **Gemini & Kimi** — API key validation and model availability
- **Expanded & compact views** — toggle between detailed cards and dense rows
- **Auto-refresh** — configurable intervals (5m, 15m, 30m, 1h)
- **Launch at login** — start automatically with your Mac
- **Secure credential storage** — uses macOS Keychain, no plaintext secrets
- **OAuth + API key** — choose your preferred auth method per provider

## Supported Providers

| Provider | Auth Methods | What's Tracked |
|----------|-------------|----------------|
| **Claude** | OAuth (PKCE), API key | 5-hour & 7-day utilization %, reset countdowns |
| **GitHub Copilot** | Device flow OAuth | Premium requests used / entitlement, reset date |
| **ChatGPT** | OAuth, API key | Plan tier, connection status |
| **Gemini** | API key | Model count, Pro/Ultra detection |
| **Kimi AI** | API key | Connection status |

## Install

### Requirements

- macOS 14 (Sonoma) or later

### Build from source

```bash
git clone https://github.com/ayangabryl/QuotaBar.git
cd QuotaBar
open QuotaBar.xcodeproj
```

Build and run in Xcode (⌘R).

## Usage

1. Click the menu bar icon to open QuotaBar
2. Click **Add Account** and select a provider
3. Authenticate via OAuth or enter an API key
4. Your usage appears in the menu bar dropdown

## Contributing

Contributions are welcome! Feel free to:

- Open an issue for bugs or feature requests
- Submit a pull request
- Add support for new providers

### Adding a new provider

1. Create `YourProviderAuthService.swift` in `Services/`
2. Create `YourProviderUsageService.swift` in `Services/`
3. Add a case to `ServiceType` in `Models/Subscription.swift`
4. Wire it up in `SubscriptionStore.swift` and `MenuBarContentView.swift`

## Architecture

```
QuotaBar/
├── QuotaBarApp.swift              # App entry point, menu bar setup
├── Models/
│   └── Subscription.swift         # ServiceType, Account, AuthMethod
├── Services/
│   ├── AnthropicAuthService.swift  # Claude OAuth + API key auth
│   ├── AnthropicUsageService.swift # Claude usage fetching
│   ├── GitHubAuthService.swift     # Copilot device flow auth
│   ├── GitHubUsageService.swift    # Copilot usage fetching
│   ├── OpenAIAuthService.swift     # ChatGPT OAuth + API key auth
│   ├── OpenAIUsageService.swift    # ChatGPT usage fetching
│   ├── GeminiAuthService.swift     # Gemini API key auth
│   ├── GeminiUsageService.swift    # Gemini validation
│   ├── KimiAuthService.swift       # Kimi API key auth
│   └── KimiUsageService.swift      # Kimi validation
├── ViewModels/
│   └── SubscriptionStore.swift    # Central state management
└── Views/
    ├── MenuBarContentView.swift   # Main menu bar dropdown UI
    ├── SettingsView.swift         # Settings window
    └── SubscriptionCardView.swift # Account card components
```

## License

[MIT](LICENSE)
