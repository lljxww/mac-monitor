import Darwin
import Foundation
import IOKit

/// All kernel/driver queries run on this actor, outside the main UI actor.
public actor SystemSampler {
    private var previousCPU: CPUCounters?
    private var previousProcesses: [Int32: ProcessCounter] = [:]
    private var previousProcessTime: TimeInterval?
    private var previousGPU: [UInt64: GPUClientCounter] = [:]
    private var previousGPUTime: TimeInterval?
    private var metadata: [Int32: Metadata] = [:]
    private var deniedProcesses: [Int32: (identity: UInt64, retryAt: TimeInterval)] = [:]
    private var accelerators: [io_registry_entry_t] = []
    private var gpuOwners: [UInt64: Int32] = [:]
    private var lastGPUDiscovery: TimeInterval = -.infinity
    private let coreCount = ProcessInfo.processInfo.activeProcessorCount
    private let totalMemory = ProcessInfo.processInfo.physicalMemory
    private let chipName: String
    private let timebaseNumerator: UInt64
    private let timebaseDenominator: UInt64
    private let host = mach_host_self()
    private let pageSize: UInt64

    public init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        timebaseNumerator = UInt64(timebase.numer)
        timebaseDenominator = UInt64(max(1, timebase.denom))
        var sizeInBytes: vm_size_t = 0
        host_page_size(host, &sizeInBytes)
        pageSize = UInt64(sizeInBytes)
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        if sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 {
            chipName = Self.decodeCString(bytes)
        } else {
            chipName = "Apple Silicon"
        }
    }

    deinit {
        accelerators.forEach { IOObjectRelease($0) }
        mach_port_deallocate(mach_task_self_, host)
    }

    public func sample(includeProcesses: Bool) -> SystemSnapshot {
        sample(systemMetrics: Set(Metric.allCases), processMetrics: includeProcesses ? Set(Metric.allCases) : [])
    }

    public func sample(systemMetrics: Set<Metric>, processMetrics: Set<Metric>) -> SystemSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let needsCPU = processMetrics.contains(.cpu)
        let needsMemory = processMetrics.contains(.memory)
        let needsGPU = processMetrics.contains(.gpu)
        let cpu = systemMetrics.contains(.cpu) ? readCPU() : nil
        let cpuPercent = cpu.flatMap { value in previousCPU.flatMap { value.utilization(since: $0) } }
        previousCPU = cpu
        let gpu = systemMetrics.contains(.gpu) || needsGPU ? readGPU(includeProcesses: needsGPU) : GPUReading()
        var processes: [ProcessUsage] = []
        var cpuState: SampleState = .warmingUp
        var gpuState: SampleState = .warmingUp
        var unreadable = 0

        if !processMetrics.isEmpty {
            let elapsed = previousProcessTime.map { now - $0 } ?? 0
            let gpuElapsed = previousGPUTime.map { now - $0 } ?? 0
            let gpuValues = GPUCounterMath.percentages(current: gpu.clients, previous: previousGPU, elapsed: gpuElapsed)
            let gpuPIDs = Set(gpu.clients.map(\.pid))
            var nextCounters: [Int32: ProcessCounter] = [:]
            let identities = readProcessIdentities()
            let pids = needsCPU || needsMemory ? Set(identities.keys).union(gpuPIDs) : gpuPIDs
            var protectedPIDs: [Int32] = []
            var rawUsage: [Int32: rusage_info_v2] = [:]
            for pid in pids where pid > 0 && (needsCPU || needsMemory) {
                if let denied = deniedProcesses[pid], denied.identity == identities[pid], denied.retryAt > now {
                    protectedPIDs.append(pid)
                    continue
                }
                var usage = rusage_info_v2()
                let result = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                    }
                }
                let processError = result == 0 ? 0 : errno
                if result == 0 {
                    rawUsage[pid] = usage
                    deniedProcesses[pid] = nil
                } else {
                    protectedPIDs.append(pid)
                    if (processError == EPERM || processError == EACCES), let identity = identities[pid], identity > 0 {
                        deniedProcesses[pid] = (identity, now + 30)
                    }
                }
            }
            let protectedStats = ProtectedProcessStats.read(pids: protectedPIDs)
            for pid in pids where pid > 0 {
                var cpuValue: Double?
                var memoryBytes: UInt64?
                var residentFallback = false
                let usage = rawUsage[pid]
                let startTime = identities[pid].flatMap { $0 > 0 ? $0 : nil } ?? usage?.ri_proc_start_abstime ?? 0
                if let usage {
                    let counter = ProcessCounter(startTime: startTime,
                                                 cpuNanoseconds: nanoseconds(usage.ri_user_time + usage.ri_system_time))
                    if needsCPU {
                        cpuValue = counter.percent(since: previousProcesses[pid], elapsed: elapsed)
                        nextCounters[pid] = counter
                    }
                    if needsMemory { memoryBytes = usage.ri_phys_footprint }
                } else if let fallback = protectedStats[pid] {
                    let counter = ProcessCounter(startTime: startTime, cpuNanoseconds: fallback.cpuNanoseconds)
                    if needsCPU {
                        cpuValue = counter.percent(since: previousProcesses[pid], elapsed: elapsed)
                        nextCounters[pid] = counter
                    }
                    if needsMemory {
                        memoryBytes = fallback.residentBytes
                        residentFallback = true
                    }
                } else if needsCPU || needsMemory {
                    unreadable += 1
                }
                let info = processMetadata(pid: pid, startTime: startTime)
                processes.append(ProcessUsage(pid: pid, startTime: startTime, name: info.name,
                                              executablePath: info.path, cpuPercent: cpuValue,
                                              gpuPercent: gpuValues[pid], memoryBytes: memoryBytes,
                                              memoryIsResidentFallback: residentFallback))
            }
            cpuState = elapsed > 0 ? (nextCounters.isEmpty ? .unavailable : .available) : .warmingUp
            gpuState = gpu.hasUsageCounters ? (previousGPUTime == nil ? .warmingUp : .available) : .unavailable
            previousProcesses = nextCounters
            previousProcessTime = needsCPU ? now : nil
            previousGPU = Dictionary(gpu.clients.map { ($0.entryID, $0) }, uniquingKeysWith: { _, new in new })
            previousGPUTime = needsGPU ? now : nil
            metadata = metadata.filter { identities[$0.key] != nil }
            deniedProcesses = deniedProcesses.filter { identities[$0.key] == $0.value.identity }
        } else {
            // Do not spend energy enumerating processes while the popover is closed.
            previousProcesses.removeAll(keepingCapacity: true)
            previousProcessTime = nil
            previousGPU.removeAll(keepingCapacity: true)
            previousGPUTime = nil
        }
        return SystemSnapshot(cpuPercent: cpuPercent, gpuPercent: gpu.percent,
                              memory: systemMetrics.contains(.memory) ? readMemory() : nil,
                              processes: processes, cpuProcessState: cpuState, gpuProcessState: gpuState,
                              unreadableProcesses: unreadable, chipName: chipName, coreCount: coreCount)
    }

    private func readCPU() -> CPUCounters? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUCounters(user: UInt64(ticks.0), system: UInt64(ticks.1),
                           idle: UInt64(ticks.2), nice: UInt64(ticks.3))
    }

    private func readMemory() -> MemoryUsage? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        guard pageSize > 0 else { return nil }
        let appPages = UInt64(info.internal_page_count) > UInt64(info.purgeable_count)
            ? UInt64(info.internal_page_count) - UInt64(info.purgeable_count) : 0
        return MemoryUsage(total: totalMemory, app: appPages * UInt64(pageSize),
                           wired: UInt64(info.wire_count) * UInt64(pageSize),
                           compressed: UInt64(info.compressor_page_count) * UInt64(pageSize))
    }

    private func readProcessIdentities() -> [Int32: UInt64] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        if sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 {
            // The process table can grow while it is being read. Retry with spare capacity.
            for _ in 0..<3 {
                var records = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 128)
                var capacity = records.count * MemoryLayout<kinfo_proc>.stride
                let result = records.withUnsafeMutableBytes {
                    sysctl(&mib, UInt32(mib.count), $0.baseAddress, &capacity, nil, 0)
                }
                if result == 0 {
                    var identities: [Int32: UInt64] = [:]
                    for record in records.prefix(capacity / MemoryLayout<kinfo_proc>.stride) {
                        let start = record.kp_proc.p_un.__p_starttime
                        identities[record.kp_proc.p_pid] = UInt64(max(0, start.tv_sec)) * 1_000_000 + UInt64(max(0, start.tv_usec))
                    }
                    return identities
                }
                size = max(capacity, size * 2)
            }
        }
        // Keep basic enumeration usable even if sysctl is restricted in a future OS.
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }
        // Allow for processes created between the size query and the actual read.
        var pids = [Int32](repeating: 0, count: Int(count) + 256)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { return [:] }
        return Dictionary(pids.prefix(min(Int(actual), pids.count)).map { ($0, UInt64(0)) }, uniquingKeysWith: { _, new in new })
    }

    private struct Metadata {
        let startTime: UInt64
        let name: String
        let path: String?
    }

    private func processMetadata(pid: Int32, startTime: UInt64) -> Metadata {
        if let cached = metadata[pid], cached.startTime == startTime { return cached }
        var pathBytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBytes, UInt32(pathBytes.count))
        let path = pathLength > 0 ? Self.decodeCString(pathBytes) : nil
        var nameBytes = [CChar](repeating: 0, count: 256)
        let nameLength = proc_name(pid, &nameBytes, UInt32(nameBytes.count))
        let shortName = nameLength > 0 ? Self.decodeCString(nameBytes) : "进程 \(pid)"
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? shortName
        let info = Metadata(startTime: startTime, name: name, path: path)
        metadata[pid] = info
        return info
    }

    private static func decodeCString(_ bytes: [CChar]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func nanoseconds(_ absoluteTime: UInt64) -> UInt64 {
        // rusage CPU times use Mach absolute ticks on Apple Silicon (24 MHz on M2),
        // whereas AGX accumulatedGPUTime is already expressed in nanoseconds.
        // Divide before multiplying to avoid overflow on long-lived processes.
        (absoluteTime / timebaseDenominator) * timebaseNumerator
            + (absoluteTime % timebaseDenominator) * timebaseNumerator / timebaseDenominator
    }

    private struct GPUReading {
        var percent: Double?
        var clients: [GPUClientCounter] = []
        var hasUsageCounters = false
    }

    private func readGPU(includeProcesses: Bool) -> GPUReading {
        var reading = GPUReading()
        let now = ProcessInfo.processInfo.systemUptime
        if accelerators.isEmpty && now - lastGPUDiscovery >= 30 {
            lastGPUDiscovery = now
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
                while case let entry = IOIteratorNext(iterator), entry != 0 { accelerators.append(entry) }
                IOObjectRelease(iterator)
            }
        }
        var liveClients: Set<UInt64> = []
        for accelerator in accelerators {
            if let stats = IORegistryEntryCreateCFProperty(accelerator, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let utilization = stats["Device Utilization %"] as? NSNumber {
                reading.percent = max(reading.percent ?? 0, min(100, max(0, utilization.doubleValue)))
            }
            guard includeProcesses else { continue }
            var children: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(accelerator, kIOServicePlane,
                                                IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(child, &id) == KERN_SUCCESS else { continue }
                liveClients.insert(id)
                var pid = gpuOwners[id]
                if pid == nil, let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString,
                                                                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                    pid = GPUCounterMath.creatorPID(creator)
                }
                var usage = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]]
                if pid == nil || usage == nil {
                    // Older drivers may expose these keys only during serialization.
                    var properties: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let values = properties?.takeRetainedValue() as? [String: Any] {
                        if let creator = values["IOUserClientCreator"] as? String { pid = GPUCounterMath.creatorPID(creator) }
                        usage = values["AppUsage"] as? [[String: Any]]
                    }
                }
                guard let pid, let usage else { continue }
                gpuOwners[id] = pid
                var total: UInt64 = 0
                var hasTime = false
                for queue in usage {
                    if let time = queue["accumulatedGPUTime"] as? NSNumber {
                        total += time.uint64Value
                        hasTime = true
                    }
                }
                guard hasTime else { continue }
                reading.hasUsageCounters = true
                reading.clients.append(GPUClientCounter(entryID: id, pid: pid, nanoseconds: total))
            }
        }
        if includeProcesses { gpuOwners = gpuOwners.filter { liveClients.contains($0.key) } }
        if reading.percent == nil && !accelerators.isEmpty {
            // A sleep/wake or driver reset can invalidate retained registry handles.
            accelerators.forEach { IOObjectRelease($0) }
            accelerators.removeAll()
            lastGPUDiscovery = -.infinity
        }
        return reading
    }
}
