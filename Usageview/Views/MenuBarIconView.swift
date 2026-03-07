import AppKit
import SwiftUI

/// The style of menu bar icon.
enum MenuBarIconStyle: String, CaseIterable, Codable {
    case white = "White"
    case colored = "Colored"
    case dynamic = "Dynamic"

    var displayName: String { rawValue }
}

/// Renders a dynamic menu bar icon shaped like the Usageview logo — a horseshoe / gauge arc.
/// The arc fills clockwise from the left end to represent usage percentage.
@MainActor
enum MenuBarIconRenderer {

    // MARK: - Arc geometry

    /// The arc spans 270° in a U shape — gap at the top (around 90°/12-o'clock).
    /// Starts at upper-left (135°) and sweeps counter-clockwise (increasing angles)
    /// through left → bottom → right to upper-right (45°).
    private static let startAngle: CGFloat = 135   // upper-left arm of the U
    private static let endAngle: CGFloat = 45      // upper-right arm of the U
    private static let arcSpan: CGFloat = 270      // total degrees of the arc

    /// Generate an `NSImage` suitable for `MenuBarExtra` label.
    /// - Parameters:
    ///   - percent: Fill percentage 0–100. `nil` = idle state.
    ///   - style: The icon style (white/colored/dynamic).
    ///   - isStale: Dims the icon when data is stale or errored.
    ///   - showCheckmark: Briefly overlays a green checkmark in the center.
    static func icon(
        percent: Double?,
        style: MenuBarIconStyle = .dynamic,
        customColor: NSColor? = nil,
        isStale: Bool = false,
        showCheckmark: Bool = false
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let noData = (percent == nil)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            let opacity: CGFloat = isStale ? 0.35 : 1.0
            let clamped = min(max((percent ?? 0) / 100, 0), 1)

            let cx = rect.midX
            let cy = rect.midY + 0.5  // slight downward nudge so the U sits comfortably
            let radius: CGFloat = 7.0
            let lineWidth: CGFloat = 2.8

            // --- Background track (U shape) ---
            let trackPath = NSBezierPath()
            trackPath.appendArc(
                withCenter: NSPoint(x: cx, y: cy),
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            trackPath.lineWidth = lineWidth
            trackPath.lineCapStyle = .round

            let trackColor: NSColor
            if noData {
                // Solid white gauge when no accounts — always clearly visible
                trackColor = .white.withAlphaComponent(0.85)
            } else {
                switch style {
                case .white:
                    trackColor = .white.withAlphaComponent(0.20 * opacity)
                case .colored:
                    let base = customColor ?? NSColor(red: 0.38, green: 0.52, blue: 1.0, alpha: 1.0)
                    trackColor = base.withAlphaComponent(0.25 * opacity)
                case .dynamic:
                    trackColor = .labelColor.withAlphaComponent(0.15 * opacity)
                }
            }
            trackColor.setStroke()
            trackPath.stroke()

            // --- Filled arc ---
            if clamped > 0 {
                let fillEndDeg = startAngle + clamped * arcSpan

                let fillPath = NSBezierPath()
                fillPath.appendArc(
                    withCenter: NSPoint(x: cx, y: cy),
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: fillEndDeg,
                    clockwise: false
                )
                fillPath.lineWidth = lineWidth
                fillPath.lineCapStyle = .round

                let fillColor: NSColor
                switch style {
                case .white:
                    fillColor = .white.withAlphaComponent(opacity)
                case .colored:
                    let base = customColor ?? NSColor(red: 0.38, green: 0.52, blue: 1.0, alpha: 1.0)
                    fillColor = base.withAlphaComponent(opacity)
                case .dynamic:
                    if clamped >= 0.9 {
                        fillColor = .systemRed.withAlphaComponent(opacity)
                    } else if clamped >= 0.7 {
                        fillColor = .systemOrange.withAlphaComponent(opacity)
                    } else {
                        fillColor = .systemGreen.withAlphaComponent(opacity)
                    }
                }
                fillColor.setStroke()
                fillPath.stroke()

                // --- Small dot at the current fill position ---
                if clamped > 0.02 && clamped < 0.98 {
                    let dotAngleRad = fillEndDeg * .pi / 180
                    let dotX = cx + radius * cos(dotAngleRad)
                    let dotY = cy + radius * sin(dotAngleRad)
                    let dotR: CGFloat = 1.2
                    let dotRect = NSRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)
                    fillColor.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                }
            }

            // --- Green checkmark overlay (account linked) ---
            if showCheckmark {
                NSColor.systemGreen.setStroke()
                let check = NSBezierPath()
                let checkCx = rect.midX
                let checkCy = rect.midY + 0.5
                check.move(to: NSPoint(x: checkCx - 3.5, y: checkCy))
                check.line(to: NSPoint(x: checkCx - 1, y: checkCy - 3))
                check.line(to: NSPoint(x: checkCx + 4, y: checkCy + 3.5))
                check.lineWidth = 2.0
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Generate a simple idle icon (empty gauge) — solid white, always visible.
    static var idleIcon: NSImage {
        icon(percent: nil, style: .dynamic, isStale: true)
    }
}
