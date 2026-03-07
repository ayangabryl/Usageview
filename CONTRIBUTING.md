# Contributing to Usageview

Thanks for your interest in contributing! Here's how to get started.

## Quick Setup

```bash
git clone https://github.com/ayangabryl/Usageview.git
cd Usageview
make setup    # installs SwiftLint + git hooks
```

That's it. The pre-commit hook will automatically lint your code before each commit.

## Development Workflow

```bash
make build    # build the project
make lint     # check for lint issues
make fix      # auto-fix lint issues
make clean    # clean build artifacts
```

Or open `Usageview.xcodeproj` in Xcode and hit ⌘R.

## Making Changes

1. **Fork** the repo and create a branch from `main`
2. Run `make setup` (first time only)
3. Make your changes
4. Run `make lint` to check for issues
5. Test by building and running the app
6. Submit a **pull request**

## Adding a New Provider

Want to add support for a new AI service? Here's the pattern:

### 1. Create the auth service

Create `Usageview/Services/YourProvider/YourProviderAuthService.swift`:

```swift
import Foundation

@Observable
@MainActor
final class YourProviderAuthService {
    private var tokens: [UUID: String] = [:]

    func isConnected(accountId: UUID) -> Bool {
        tokens[accountId] != nil
    }

    func connect(accountId: UUID, apiKey: String) {
        // Store credentials in Keychain
        tokens[accountId] = apiKey
    }

    func disconnect(accountId: UUID) {
        tokens.removeValue(forKey: accountId)
    }
}
```

### 2. Create the usage service

Create `Usageview/Services/YourProvider/YourProviderUsageService.swift`:

```swift
import Foundation

@MainActor
final class YourProviderUsageService {
    let authService: YourProviderAuthService

    init(authService: YourProviderAuthService) {
        self.authService = authService
    }

    func fetchUsage(for accountId: UUID) async -> UsageResult? {
        // Fetch usage data from the provider's API
    }
}
```

### 3. Add the service type

In `Usageview/Models/ServiceType.swift`, add a new case:

```swift
enum ServiceType: String, Codable, CaseIterable, Sendable {
    // ... existing cases
    case yourProvider
}
```

Then fill in all the computed properties (`displayName`, `assetName`, `accentColor`, etc.).

### 4. Wire it up

- Add the auth/usage services to `AccountStore.swift`
- Add the connect screen to `MenuBarContentView.swift`
- Add a brand logo to `Assets.xcassets/`

### 5. Submit

Open a PR with:
- A brief description of the provider
- What data it tracks
- How authentication works

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/). The commit-msg hook enforces this automatically.

**Format:** `type(scope): description`

| Type | When to use |
|:-----|:------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Code style (formatting, no logic change) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance (deps, configs, scripts) |
| `ci` | CI/CD changes |
| `perf` | Performance improvement |
| `build` | Build system changes |

**Scope** is optional — use the provider name or area (e.g. `claude`, `copilot`, `ui`, `auth`).

**Examples:**
```
feat(claude): add 5-hour rate window tracking
fix(copilot): handle expired OAuth token gracefully
docs: update contributing guide
refactor(services): extract shared auth logic
chore: bump SwiftLint to 0.55
```

## Code Style

- We use **SwiftLint** — the config is in `.swiftlint.yml`
- Follow existing patterns in the codebase
- Use `@Observable` and `@MainActor` for services
- Store credentials in macOS Keychain, never in plain text
- Keep views small and composable

## Reporting Bugs

Open an issue with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

## Feature Requests

Open an issue tagged with "enhancement". Describe:
- What you'd like to see
- Why it's useful
- Any implementation ideas

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
