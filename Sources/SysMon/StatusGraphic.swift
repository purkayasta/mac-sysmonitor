import AppKit

/// Template artwork lets AppKit choose native menu-bar contrast and highlights.
@MainActor
enum StatusGraphic {
    static func symbol(for metric: Metric) -> NSImage? {
        let name: String
        switch metric {
        case .cpu: name = "cpu"
        case .gpu: name = "display"
        case .memory: name = "memorychip"
        case .swap: name = "arrow.left.arrow.right"
        case .network: name = "network"
        case .disk: name = "internaldrive"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: metric.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
    }

    static func image(metric: Metric, mode: DisplayMode, reading: MetricReading = .measuring,
                      history: MetricHistory = MetricHistory()) -> NSImage {
        let hasText = mode != .graph
        let hasGraph = mode != .text
        let dual = metric == .network || metric == .disk
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        // The network arrows already identify the metric in numeric modes.
        let icon = metric == .network && hasText ? nil : symbol(for: metric)
        let values = reading.compactText(for: metric)
        let labels: [String]
        if !hasText {
            labels = icon == nil ? [metric.shortName] : []
        } else if dual || metric == .memory {
            labels = values
        } else {
            labels = [values[0]]
        }
        // Measure the actual labels instead of reserving a wide, mostly empty slot.
        let padding: CGFloat = 1
        let prefixes = hasText && dual ? (metric == .network ? ["↓", "↑"] : ["R", "W"]) : []
        let prefixWidth = ceil(prefixes.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
        let prefixColumnWidth = prefixes.isEmpty ? 0 : prefixWidth + 1
        let textWidth = ceil(labels.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
        let iconWidth: CGFloat = icon == nil ? 0 : 12
        let textStart = padding + iconWidth + (icon != nil && !labels.isEmpty ? 1 : 0)
        let valueStart = textStart + prefixColumnWidth
        let contentEnd = valueStart + textWidth
        let graphStart = contentEnd + 2
        let size = NSSize(width: hasGraph ? graphStart + 24 + padding : contentEnd + padding, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        if let icon {
            // Aspect-fit symbols in one centered slot so every metric aligns.
            let scale = min(iconWidth / icon.size.width, 12 / icon.size.height)
            let iconSize = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            let bounds = NSRect(x: padding + (iconWidth - iconSize.width) / 2,
                                y: (size.height - iconSize.height) / 2,
                                width: iconSize.width, height: iconSize.height)
            icon.draw(in: bounds)
        }
        for (index, label) in labels.enumerated() {
            let y: CGFloat = labels.count == 2 ? (index == 0 ? 11 : 0) : 5
            let width = (label as NSString).size(withAttributes: attributes).width
            // Direction markers have their own gutter; unequal rates must not
            // move the arrows or R/W labels out of alignment (including zero).
            if !prefixes.isEmpty {
                let prefix = prefixes[index] as NSString
                let prefixX = textStart + (prefixWidth - prefix.size(withAttributes: attributes).width) / 2
                prefix.draw(at: NSPoint(x: prefixX, y: y), withAttributes: attributes)
            }
            let x = valueStart + (textWidth - width) / 2
            (label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
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
                let step = 24.0 / CGFloat(MetricHistory.limit - 1)
                for (index, point) in history.points.enumerated() {
                    guard let point else { drawing = false; continue }
                    let raw = lane == 0 ? point.primary : point.secondary
                    let value = min(1, max(0, raw / maximum))
                    let x = graphStart + CGFloat(MetricHistory.limit - history.points.count + index) * step
                    let position = NSPoint(x: x, y: bounds.0 + value * bounds.1)
                    if drawing { path.line(to: position) } else { path.move(to: position); drawing = true }
                }
                if history.points.allSatisfy({ $0 == nil }) {
                    path.setLineDash([2, 2], count: 2, phase: 0)
                    path.move(to: NSPoint(x: graphStart, y: bounds.0))
                    path.line(to: NSPoint(x: graphStart + 24, y: bounds.0))
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
