import AppKit

/// Template artwork lets AppKit choose native menu-bar contrast and highlights.
@MainActor
enum StatusGraphic {
    static func image(metric: Metric, mode: DisplayMode, reading: MetricReading = .measuring,
                      history: MetricHistory = MetricHistory()) -> NSImage {
        let hasText = mode != .graph
        let hasGraph = mode != .text
        let dual = metric == .network || metric == .disk
        let textWidth: CGFloat = hasText ? ((metric == .cpu || metric == .gpu) ? 58 : 90) : 28
        let size = NSSize(width: textWidth + (hasGraph ? 34 : 0), height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let values = reading.compactText(for: metric)
        if hasText && dual {
            let labels = metric == .network ? ["↓", "↑"] : ["R", "W"]
            ("\(labels[0]) \(values[0])" as NSString).draw(at: NSPoint(x: 1, y: 11), withAttributes: attributes)
            ("\(labels[1]) \(values[1])" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attributes)
        } else {
            let label = hasText ? "\(metric.shortName) \(values[0])" : metric.shortName
            (label as NSString).draw(at: NSPoint(x: 1, y: 5), withAttributes: attributes)
        }
        if hasGraph {
            let rateMetric = metric == .network || metric == .disk
            let maximum = rateMetric ? max(1024, history.points.compactMap { $0 }.map { max($0.primary, $0.secondary) }.max() ?? 0) : 1
            let lanes: [(CGFloat, CGFloat)] = dual ? [(12, 8), (1, 8)] : [(3, 16)]
            NSColor.black.setStroke()
            for (lane, bounds) in lanes.enumerated() {
                let path = NSBezierPath()
                path.lineWidth = 1
                var drawing = false
                let step = 30.0 / CGFloat(MetricHistory.limit - 1)
                for (index, point) in history.points.enumerated() {
                    guard let point else { drawing = false; continue }
                    let raw = lane == 0 ? point.primary : point.secondary
                    let value = min(1, max(0, raw / maximum))
                    let x = textWidth + 2 + CGFloat(MetricHistory.limit - history.points.count + index) * step
                    let position = NSPoint(x: x, y: bounds.0 + value * bounds.1)
                    if drawing { path.line(to: position) } else { path.move(to: position); drawing = true }
                }
                if history.points.allSatisfy({ $0 == nil }) {
                    path.setLineDash([2, 2], count: 2, phase: 0)
                    path.move(to: NSPoint(x: textWidth + 2, y: bounds.0))
                    path.line(to: NSPoint(x: size.width - 2, y: bounds.0))
                }
                path.stroke()
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "\(metric.title), \(reading.lines(for: metric).joined(separator: ", "))"
        return image
    }
}
