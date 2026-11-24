import Foundation

struct MetricReading: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case measuring
        case available
        case unavailable(String)
    }

    var state: State
    var primary: Double = 0
    var secondary: Double = 0
    var capacity: Double = 0

    static let measuring = MetricReading(state: .measuring)
    static func unavailable(_ reason: String) -> Self { Self(state: .unavailable(reason)) }

    func lines(for metric: Metric) -> [String] {
        switch state {
        case .measuring: return ["Measuring…"]
        case .unavailable(let reason): return ["Unavailable", reason]
        case .available:
            switch metric {
            case .cpu: return ["CPU usage: \(Self.percent(primary))"]
            case .gpu: return ["GPU usage: \(Self.percent(primary))"]
            case .memory: return ["Memory used: \(Self.bytes(primary))", "Physical memory: \(Self.bytes(capacity))"]
            case .swap: return ["Swap used: \(Self.bytes(primary))", "Swap allocated: \(Self.bytes(capacity))"]
            case .network: return ["Download: \(Self.rate(primary))", "Upload: \(Self.rate(secondary))"]
            case .disk: return ["Read: \(Self.rate(primary))", "Write: \(Self.rate(secondary))"]
            }
        }
    }

    func compactText(for metric: Metric) -> [String] {
        guard state == .available else {
            return [.network, .disk, .memory, .swap].contains(metric) ? ["—", "—"] : ["—"]
        }
        switch metric {
        case .cpu, .gpu: return [Self.percent(primary)]
        case .memory: return [Self.compactBytes(primary), Self.compactBytes(capacity)]
        case .swap: return [Self.compactBytes(primary), Self.compactBytes(capacity)]
        case .network, .disk: return [Self.compactBytes(primary) + "/s", Self.compactBytes(secondary) + "/s"]
        }
    }

    private static func compactBytes(_ value: Double) -> String {
        bytes(value).replacingOccurrences(of: "KiB", with: "KB")
            .replacingOccurrences(of: "MiB", with: "MB")
            .replacingOccurrences(of: "GiB", with: "GB")
            .replacingOccurrences(of: "TiB", with: "TB")
    }

    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }
    static func rate(_ value: Double) -> String { bytes(value) + "/s" }
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = value.isFinite ? max(0, value) : 0
        var unit = 0
        while amount >= 1024 && unit < units.count - 1 { amount /= 1024; unit += 1 }
        return String(format: amount < 10 && unit > 0 ? "%.1f %@" : "%.0f %@", amount, units[unit])
    }
}

struct GraphPoint: Sendable, Equatable {
    let primary: Double
    let secondary: Double
}

struct MetricHistory: Sendable {
    static let limit = 60
    private(set) var points: [GraphPoint?] = []

    mutating func append(_ reading: MetricReading, for metric: Metric) {
        if reading.state != .available { points.append(nil) }
        else {
            let divisor: Double
            switch metric {
            case .cpu, .gpu: divisor = 100
            case .memory, .swap: divisor = max(1, reading.capacity)
            case .network, .disk: divisor = 1
            }
            points.append(GraphPoint(primary: reading.primary / divisor, secondary: reading.secondary / divisor))
        }
        if points.count > Self.limit { points.removeFirst(points.count - Self.limit) }
    }
}
