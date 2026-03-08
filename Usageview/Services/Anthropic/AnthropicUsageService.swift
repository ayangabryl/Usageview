import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "AnthropicUsage")

struct ClaudeUsageData: Sendable {
    var fiveHourUtilization: Double
    var fiveHourResetsAt: Date?
    var sevenDayUtilization: Double
    var sevenDayResetsAt: Date?
    // Extra metadata from usage response
    var planTier: String?
    var organizationName: String?
}

@MainActor
final class AnthropicUsageService: Sendable {
    private let authService: AnthropicAuthService

    init(authService: AnthropicAuthService) {
        self.authService = authService
    }

    func fetchUsage(for accountId: UUID) async -> ClaudeUsageData? {
        // Prefer Claude Code CLI credentials for most accurate usage data
        guard let token = await authService.getValidTokenPreferCLI(for: accountId) else {
            logger.error("No valid token for account \(accountId.uuidString)")
            return nil
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        // Detect Claude Code version for User-Agent (matches what Claude Code CLI sends)
        let claudeVersion = Self.detectClaudeCodeVersion() ?? "2.1.0"

        // Retry up to 5 times on 429 (rate limit on the usage endpoint itself)
        for attempt in 0..<5 {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            // The usage API requires a claude-code User-Agent to return proper data
            request.setValue("claude-code/\(claudeVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 200 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    logger.info("Usage response: \(bodyStr.prefix(500))")
                    return parseUsageResponse(data: data)
                } else if http.statusCode == 429 {
                    // Rate limited on the usage endpoint — wait and retry
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { Double($0) } ?? 3.0
                    let delay = max(retryAfter, 3.0) // at least 3s
                    logger.info("Usage endpoint 429, retry-after=\(retryAfter), attempt \(attempt + 1)/5")
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                } else {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    logger.error("Usage endpoint status \(http.statusCode): \(bodyStr.prefix(300))")
                    return nil
                }
            } catch {
                logger.error("Usage fetch error: \(error.localizedDescription)")
                return nil
            }
        }

        logger.error("Usage fetch exhausted retries for \(accountId.uuidString)")
        return nil
    }

    private func parseUsageResponse(data: Data) -> ClaudeUsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String?) -> Date? {
            guard let str else { return nil }
            return formatter.date(from: str) ?? formatterNoFrac.date(from: str)
        }

        // Log all top-level keys for debugging
        logger.info("Usage response keys: \(json.keys.sorted(), privacy: .public)")

        // API response: { "five_hour": { "utilization": 31.0, "resets_at": "..." }, "seven_day": { ... } }
        let fiveHour = json["five_hour"] as? [String: Any]
        let sevenDay = json["seven_day"] as? [String: Any]

        // Also try alternative key names
        let fiveHourData = fiveHour
            ?? json["5_hour"] as? [String: Any]
            ?? json["hourly"] as? [String: Any]
            ?? json["short_term"] as? [String: Any]
        let sevenDayData = sevenDay
            ?? json["7_day"] as? [String: Any]
            ?? json["daily"] as? [String: Any]
            ?? json["weekly"] as? [String: Any]
            ?? json["long_term"] as? [String: Any]

        if fiveHourData != nil {
            logger.info("5-hour data keys: \(fiveHourData!.keys.sorted(), privacy: .public)")
        }
        if sevenDayData != nil {
            logger.info("7-day data keys: \(sevenDayData!.keys.sorted(), privacy: .public)")
        }

        guard fiveHourData != nil || sevenDayData != nil else {
            logger.warning("Unknown usage response keys: \(json.keys.sorted(), privacy: .public)")
            return nil
        }

        // Extract plan/org metadata from top-level fields if present
        let planTier = json["plan"] as? String
            ?? json["tier"] as? String
            ?? json["plan_tier"] as? String
            ?? json["plan_type"] as? String
            ?? (json["plan"] as? [String: Any])?["name"] as? String
            ?? (json["plan"] as? [String: Any])?["tier"] as? String
        let orgName = json["organization"] as? String
            ?? json["organization_name"] as? String
            ?? json["org_name"] as? String
            ?? (json["organization"] as? [String: Any])?["name"] as? String

        return ClaudeUsageData(
            fiveHourUtilization: fiveHourData?["utilization"] as? Double ?? 0,
            fiveHourResetsAt: parseDate(fiveHourData?["resets_at"] as? String
                ?? fiveHourData?["reset_at"] as? String),
            sevenDayUtilization: sevenDayData?["utilization"] as? Double ?? 0,
            sevenDayResetsAt: parseDate(sevenDayData?["resets_at"] as? String
                ?? sevenDayData?["reset_at"] as? String),
            planTier: planTier,
            organizationName: orgName
        )
    }

    // MARK: - Claude Code Version Detection

    /// Detect installed Claude Code CLI version for User-Agent header.
    /// Returns nil if not installed or detection fails.
    private static func detectClaudeCodeVersion() -> String? {
        // Try to find the claude binary
        let possiblePaths = [
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "/opt/homebrew/bin/claude"
        ]
        
        // Also check PATH via /usr/bin/which
        let whichProc = Process()
        whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProc.arguments = ["claude"]
        let whichPipe = Pipe()
        whichProc.standardOutput = whichPipe
        whichProc.standardError = Pipe()
        
        var claudePath: String?
        if let _ = try? whichProc.run() {
            whichProc.waitUntilExit()
            if whichProc.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                claudePath = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if claudePath == nil || claudePath!.isEmpty {
            claudePath = possiblePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        
        guard let path = claudePath, !path.isEmpty else { return nil }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        
        do {
            try proc.run()
            // Timeout after 3 seconds
            let deadline = Date().addingTimeInterval(3.0)
            while proc.isRunning, Date() < deadline {
                usleep(50000)
            }
            if proc.isRunning {
                proc.terminate()
                usleep(200000)
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
            
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let version = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace).first
                .map(String.init)
            return version?.isEmpty == true ? nil : version
        } catch {
            return nil
        }
    }

}
