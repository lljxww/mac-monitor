import Foundation
import Testing
@testable import MonitorCore

@Test func cpuUsesTickDeltasAndHandlesCounterWrap() {
    let before = CPUCounters(user: UInt64(UInt32.max) - 4, system: 10, idle: 100, nice: 0)
    let after = CPUCounters(user: 5, system: 20, idle: 180, nice: 0)
    #expect(after.utilization(since: before) == 20)
    #expect(after.utilization(since: after) == nil)
}

@Test func processCPUAllowsMultipleCores() {
    let old = ProcessCounter(startTime: 12, cpuNanoseconds: 1_000_000_000)
    let new = ProcessCounter(startTime: 12, cpuNanoseconds: 6_000_000_000)
    #expect(new.percent(since: old, elapsed: 2) == 250)
}

@Test func processReplacementAndCounterResetNeedANewBaseline() {
    let old = ProcessCounter(startTime: 12, cpuNanoseconds: 5_000_000_000)
    #expect(ProcessCounter(startTime: 13, cpuNanoseconds: 6_000_000_000).percent(since: old, elapsed: 1) == nil)
    #expect(ProcessCounter(startTime: 12, cpuNanoseconds: 1).percent(since: old, elapsed: 1) == nil)
    #expect(old.percent(since: nil, elapsed: 1) == nil)
    #expect(old.percent(since: old, elapsed: 0) == nil)
}

@Test func closingAGPUClientDoesNotEraseAnotherClientsActivity() {
    let old = [
        UInt64(1): GPUClientCounter(entryID: 1, pid: 42, nanoseconds: 8_000_000_000),
        UInt64(2): GPUClientCounter(entryID: 2, pid: 42, nanoseconds: 1_000_000_000)
    ]
    let current = [GPUClientCounter(entryID: 2, pid: 42, nanoseconds: 1_500_000_000)]
    #expect(GPUCounterMath.percentages(current: current, previous: old, elapsed: 1)[42] == 50)
}

@Test func gpuAggregatesClientsAfterDifferencing() {
    let old = [UInt64(1): GPUClientCounter(entryID: 1, pid: 42, nanoseconds: 0),
               UInt64(2): GPUClientCounter(entryID: 2, pid: 42, nanoseconds: 0)]
    let current = [GPUClientCounter(entryID: 1, pid: 42, nanoseconds: 250_000_000),
                   GPUClientCounter(entryID: 2, pid: 42, nanoseconds: 500_000_000)]
    #expect(GPUCounterMath.percentages(current: current, previous: old, elapsed: 1)[42] == 75)
}

@Test func newGPUClientsCannotContributeTheirEntireLifetime() {
    let client = GPUClientCounter(entryID: 1, pid: 42, nanoseconds: 100_000_000_000)
    #expect(GPUCounterMath.percentages(current: [client], previous: [:], elapsed: 1).isEmpty)
    let old = [UInt64(1): GPUClientCounter(entryID: 1, pid: 99, nanoseconds: 1)]
    #expect(GPUCounterMath.percentages(current: [client], previous: old, elapsed: 1).isEmpty)
}

@Test func creatorParsingMatchesExactPID() {
    #expect(GPUCounterMath.creatorPID("pid 42, WindowServer") == 42)
    #expect(GPUCounterMath.creatorPID("pid 4242, Name With Spaces") == 4242)
    #expect(GPUCounterMath.creatorPID("something else") == nil)
    #expect(GPUCounterMath.creatorPID("pid nope, invalid") == nil)
}

@Test func unavailableCountersSortAfterMeasuredZero() {
    let snapshot = SystemSnapshot(processes: [
        ProcessUsage(pid: 1, name: "hidden", cpuPercent: nil, gpuPercent: nil, memoryBytes: nil),
        ProcessUsage(pid: 2, name: "idle", cpuPercent: 0, gpuPercent: 0, memoryBytes: 0),
        ProcessUsage(pid: 3, name: "busy", cpuPercent: 25, gpuPercent: 30, memoryBytes: 200)
    ])
    #expect(snapshot.rankedProcesses(for: .cpu).map(\.pid) == [3, 2, 1])
    #expect(snapshot.rankedProcesses(for: .memory).map(\.pid) == [3, 2, 1])
    #expect(snapshot.rankedProcesses(for: .gpu).map(\.pid) == [3, 2])
    #expect(snapshot.processes[2].value(for: .memory) == 200)
}

@Test func memoryNeverReportsNegativeAvailableOrMoreThan100Percent() {
    let memory = MemoryUsage(total: 1_000, app: 700, wired: 200, compressed: 300)
    #expect(memory.used == 1_000)
    #expect(memory.available == 0)
    #expect(memory.percent == 100)
    #expect(MemoryUsage(total: 0, app: 0, wired: 0, compressed: 0).percent == 0)
}

@Test func protectedProcessStatisticsParseCPUAndMemory() {
    let values = ProtectedProcessStats.parse(" 475 54:40.59 82928\n 1 2:51.33 22528\ninvalid line\n")
    #expect(values[475]?.cpuNanoseconds == 3_280_590_000_000)
    #expect(values[475]?.residentBytes == 84_918_272)
    #expect(values.count == 2)
    #expect(ProtectedProcessStats.cpuNanoseconds("1-02:03:04.50") == 93_784_500_000_000)
    #expect(ProtectedProcessStats.cpuNanoseconds("garbage") == nil)
    #expect(ProtectedProcessStats.cpuNanoseconds("0:nan") == nil)
}

@Test func historyAndSystemOnlySnapshotsDoNotRetainProcessData() {
    let date = Date()
    let snapshot = SystemSnapshot(date: date, cpuPercent: 12, gpuPercent: 34,
                                  memory: MemoryUsage(total: 100, app: 40, wired: 10, compressed: 5),
                                  processes: [ProcessUsage(pid: 42, name: "busy", cpuPercent: 5, gpuPercent: 6, memoryBytes: 7)])
    let point = snapshot.historyPoint
    #expect(point.date == date)
    #expect(point.percent(for: .cpu) == 12)
    #expect(point.percent(for: .gpu) == 34)
    #expect(abs((point.percent(for: .memory) ?? 0) - 55) < 0.000_001)
    #expect(snapshot.systemOnly.processes.isEmpty)
    #expect(snapshot.systemOnly.rankedProcesses(for: .cpu).isEmpty)
    #expect(snapshot.systemOnly.percent(for: .gpu) == 34)
}

@Test func rankingTieBreakersStayDeterministicAcrossRepeatedReads() {
    let snapshot = SystemSnapshot(processes: [
        ProcessUsage(pid: 9, name: "second", cpuPercent: 10, gpuPercent: 0, memoryBytes: 5),
        ProcessUsage(pid: 2, name: "first", cpuPercent: 10, gpuPercent: 0, memoryBytes: 5)
    ])
    for metric in Metric.allCases {
        #expect(snapshot.rankedProcesses(for: metric).map(\.pid) == [2, 9])
        #expect(snapshot.rankedProcesses(for: metric).map(\.pid) == [2, 9])
    }
}

@Test func excludedSystemMetricsAreNotReturned() async {
    let sampler = SystemSampler()
    let snapshot = await sampler.sample(systemMetrics: [.cpu], processMetrics: [])
    #expect(snapshot.gpuPercent == nil)
    #expect(snapshot.memory == nil)
    #expect(snapshot.processes.isEmpty)
}
