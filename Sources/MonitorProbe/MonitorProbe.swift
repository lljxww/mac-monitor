import Foundation
import MonitorCore

/// Read-only sampling diagnostics; uses exactly the same sampler as the app.
@main
enum MonitorProbe {
    static func main() async throws {
        if CommandLine.arguments.contains("--benchmark") {
            try await Benchmark.run()
            return
        }
        let sampler = SystemSampler()
        _ = await sampler.sample(includeProcesses: true)
        try await Task.sleep(for: .seconds(1))
        let snapshot = await sampler.sample(includeProcesses: true)
        var output: [String: Any] = [
            "chip": snapshot.chipName,
            "cores": snapshot.coreCount,
            "processCount": snapshot.processes.count,
            "unreadableProcesses": snapshot.unreadableProcesses,
            "cpuProcessState": snapshot.cpuProcessState.rawValue,
            "gpuProcessState": snapshot.gpuProcessState.rawValue
        ]
        output["cpuPercent"] = snapshot.cpuPercent
        output["gpuPercent"] = snapshot.gpuPercent
        output["memoryPercent"] = snapshot.memory?.percent
        output["memoryUsedBytes"] = snapshot.memory?.used
        for metric in Metric.allCases {
            output["\(metric.rawValue)Top5"] = snapshot.rankedProcesses(for: metric).prefix(5).map { process in
                var row: [String: Any] = ["pid": process.pid, "name": process.name]
                row["value"] = process.value(for: metric)
                return row
            }
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        guard snapshot.cpuPercent != nil, snapshot.memory != nil, !snapshot.processes.isEmpty else {
            throw ProbeError.missingSystemData
        }
    }
    enum ProbeError: Error { case missingSystemData }
}
