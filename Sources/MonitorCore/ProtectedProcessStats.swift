import Foundation

/// The system ps executable can obtain basic statistics for protected processes
/// that libproc denies to ordinary applications. It runs without a shell or sudo.
enum ProtectedProcessStats {
    struct Entry {
        let cpuNanoseconds: UInt64
        let residentBytes: UInt64
    }

    static func read(pids: [Int32]) -> [Int32: Entry] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", pids.map(String.init).joined(separator: ","), "-o", "pid=,time=,rss="]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        // Drain before waiting: full process output can exceed the pipe's capacity.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ output: String) -> [Int32: Entry] {
        var result: [Int32: Entry] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]),
                  let cpu = cpuNanoseconds(String(fields[1])), let rssKB = UInt64(fields[2]) else { continue }
            result[pid] = Entry(cpuNanoseconds: cpu, residentBytes: rssKB * 1_024)
        }
        return result
    }

    static func cpuNanoseconds(_ time: String) -> UInt64? {
        // macOS emits minutes:seconds.centiseconds, including minutes above 59.
        // Accept day/hour forms as well for compatibility with future ps versions.
        let dayParts = time.split(separator: "-")
        guard dayParts.count <= 2, let clock = dayParts.last else { return nil }
        let days = dayParts.count == 2 ? UInt64(dayParts[0]) : 0
        guard let days else { return nil }
        let parts = clock.split(separator: ":")
        guard (2...3).contains(parts.count), let seconds = Double(parts.last!),
              seconds.isFinite, seconds >= 0, seconds < 60,
              let minutes = UInt64(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? UInt64(parts[0]) : 0
        guard let hours else { return nil }
        let total = Double(days) * 86_400 + Double(hours) * 3_600 + Double(minutes) * 60 + seconds
        guard total < Double(UInt64.max) / 1_000_000_000 else { return nil }
        return UInt64((total * 1_000_000_000).rounded())
    }
}
