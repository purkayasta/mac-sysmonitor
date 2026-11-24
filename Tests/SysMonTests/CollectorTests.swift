import Foundation

private struct Failure: Error, CustomStringConvertible { let description: String }
private func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw Failure(description: message) }
}

private final class CounterFixture: SystemCounterSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Metric: Result<RawMetricSample, SamplingError>] = [:]
    private var counts: [Metric: Int] = [:]
    var delay: TimeInterval = 0

    func set(_ metric: Metric, _ value: Result<RawMetricSample, SamplingError>) {
        lock.lock(); defer { lock.unlock() }
        values[metric] = value
    }
    func count(_ metric: Metric) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[metric] ?? 0
    }
    func read(_ metric: Metric) -> Result<RawMetricSample, SamplingError> {
        lock.lock()
        counts[metric, default: 0] += 1
        let value = values[metric] ?? .failure(SamplingError(message: "Fixture counter absent"))
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return value
    }
}

@main
struct CollectorTests {
    @MainActor
    static func main() async throws {
        let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let ticks = CPUTicks(user: 10, system: 20, idle: 60, nice: 10)
        try expect(CounterMath.cpuUsage(previous: zero, current: ticks) == 40, "CPU tick normalization failed")
        try expect(CounterMath.cpuUsage(previous: ticks, current: ticks) == nil, "Unchanged CPU ticks must stay measuring")
        let beforeWrap = CPUTicks(user: .max - 9, system: 0, idle: 0, nice: 0)
        let afterWrap = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        try expect(CounterMath.cpuUsage(previous: beforeWrap, current: afterWrap) == 50, "CPU tick rollover failed")
        print("PASS CPU: normalized ticks, no-tick warmup, and 32-bit rollover")

        let before = ["en0": ByteCounters(incoming: 1000, outgoing: 100), "removed": ByteCounters(incoming: 9000, outgoing: 9000)]
        let after = ["en0": ByteCounters(incoming: 1600, outgoing: 400), "new": ByteCounters(incoming: 9_000_000, outgoing: 9_000_000)]
        let steadyBefore = ["en0": before["en0"]!]
        let steadyAfter = ["en0": after["en0"]!]
        let rates = CounterMath.rates(previous: steadyBefore, current: steadyAfter, elapsed: 3)!
        try expect(rates.incoming == 200 && rates.outgoing == 100, "Rates must use actual elapsed time")
        try expect(CounterMath.rates(previous: before, current: after, elapsed: 3) == nil, "Topology changes need a fresh baseline")
        let reset = CounterMath.rates(previous: steadyBefore, current: ["en0": ByteCounters(incoming: 0, outgoing: 100)], elapsed: 1)
        try expect(reset == nil, "Reset counters must not fabricate zero usage or spikes")
        for interval in [0.0, -1, .nan, .infinity] {
            try expect(CounterMath.rates(previous: before, current: after, elapsed: interval) == nil, "Invalid elapsed interval accepted")
        }
        let large = CounterMath.rates(previous: ["disk": ByteCounters(incoming: 0, outgoing: 0)],
                                      current: ["disk": ByteCounters(incoming: 8_589_934_592, outgoing: 0)], elapsed: 2)!
        try expect(large.incoming == 4_294_967_296, "64-bit rate counters were truncated")
        print("PASS network/disk: elapsed time, hot-plug, removal, resets, invalid intervals, and 64-bit counters")

        let source = CounterFixture()
        source.set(.cpu, .success(.cpu(zero)))
        source.set(.gpu, .success(.percentage(0)))
        source.set(.memory, .success(.capacity(used: 512, total: 1024)))
        source.set(.swap, .success(.capacity(used: 0, total: 0)))
        source.set(.network, .success(.counters(steadyBefore)))
        source.set(.disk, .success(.counters(steadyBefore)))
        let sampler = SystemSampler(source: source)
        let disabled = await sampler.sample(enabled: [])
        try expect(disabled.isEmpty && Metric.allCases.allSatisfy { source.count($0) == 0 }, "Disabled metrics read native counters")
        let initial = await sampler.sample(enabled: Set(Metric.allCases), at: 10)
        try expect(initial[.cpu]?.state == .measuring && initial[.network]?.state == .measuring && initial[.disk]?.state == .measuring,
                   "Rate/CPU collectors need a baseline before presenting real measurements")
        try expect(initial[.gpu]?.state == .available && initial[.gpu]?.primary == 0, "Real zero GPU usage was confused with missing data")
        try expect(initial[.swap]?.state == .available && initial[.swap]?.primary == 0 && initial[.swap]?.capacity == 0,
                   "Zero allocated swap is a valid real reading")
        try expect(initial[.memory]?.primary == 512 && initial[.memory]?.capacity == 1024, "Memory capacity was not preserved")
        source.set(.cpu, .success(.cpu(ticks)))
        source.set(.network, .success(.counters(steadyAfter)))
        source.set(.disk, .success(.counters(steadyAfter)))
        let next = await sampler.sample(enabled: Set(Metric.allCases), at: 13)
        try expect(next[.cpu]?.primary == 40 && next[.network]?.primary == 200 && next[.disk]?.secondary == 100,
                   "Collector readings were not connected to real counter deltas")
        _ = await sampler.sample(enabled: [], at: 14)
        let resumed = await sampler.sample(enabled: [.network], at: 20)
        try expect(resumed[.network]?.state == .measuring, "Re-enabling a collector reused a disabled baseline")
        try expect(source.count(.gpu) == 2 && source.count(.memory) == 2, "A disabled collector kept sampling")
        source.set(.network, .failure(SamplingError(message: "Permission denied")))
        let failed = await sampler.sample(enabled: [.network], at: 21)
        try expect(failed[.network]?.state == .unavailable("Permission denied"), "Unavailable counters were presented as zero")
        source.set(.network, .success(.counters(after)))
        let recovered = await sampler.sample(enabled: [.network], at: 22)
        try expect(recovered[.network]?.state == .measuring, "Failure recovery reused a stale baseline")
        source.set(.gpu, .success(.percentage(.nan)))
        let invalidGPU = await sampler.sample(enabled: [.gpu])
        try expect(invalidGPU[.gpu]?.state != .available, "Invalid GPU percentage accepted")
        source.set(.swap, .success(.capacity(used: 1, total: 0)))
        let invalidSwap = await sampler.sample(enabled: [.swap])
        try expect(invalidSwap[.swap]?.state != .available, "Invalid swap capacity accepted")
        let reconfigured = await sampler.sample(enabled: [.network], at: 30, configuration: 2)
        try expect(reconfigured[.network]?.state == .measuring, "Rapid reconfiguration reused a stale baseline")
        let calls = source.count(.network)
        let stale = await sampler.sample(enabled: [.network], at: 31, configuration: 1)
        try expect(stale.isEmpty && source.count(.network) == calls, "A cancelled old configuration kept collecting")
        print("PASS sampler: all six metrics, zero readings, disabled collectors, warmup, failure, and recovery")

        var history = MetricHistory()
        for _ in 0..<1000 { history.append(MetricReading(state: .available, primary: 25), for: .cpu) }
        try expect(history.points.count == MetricHistory.limit && history.points.compactMap { $0 }.last?.primary == 0.25, "History must be bounded and normalized")
        history.append(.unavailable("Read failed"), for: .cpu)
        try expect(history.points.count == MetricHistory.limit && history.points.last! == nil, "Missing readings must leave graph gaps")
        try expect(MetricReading.bytes(1024) == "1.0 KiB", "Binary units are incorrect")
        print("PASS history: 60-sample cap, normalization, missing-data gaps, and binary units")

        let slow = CounterFixture()
        slow.delay = 0.25
        slow.set(.gpu, .success(.percentage(25)))
        let slowSampler = SystemSampler(source: slow)
        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                heartbeats += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        _ = await slowSampler.sample(enabled: [.gpu])
        heartbeat.cancel()
        try expect(heartbeats >= 5, "Native collection blocked the main actor")
        print("PASS responsiveness: slow collection runs off the main actor")

        let liveSampler = SystemSampler()
        _ = await liveSampler.sample(enabled: Set(Metric.allCases))
        try await Task.sleep(for: .milliseconds(300))
        let live = await liveSampler.sample(enabled: Set(Metric.allCases))
        for metric in Metric.allCases {
            let reading = live[metric]!
            if metric == .gpu, case .unavailable(let reason) = reading.state {
                print("LIVE GPU: unavailable on this driver (\(reason))")
                continue
            }
            try expect(reading.state == .available, "Live \(metric.title) failed: \(reading.lines(for: metric))")
            try expect(reading.primary.isFinite && reading.primary >= 0 && reading.secondary.isFinite && reading.secondary >= 0,
                       "Invalid live \(metric.title) reading")
            print("LIVE \(metric.title): \(reading.lines(for: metric).joined(separator: "; "))")
        }
        print("Passed collector logic, native smoke, and off-main-thread responsiveness checks.")
    }
}
