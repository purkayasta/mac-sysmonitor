import Darwin
import Foundation
import IOKit
import IOKit.storage

struct NativeSystemCounters: SystemCounterSource {
    func read(_ metric: Metric) -> Result<RawMetricSample, SamplingError> {
        switch metric {
        case .cpu: return cpu()
        case .gpu: return gpu()
        case .memory: return memory()
        case .swap: return swap()
        case .network: return network()
        case .disk: return disk()
        }
    }

    private func failure(_ reason: String) -> Result<RawMetricSample, SamplingError> { .failure(SamplingError(message: reason)) }

    private func cpu() -> Result<RawMetricSample, SamplingError> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return failure("CPU counters could not be read (\(result))") }
        return .success(.cpu(CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)))
    }

    private func memory() -> Result<RawMetricSample, SamplingError> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return failure("Memory counters could not be read (\(result))") }
        let pageSize = sysconf(_SC_PAGESIZE)
        guard pageSize > 0 else { return failure("Memory page size is unavailable") }
        // App memory plus wired and compressed pages; exclude reclaimable file
        // cache and purgeable pages rather than treating them as app memory.
        let occupied = UInt64(info.active_count) + UInt64(info.inactive_count) + UInt64(info.speculative_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let reclaimable = UInt64(info.external_page_count) + UInt64(info.purgeable_count)
        let pages = occupied > reclaimable ? occupied - reclaimable : 0
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return failure("Physical memory size is unavailable") }
        return .success(.capacity(used: min(total, pages * UInt64(pageSize)), total: total))
    }

    private func swap() -> Result<RawMetricSample, SamplingError> {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return failure("Swap counters could not be read (\(errno))") }
        return .success(.capacity(used: usage.xsu_used, total: usage.xsu_total))
    }

    private func gpu() -> Result<RawMetricSample, SamplingError> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return failure("GPU services could not be read")
        }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue,
               value.isFinite && (0...100).contains(value) { values.append(value) }
        }
        guard let usage = values.max() else { return failure("This GPU driver does not expose utilization counters") }
        return .success(.percentage(usage))
    }

    private func disk() -> Result<RawMetricSample, SamplingError> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass), &iterator) == KERN_SUCCESS else {
            return failure("Disk services could not be read")
        }
        defer { IOObjectRelease(iterator) }
        var counters: [String: ByteCounters] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var identity: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS,
                  let stats = IORegistryEntryCreateCFProperty(service, kIOBlockStorageDriverStatisticsKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let read = stats[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber,
                  let write = stats[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber else { continue }
            counters[String(identity)] = ByteCounters(incoming: read.uint64Value, outgoing: write.uint64Value)
        }
        guard !counters.isEmpty else { return failure("No disk byte counters are available") }
        return .success(.counters(counters))
    }

    private func network() -> Result<RawMetricSample, SamplingError> {
        // NET_RT_IFLIST2 provides 64-bit counters; getifaddrs' if_data counters
        // can wrap at 4 GiB and miss traffic on fast interfaces.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size <= 16 * 1024 * 1024 else { return failure("Network counters could not be sized (\(errno))") }
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard status == 0 else { return failure("Network counters could not be read (\(errno))") }
        var counters: [String: ByteCounters] = [:]
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4 && offset + length <= size else { break }
                let kind = buffer[offset + 3]
                defer { offset += length }
                guard kind == RTM_IFINFO2 && length >= MemoryLayout<if_msghdr2>.size else { continue }
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(header.ifm_index), &name) != nil else { continue }
                let interface = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                // Physical Ethernet/Wi-Fi interfaces avoid counting VPN, bridge,
                // AWDL, and loopback traffic twice.
                guard interface.hasPrefix("en"), header.ifm_flags & IFF_UP != 0 else { continue }
                counters[interface] = ByteCounters(incoming: header.ifm_data.ifi_ibytes, outgoing: header.ifm_data.ifi_obytes)
            }
        }
        return .success(.counters(counters))
    }
}
