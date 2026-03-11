import Foundation
import Security

struct JetBrainsAccountInfo: Sendable {
    var name: String?
    var idePath: String?
}

@Observable
@MainActor
final class JetBrainsAuthService: Sendable {

    func isAuthenticated(for accountId: UUID) -> Bool {
        // JetBrains AI is "authenticated" if we can find the IDE config
        loadToken(key: configKey(for: accountId)) != nil || findIDEConfigPath() != nil
    }

    /// Store the IDE config path (or "auto" for auto-detection)
    func saveConfig(_ path: String, for accountId: UUID) -> JetBrainsAccountInfo {
        saveToken(key: configKey(for: accountId), value: path)
        let ideName = extractIDEName(from: path)
        return JetBrainsAccountInfo(name: ideName, idePath: path)
    }

    /// Get the stored config path, falling back to auto-detection
    func getConfigPath(for accountId: UUID) -> String? {
        if let stored = loadToken(key: configKey(for: accountId)) {
            if stored == "auto" {
                return findIDEConfigPath()
            }
            return stored
        }
        return findIDEConfigPath()
    }

    func disconnect(accountId: UUID) {
        removeToken(key: configKey(for: accountId))
    }

    /// Auto-enable by saving "auto" as config path
    func autoEnable(for accountId: UUID) -> JetBrainsAccountInfo? {
        guard let path = findIDEConfigPath() else { return nil }
        saveToken(key: configKey(for: accountId), value: "auto")
        let ideName = extractIDEName(from: path)
        return JetBrainsAccountInfo(name: ideName, idePath: path)
    }

    // MARK: - IDE Auto-Detection

    /// Find the most recently modified AIAssistantQuotaManager2.xml across JetBrains IDE configs
    func findIDEConfigPath() -> String? {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser.path

        // Scan JetBrains and Google (Android Studio) config dirs
        let searchDirs = [
            "\(homeDir)/Library/Application Support/JetBrains",
            "\(homeDir)/Library/Application Support/Google"
        ]

        var bestPath: String?
        var bestDate: Date?

        for searchDir in searchDirs {
            guard let ideDirs = try? fm.contentsOfDirectory(atPath: searchDir) else { continue }

            for ideDir in ideDirs {
                let xmlPath = "\(searchDir)/\(ideDir)/options/AIAssistantQuotaManager2.xml"
                guard fm.fileExists(atPath: xmlPath),
                      let attrs = try? fm.attributesOfItem(atPath: xmlPath),
                      let modDate = attrs[.modificationDate] as? Date
                else { continue }

                if bestDate == nil || modDate > bestDate! {
                    bestDate = modDate
                    bestPath = xmlPath
                }
            }
        }

        return bestPath
    }

    private func extractIDEName(from path: String) -> String {
        // Path like .../JetBrains/IntelliJIdea2025.1/options/...
        let components = path.components(separatedBy: "/")
        if let optionsIndex = components.firstIndex(of: "options"), optionsIndex > 0 {
            let dirName = components[optionsIndex - 1]
            // Clean up version suffix: "IntelliJIdea2025.1" → "IntelliJ IDEA"
            let cleaned = dirName
                .replacingOccurrences(of: #"\d{4}\.\d+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "IntelliJIdea", with: "IntelliJ IDEA")
                .replacingOccurrences(of: "PyCharm", with: "PyCharm")
                .replacingOccurrences(of: "WebStorm", with: "WebStorm")
                .replacingOccurrences(of: "GoLand", with: "GoLand")
                .replacingOccurrences(of: "CLion", with: "CLion")
                .replacingOccurrences(of: "RustRover", with: "RustRover")
                .replacingOccurrences(of: "AndroidStudio", with: "Android Studio")
                .trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? dirName : cleaned
        }
        return "JetBrains IDE"
    }

    // MARK: - Key Helpers

    private func configKey(for id: UUID) -> String {
        "com.ayangabryl.usage.jetbrains-config-\(id.uuidString)"
    }

    // MARK: - Keychain Storage

    private func saveToken(key: String, value: String) { KeychainHelper.save(value, forKey: key) }
    private func loadToken(key: String) -> String? { KeychainHelper.load(forKey: key) }
    private func removeToken(key: String) { KeychainHelper.remove(forKey: key) }
}
