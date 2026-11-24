import AppKit

/// Monochrome template artwork follows the menu bar's light/dark appearance.
/// Black is an alpha-mask source, not the displayed color. AppKit supplies the
/// foreground and highlight treatment over the user's own menu bar background.
/// Do not fill the image background or bake an accent color into this template.
/// Empty plots intentionally have no trace: they must not imply measured activity.
@MainActor
enum StatusGraphic {
    static func image(metric: Metric, mode: DisplayMode) -> NSImage {
        let hasText = mode != .graph
        let hasGraph = mode != .text
        let textWidth: CGFloat = hasText ? (metric == .network ? 66 : 58) : 28
        let graphWidth: CGFloat = hasGraph ? 34 : 0
        let size = NSSize(width: textWidth + graphWidth, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        if hasText && metric == .network {
            // AppKit's image coordinates start at the bottom: download is above upload.
            ("↓ — B/s" as NSString).draw(at: NSPoint(x: 1, y: 11), withAttributes: attributes)
            ("↑ — B/s" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attributes)
        } else {
            let label = hasText ? "\(metric.shortName) —" : metric.shortName
            (label as NSString).draw(at: NSPoint(x: 1, y: 5), withAttributes: attributes)
        }
        if hasGraph {
            NSColor.black.setStroke()
            let baselines: [CGFloat] = metric == .network ? [5, 16] : [7]
            for y in baselines {
                let path = NSBezierPath()
                path.lineWidth = 1
                path.setLineDash([2, 2], count: 2, phase: 0)
                path.move(to: NSPoint(x: textWidth + 2, y: y))
                path.line(to: NSPoint(x: size.width - 2, y: y))
                path.stroke()
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "\(metric.title), no data"
        return image
    }
}
