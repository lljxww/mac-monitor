import Foundation

public struct CPUCounters: Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    public func utilization(since previous: CPUCounters) -> Double? {
        // HOST_CPU_LOAD_INFO uses wrapping 32-bit tick counters.
        func delta(_ current: UInt64, _ old: UInt64) -> UInt64 {
            UInt64(UInt32(truncatingIfNeeded: current) &- UInt32(truncatingIfNeeded: old))
        }
        let busy = delta(user, previous.user) + delta(system, previous.system) + delta(nice, previous.nice)
        let total = busy + delta(idle, previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }
}

public struct ProcessCounter: Sendable {
    public let startTime: UInt64
    public let cpuNanoseconds: UInt64
    public init(startTime: UInt64, cpuNanoseconds: UInt64) {
        self.startTime = startTime; self.cpuNanoseconds = cpuNanoseconds
    }

    public func percent(since previous: ProcessCounter?, elapsed: Double) -> Double? {
        guard let previous, elapsed > 0,
              startTime == previous.startTime, cpuNanoseconds >= previous.cpuNanoseconds else { return nil }
        return Double(cpuNanoseconds - previous.cpuNanoseconds) / (elapsed * 1_000_000_000) * 100
    }
}

public struct GPUClientCounter: Sendable {
    public let entryID: UInt64
    public let pid: Int32
    public let nanoseconds: UInt64
    public init(entryID: UInt64, pid: Int32, nanoseconds: UInt64) {
        self.entryID = entryID; self.pid = pid; self.nanoseconds = nanoseconds
    }
}

public enum GPUCounterMath {
    public static func percentages(current: [GPUClientCounter], previous: [UInt64: GPUClientCounter],
                                   elapsed: Double) -> [Int32: Double] {
        guard elapsed > 0 else { return [:] }
        var result: [Int32: Double] = [:]
        for client in current {
            guard let old = previous[client.entryID], old.pid == client.pid,
                  client.nanoseconds >= old.nanoseconds else { continue }
            // Difference individual clients before aggregating: a closed client must not
            // subtract its lifetime GPU time from other surviving clients of the same PID.
            result[client.pid, default: 0] += Double(client.nanoseconds - old.nanoseconds)
                / (elapsed * 1_000_000_000) * 100
        }
        return result
    }

    public static func creatorPID(_ creator: String) -> Int32? {
        guard creator.hasPrefix("pid "), let comma = creator.firstIndex(of: ",") else { return nil }
        return Int32(creator[creator.index(creator.startIndex, offsetBy: 4)..<comma])
    }
}
