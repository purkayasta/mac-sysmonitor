import Foundation

struct CPUTicks: Sendable, Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

struct ByteCounters: Sendable, Equatable {
    let incoming: UInt64
    let outgoing: UInt64
}

enum RawMetricSample: Sendable {
    case cpu(CPUTicks)
    case percentage(Double)
    case capacity(used: UInt64, total: UInt64)
    case counters([String: ByteCounters])
}

struct SamplingError: Error, Sendable {
    let message: String
}

protocol SystemCounterSource: Sendable {
    func read(_ metric: Metric) -> Result<RawMetricSample, SamplingError>
}

enum CounterMath {
    static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double? {
        // Kernel CPU ticks are 32-bit counters; subtraction handles rollover.
        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let idle = UInt64(current.idle &- previous.idle)
        let nice = UInt64(current.nice &- previous.nice)
        let busy = user + system + nice
        let total = busy + idle
        return total == 0 ? nil : Double(busy) / Double(total) * 100
    }

    static func rates(previous: [String: ByteCounters], current: [String: ByteCounters], elapsed: TimeInterval) -> ByteRates? {
        guard elapsed.isFinite && elapsed > 0 else { return nil }
        guard Set(previous.keys) == Set(current.keys) else { return nil }
        var incoming = 0.0
        var outgoing = 0.0
        // Compare each device separately. Topology changes and counter resets
        // require a fresh baseline rather than a fabricated zero or a spike.
        for (name, counter) in current {
            guard let old = previous[name], counter.incoming >= old.incoming, counter.outgoing >= old.outgoing else { return nil }
            incoming += Double(counter.incoming - old.incoming) / elapsed
            outgoing += Double(counter.outgoing - old.outgoing) / elapsed
        }
        guard incoming.isFinite && outgoing.isFinite else { return nil }
        return ByteRates(incoming: incoming, outgoing: outgoing)
    }

    struct ByteRates { let incoming: Double; let outgoing: Double }
}

actor SystemSampler {
    private let source: any SystemCounterSource
    private var previous: [Metric: (sample: RawMetricSample, time: TimeInterval)] = [:]
    private var configuration = 0

    init(source: any SystemCounterSource = NativeSystemCounters()) { self.source = source }

    func sample(enabled: Set<Metric>, at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
                configuration: Int = 0) -> [Metric: MetricReading] {
        guard configuration >= self.configuration else { return [:] }
        if configuration != self.configuration {
            previous.removeAll()
            self.configuration = configuration
        }
        previous = previous.filter { enabled.contains($0.key) }
        var readings: [Metric: MetricReading] = [:]
        for metric in Metric.allCases where enabled.contains(metric) {
            if Task.isCancelled { break }
            switch source.read(metric) {
            case .failure(let error):
                previous[metric] = nil
                readings[metric] = .unavailable(error.message)
            case .success(let raw):
                let old = previous[metric]
                previous[metric] = (raw, time)
                switch raw {
                case .cpu(let ticks):
                    if let old, case .cpu(let baseline) = old.sample,
                       let usage = CounterMath.cpuUsage(previous: baseline, current: ticks) {
                        readings[metric] = MetricReading(state: .available, primary: usage)
                    } else { readings[metric] = .measuring }
                case .percentage(let value):
                    readings[metric] = value.isFinite && (0...100).contains(value)
                        ? MetricReading(state: .available, primary: value) : .unavailable("Invalid utilization counter")
                case .capacity(let used, let total):
                    readings[metric] = used <= total ? MetricReading(state: .available, primary: Double(used), capacity: Double(total))
                        : .unavailable("Invalid memory counters")
                case .counters(let counters):
                    if let old, case .counters(let baseline) = old.sample,
                       let rates = CounterMath.rates(previous: baseline, current: counters, elapsed: time - old.time) {
                        readings[metric] = MetricReading(state: .available, primary: rates.incoming, secondary: rates.outgoing)
                    } else { readings[metric] = .measuring }
                }
            }
        }
        return readings
    }
}
