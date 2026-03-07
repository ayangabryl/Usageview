import Foundation
import os

private let logger = Logger(subsystem: "com.ayangabryl.usage", category: "JetBrainsUsage")

struct JetBrainsUsageData: Sendable {
    var isActive: Bool
    var currentUsed: Double = 0
    var maximum: Double = 0
    var resetDate: Date?
    var ideName: String?

    var usagePercent: Double {
        guard maximum > 0 else { return 0 }
        return (currentUsed / maximum) * 100
    }
}

@MainActor
final class JetBrainsUsageService: Sendable {
    private let authService: JetBrainsAuthService

    init(authService: JetBrainsAuthService) {
        self.authService = authService
    }

    /// Parse JetBrains IDE AIAssistantQuotaManager2.xml for quota info
    func fetchUsage(for accountId: UUID) async -> JetBrainsUsageData? {
        guard let xmlPath = authService.getConfigPath(for: accountId) else {
            logger.info("JetBrains: no XML config path found")
            return nil
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: xmlPath) else {
            logger.info("JetBrains: XML file not found at \(xmlPath)")
            return nil
        }

        guard let xmlData = fm.contents(atPath: xmlPath),
              let xmlString = String(data: xmlData, encoding: .utf8) else {
            return nil
        }

        return parseQuotaXML(xmlString, path: xmlPath)
    }

    // MARK: - XML Parsing

    private func parseQuotaXML(_ xml: String, path: String) -> JetBrainsUsageData? {
        // Extract quotaInfo value attribute
        guard let quotaValue = extractOptionValue(from: xml, name: "quotaInfo") else {
            logger.info("JetBrains: quotaInfo not found in XML")
            return JetBrainsUsageData(isActive: true)
        }

        // Decode HTML entities
        let decoded = decodeHTMLEntities(quotaValue)

        guard let jsonData = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.error("JetBrains: failed to parse quotaInfo JSON")
            return JetBrainsUsageData(isActive: true)
        }

        var result = JetBrainsUsageData(isActive: true)
        result.currentUsed = parseNumber(json["current"]) ?? 0
        result.maximum = parseNumber(json["maximum"]) ?? 0

        // Extract IDE name from path
        let components = path.components(separatedBy: "/")
        if let optionsIndex = components.firstIndex(of: "options"), optionsIndex > 0 {
            result.ideName = components[optionsIndex - 1]
        }

        // Parse nextRefill for reset date
        if let refillValue = extractOptionValue(from: xml, name: "nextRefill") {
            let refillDecoded = decodeHTMLEntities(refillValue)
            if let refillData = refillDecoded.data(using: .utf8),
               let refillJson = try? JSONSerialization.jsonObject(with: refillData) as? [String: Any],
               let nextStr = refillJson["next"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                result.resetDate = formatter.date(from: nextStr)
            }
        }

        // Also check quotaInfo.until as fallback reset
        if result.resetDate == nil, let untilStr = json["until"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            result.resetDate = formatter.date(from: untilStr)
        }

        logger.info("JetBrains: used=\(result.currentUsed) max=\(result.maximum) reset=\(String(describing: result.resetDate))")
        return result
    }

    /// Extract the value attribute from an <option name="X" value="Y"/> element
    private func extractOptionValue(from xml: String, name: String) -> String? {
        // Match: <option name="quotaInfo" value="..."/>
        let pattern = #"<option\s+name="\#(name)"\s+value="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let valueRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[valueRange])
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\r")
            .replacingOccurrences(of: "&#9;", with: "\t")
    }

    private func parseNumber(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
