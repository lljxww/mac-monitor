import Darwin
import Foundation
import MonitorCore

enum Benchmark {
    static func run() async throws {
        let arguments = CommandLine.arguments
        let count = arguments.firstIndex(of: "--samples").flatMap { index in
            arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
        } ?? 50
        guard (10...1_000).contains(count) else { throw BenchmarkError.invalidSampleCount }
        var report: [String: Any] = ["samplesPerMode": count, "hardware": ProcessInfo.processInfo.processorCount]
        let all = Set(Metric.allCases)
        let modes: [(name: String, system: Set<Metric>, processes: Set<Metric>)] = [
            ("menuBar", all, []), ("popover", all, all), ("gpuOnly", [.gpu], [.gpu])
        ]
        for mode in modes {
            let sampler = SystemSampler()
            for _ in 0..<3 { _ = await sampler.sample(systemMetrics: mode.system, processMetrics: mode.processes) }
            var durations: [Double] = []
            var rankingDurations: [Double] = []
            var processCount = 0
            let selfBefore = cpuTime(RUSAGE_SELF)
            let childBefore = cpuTime(RUSAGE_CHILDREN)
            for _ in 0..<count {
                let start = ProcessInfo.processInfo.systemUptime
                let snapshot = await sampler.sample(systemMetrics: mode.system, processMetrics: mode.processes)
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                processCount = snapshot.processes.count
                let rankStart = ProcessInfo.processInfo.systemUptime
                // Repeated accesses model SwiftUI body evaluation of the same snapshot.
                for _ in 0..<6 {
                    for metric in Metric.allCases {
                        consume(snapshot.rankedProcesses(for: metric))
                    }
                }
                rankingDurations.append((ProcessInfo.processInfo.systemUptime - rankStart) * 1_000)
                try await Task.sleep(for: .milliseconds(50))
            }
            let selfCPU = (cpuTime(RUSAGE_SELF) - selfBefore) * 1_000 / Double(count)
            let childCPU = (cpuTime(RUSAGE_CHILDREN) - childBefore) * 1_000 / Double(count)
            report[mode.name] = [
                "sampleP50Ms": percentile(durations, 0.5),
                "sampleP95Ms": percentile(durations, 0.95),
                "rankingP50Ms": percentile(rankingDurations, 0.5),
                "selfCPUPerSampleMs": selfCPU,
                "childCPUPerSampleMs": childCPU,
                "processCount": processCount
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    // Keep benchmark work visible to the optimizer without logging process information.
    nonisolated(unsafe) private static var sink = 0
    @inline(never) private static func consume(_ processes: [ProcessUsage]) { sink &+= processes.count }

    private static func cpuTime(_ who: Int32) -> Double {
        var usage = rusage()
        getrusage(who, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        values.sorted()[min(values.count - 1, Int(Double(values.count - 1) * fraction))]
    }

    enum BenchmarkError: Error { case invalidSampleCount }
}
