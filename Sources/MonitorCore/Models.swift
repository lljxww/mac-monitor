import Foundation

public enum Metric: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpu, gpu, memory
    public var id: Self { self }
    public var title: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "内存" }
    }
}

public enum SampleState: String, Sendable, Codable {
    case warmingUp, available, unavailable
}

public struct ProcessUsage: Identifiable, Sendable {
    public let pid: Int32
    public let startTime: UInt64
    public let name: String
    public let executablePath: String?
    public let cpuPercent: Double?
    public let gpuPercent: Double?
    public let memoryBytes: UInt64?
    public let memoryIsResidentFallback: Bool
    // A reused PID must not inherit the previous process' row or icon.
    public var id: String { "\(pid):\(startTime)" }

    public init(pid: Int32, startTime: UInt64 = 0, name: String, executablePath: String? = nil,
                cpuPercent: Double?, gpuPercent: Double?, memoryBytes: UInt64?, memoryIsResidentFallback: Bool = false) {
        self.pid = pid
        self.startTime = startTime
        self.name = name
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.gpuPercent = gpuPercent
        self.memoryBytes = memoryBytes
        self.memoryIsResidentFallback = memoryIsResidentFallback
    }

    public func value(for metric: Metric) -> Double? {
        switch metric {
        case .cpu: cpuPercent
        case .gpu: gpuPercent
        case .memory: memoryBytes.map { Double($0) }
        }
    }
}

public struct MemoryUsage: Sendable {
    public let total: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public var used: UInt64 { min(total, app + wired + compressed) }
    public var available: UInt64 { total - used }
    public var percent: Double { total == 0 ? 0 : Double(used) / Double(total) * 100 }

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
    }
}

public struct SystemSnapshot: Sendable {
    public let date: Date
    public let cpuPercent: Double?
    public let gpuPercent: Double?
    public let memory: MemoryUsage?
    public let processes: [ProcessUsage]
    public let cpuProcessState: SampleState
    public let gpuProcessState: SampleState
    public let unreadableProcesses: Int
    public let chipName: String
    public let coreCount: Int
    private let rankings: [Metric: [ProcessUsage]]

    public init(date: Date = .now, cpuPercent: Double? = nil, gpuPercent: Double? = nil,
                memory: MemoryUsage? = nil, processes: [ProcessUsage] = [],
                cpuProcessState: SampleState = .warmingUp, gpuProcessState: SampleState = .warmingUp,
                unreadableProcesses: Int = 0, chipName: String = "Apple Silicon", coreCount: Int = 1) {
        self.date = date
        self.cpuPercent = cpuPercent
        self.gpuPercent = gpuPercent
        self.memory = memory
        self.processes = processes
        self.cpuProcessState = cpuProcessState
        self.gpuProcessState = gpuProcessState
        self.unreadableProcesses = unreadableProcesses
        self.chipName = chipName
        self.coreCount = coreCount
        // Computed once on the sampling actor. SwiftUI reads share these arrays
        // through copy-on-write instead of sorting on every body evaluation.
        rankings = Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
            (metric, Self.rank(processes, for: metric))
        })
    }

    public func percent(for metric: Metric) -> Double? {
        switch metric { case .cpu: cpuPercent; case .gpu: gpuPercent; case .memory: memory?.percent }
    }

    public func rankedProcesses(for metric: Metric) -> [ProcessUsage] {
        rankings[metric] ?? []
    }

    private static func rank(_ processes: [ProcessUsage], for metric: Metric) -> [ProcessUsage] {
        // GPU lists only clients the driver actually exposes. An absent counter is not 0%.
        // Sort compact keys instead of repeatedly moving process structs and
        // converting memory values inside an O(n log n) comparator.
        var keys: [(index: Int, pid: Int32, value: Double)] = []
        keys.reserveCapacity(processes.count)
        for (index, process) in processes.enumerated() {
            let value = process.value(for: metric)
            if metric == .gpu && value == nil { continue }
            keys.append((index, process.pid, value ?? -1))
        }
        keys.sort { $0.value == $1.value ? $0.pid < $1.pid : $0.value > $1.value }
        return keys.map { processes[$0.index] }
    }

    public var historyPoint: SystemHistoryPoint {
        SystemHistoryPoint(date: date, cpuPercent: cpuPercent, gpuPercent: gpuPercent, memoryPercent: memory?.percent)
    }

    public var systemOnly: SystemSnapshot {
        SystemSnapshot(date: date, cpuPercent: cpuPercent, gpuPercent: gpuPercent,
                       memory: memory, chipName: chipName, coreCount: coreCount)
    }
}

/// Bounded chart history must never retain process arrays or executable paths.
public struct SystemHistoryPoint: Sendable {
    public let date: Date
    public let cpuPercent: Double?
    public let gpuPercent: Double?
    public let memoryPercent: Double?

    public func percent(for metric: Metric) -> Double? {
        switch metric { case .cpu: cpuPercent; case .gpu: gpuPercent; case .memory: memoryPercent }
    }
}
