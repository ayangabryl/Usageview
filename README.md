# QuotaBar

**Keep your AI usage limits visible — right in the menu bar.**

QuotaBar is a lightweight macOS app that shows how much of your AI quota you've used across Claude, GitHub Copilot, ChatGPT, Gemini, and Kimi — with reset countdowns so you always know when you get more.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![MIT License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

<!-- Add a screenshot here: ![QuotaBar Screenshot](screenshots/screenshot.png) -->

---

## Why QuotaBar?

If you use AI coding tools, you've hit rate limits mid-flow. QuotaBar sits in your menu bar and shows:

- **How much quota you've used** — per provider, per account
- **When it resets** — countdown timers for each rate window
- **Multiple accounts** — track personal + work accounts side by side

No Dock icon. No background noise. Just a glance at your menu bar.

---

## Supported Providers

| Provider | Auth | What You See |
|:---------|:-----|:-------------|
| **Claude** | OAuth or API key | 5-hour + 7-day utilization with reset countdowns |
| **GitHub Copilot** | Device flow sign-in | Premium requests used (e.g. 142/300), reset date |
| **ChatGPT** | OAuth or API key | Plan tier (Free/Plus/Pro/Team/Enterprise) |
| **Gemini** | API key | Available models, Pro/Ultra detection |
| **Kimi AI** | API key | Connection status |

> Want another provider? [Open an issue](https://github.com/ayangabryl/QuotaBar/issues/new?template=new_provider.md) or [submit a PR](CONTRIBUTING.md#adding-a-new-provider).

---

## Install

**Requirements:** macOS 14 (Sonoma) or later

### Build from source

```bash
git clone https://github.com/ayangabryl/QuotaBar.git
cd QuotaBar
open QuotaBar.xcodeproj
```

Hit **⌘R** in Xcode to build and run.

---

## Getting Started

1. **Click the menu bar icon** to open QuotaBar
2. **Add Account** → pick a provider
3. **Sign in** via OAuth or paste an API key
4. **Done** — your usage appears instantly

Switch between **expanded** (detailed cards) and **compact** (dense rows) views with one click.

---

## Features

| Feature | Details |
|:--------|:--------|
| Menu bar native | No Dock icon, minimal footprint |
| Multiple accounts | Personal + work accounts per provider |
| Claude dual windows | 5-hour and 7-day rate limits shown simultaneously |
| Expanded & compact views | Toggle between detailed cards and dense rows |
| Auto-refresh | Configurable: 5m / 15m / 30m / 1h |
| Launch at login | Start with your Mac |
| Secure storage | macOS Keychain — no plaintext secrets |
| OAuth + API key | Choose your preferred auth per provider |

---

## Contributing

We'd love your help! Whether it's a bug fix, new provider, or UI improvement.

```bash
git clone https://github.com/ayangabryl/QuotaBar.git
cd QuotaBar
make setup    # installs SwiftLint + git hooks (one-time)
make build    # build the project
make lint     # check code style
```

The pre-commit hook runs SwiftLint automatically — no extra steps needed.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide, including how to add a new provider.

---

## Architecture

```
QuotaBar/
├── App/                          # Entry point
│   └── QuotaBarApp.swift
├── Models/                       # Data types
│   ├── Account.swift
│   ├── AuthMethod.swift
│   └── ServiceType.swift
├── Services/                     # Provider integrations
│   ├── Anthropic/                #   Claude
│   ├── GitHub/                   #   Copilot
│   ├── OpenAI/                   #   ChatGPT
│   ├── Gemini/                   #   Gemini
│   └── Kimi/                     #   Kimi AI
├── ViewModels/                   # State management
│   └── AccountStore.swift
├── Views/                        # UI components
│   ├── MenuBarContentView.swift
│   ├── SettingsView.swift
│   └── AccountCardView.swift
└── Extensions/                   # Utilities
    └── Color+Hex.swift
```

---

## License

[MIT](LICENSE) — use it however you want.
