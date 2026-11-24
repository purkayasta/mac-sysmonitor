import Foundation

// Raw values are persisted identifiers from the first release. Display titles
// can change independently.
enum Metric: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "RAM"
    case swap = "Swap"
    case network = "Network speed"
    case disk = "Disk I/O"

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .swap: "Swap"
        case .network: "Network speed"
        case .disk: "Disk I/O"
        }
    }

    var shortName: String {
        switch self {
        case .network: "NET"
        case .disk: "DISK"
        default: title
        }
    }
}

enum DisplayMode: String, CaseIterable, Sendable {
    case text = "Text"
    case graph = "Mini graph"
    case combined = "Text + mini graph"

    var title: String {
        switch self {
        case .text: "Text"
        case .graph: "Mini graph"
        case .combined: "Text + mini graph"
        }
    }
}

struct SettingsChanges {
    var visibility: [Metric: Bool] = [:]
    var modes: [Metric: DisplayMode] = [:]
    var interval: Int?
    var launchAtLogin: Bool?

    var isEmpty: Bool { visibility.isEmpty && modes.isEmpty && interval == nil && launchAtLogin == nil }
}

final class SettingsStore {
    static let intervals = [1, 2, 3, 5, 10, 30]
    private static let defaultInterval = 3
    private static let intervalKey = "refreshIntervalSeconds"
    private static let launchAtLoginKey = "launchAtLogin"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var registration: [String: Any] = [Self.intervalKey: Self.defaultInterval, Self.launchAtLoginKey: false]
        for metric in Metric.allCases {
            registration[visibilityKey(metric)] = true
            registration[modeKey(metric)] = DisplayMode.text.rawValue
        }
        defaults.register(defaults: registration)
        if !Self.intervals.contains(defaults.integer(forKey: Self.intervalKey)) {
            defaults.set(Self.defaultInterval, forKey: Self.intervalKey)
        }
    }

    func isEnabled(_ metric: Metric) -> Bool {
        defaults.bool(forKey: visibilityKey(metric))
    }

    func displayMode(for metric: Metric) -> DisplayMode {
        DisplayMode(rawValue: defaults.string(forKey: modeKey(metric)) ?? "") ?? .text
    }

    var launchAtLogin: Bool { defaults.bool(forKey: Self.launchAtLoginKey) }

    func setLaunchAtLogin(_ enabled: Bool) { defaults.set(enabled, forKey: Self.launchAtLoginKey) }

    var interval: Int {
        let seconds = defaults.integer(forKey: Self.intervalKey)
        return Self.intervals.contains(seconds) ? seconds : Self.defaultInterval
    }

    func apply(_ changes: SettingsChanges) -> SettingsChanges {
        var applied = SettingsChanges()
        for (metric, enabled) in changes.visibility where enabled != isEnabled(metric) {
            defaults.set(enabled, forKey: visibilityKey(metric))
            applied.visibility[metric] = enabled
        }
        for (metric, mode) in changes.modes where mode != displayMode(for: metric) {
            defaults.set(mode.rawValue, forKey: modeKey(metric))
            applied.modes[metric] = mode
        }
        if let seconds = changes.interval, Self.intervals.contains(seconds), seconds != interval {
            defaults.set(seconds, forKey: Self.intervalKey)
            applied.interval = seconds
        }
        if let enabled = changes.launchAtLogin, enabled != launchAtLogin {
            defaults.set(enabled, forKey: Self.launchAtLoginKey)
            applied.launchAtLogin = enabled
        }
        return applied
    }

    private func visibilityKey(_ metric: Metric) -> String { "metric.\(metric.rawValue).enabled" }
    private func modeKey(_ metric: Metric) -> String { "metric.\(metric.rawValue).displayMode" }
}
