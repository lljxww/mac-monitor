#if DEBUG
import AppKit
import Foundation
import MonitorCore

/// Development-only checks and captures of this app's own content view.
/// No accessibility, screen recording, or input automation permissions are needed.
@MainActor
enum UIDiagnostics {
    static func run(store: MonitorStore, controller: StatusItemController, domain: String) async -> Bool {
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let args = ProcessInfo.processInfo.arguments
        let directory: URL
        if let index = args.firstIndex(of: "--ui-self-test"), args.count > index + 1 {
            directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacMonitor-UI")
        }
        var checks: [String: Bool] = [:]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await Task.sleep(for: .milliseconds(500))
            controller.showPopover()
            try await Task.sleep(for: .seconds(2.5))
            checks["accessoryActivationPolicy"] = NSApp.activationPolicy() == .accessory
            checks["allMetricsVisibleByDefault"] = store.preferences.orderedMetrics == Metric.allCases
            checks["cpuProcessSampling"] = store.snapshot.cpuProcessState == .available
            checks["memoryProcessSampling"] = store.snapshot.processes.contains { ($0.memoryBytes ?? 0) > 0 }
            checks["gpuProcessSampling"] = store.snapshot.gpuProcessState == .available
            let sampledProcessCount = store.snapshot.processes.count
            checks["noTextInputInOverview"] = noTextInputs(NSApp.windows.flatMap { $0.contentView.map { [$0] } ?? [] })
            let firstState = controller.diagnosticState
            checks["popoverIsShown"] = firstState["popoverShown"] as? Bool == true
            checks["noMainWindow"] = firstState["isMainWindow"] as? Bool == false
            checks["applicationHasNoMainWindow"] = NSApp.mainWindow == nil
            checks["noAutomaticControlFocus"] = ["none", "NSPopoverWindow", "NSPanel", "_NSPopoverWindow"].contains(firstState["focusedResponder"] as? String ?? "")
            try controller.savePopoverImage(to: directory.appendingPathComponent("overview.png"))
            try controller.saveStatusItemImage(to: directory.appendingPathComponent("menu-bars.png"))
            for metric in Metric.allCases {
                let previousDate = store.snapshot.date
                store.route = .processes(metric)
                try await waitFor {
                    store.snapshot.date > previousDate && !store.snapshot.rankedProcesses(for: metric).compactMap { $0.value(for: metric) }.isEmpty
                }
                try controller.savePopoverImage(to: directory.appendingPathComponent("processes-\(metric.rawValue).png"))
                let values = store.snapshot.rankedProcesses(for: metric).compactMap { $0.value(for: metric) }
                checks["\(metric.rawValue)FullListSorted"] = !values.isEmpty && values == values.sorted(by: >)
                if metric == .gpu {
                    checks["gpuPageSkipsCPUAndMemory"] = store.snapshot.processes.allSatisfy { $0.cpuPercent == nil && $0.memoryBytes == nil }
                }
            }
            store.route = .settings
            try await waitFor { store.latestSnapshot.processes.isEmpty }
            checks["settingsStopsProcessEnumeration"] = store.latestSnapshot.processes.isEmpty
            try controller.savePopoverImage(to: directory.appendingPathComponent("settings.png"))
            checks["noTextInputInSettings"] = noTextInputs(NSApp.windows.flatMap { $0.contentView.map { [$0] } ?? [] })
            store.preferences.setVisible(.gpu, visible: false)
            checks["hiddenMetricRemoved"] = !store.preferences.orderedMetrics.contains(.gpu)
            checks["settingsPersist"] = MonitorPreferences(defaults: UserDefaults(suiteName: domain)!).visibleMetrics == [.cpu, .memory]
            store.preferences.setVisible(.memory, visible: false)
            store.preferences.setVisible(.cpu, visible: false)
            checks["lastMetricStaysVisible"] = store.preferences.orderedMetrics == [.cpu]
            store.preferences.setVisible(.gpu, visible: true)
            store.preferences.setVisible(.memory, visible: true)
            store.preferences.setShowPercentages(true)
            checks["optionalPercentages"] = store.preferences.showPercentages
            store.preferences.setShowPercentages(false)
            store.route = .overview
            try await waitFor { store.snapshot.cpuProcessState == .available && store.snapshot.gpuProcessState == .available }
            try controller.savePopoverImage(to: directory.appendingPathComponent("overview-final.png"))
            controller.setDiagnosticAppearance(.darkAqua)
            try await Task.sleep(for: .milliseconds(200))
            try controller.savePopoverImage(to: directory.appendingPathComponent("overview-dark.png"))
            store.route = .settings
            try await Task.sleep(for: .milliseconds(200))
            try controller.savePopoverImage(to: directory.appendingPathComponent("settings-dark.png"))
            controller.setDiagnosticAppearance(nil)
            controller.close()
            try await Task.sleep(for: .milliseconds(500))
            checks["closingStopsProcessEnumeration"] = !store.isPresented && store.snapshot.processes.isEmpty
            let report: [String: Any] = ["checks": checks, "popover": firstState,
                                         "sampledProcessCount": sampledProcessCount,
                                         "processCountAfterClose": store.snapshot.processes.count,
                                         "allPassed": checks.values.allSatisfy { $0 }]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("ui-report.json"))
            print(String(decoding: data, as: UTF8.self))
            return checks.values.allSatisfy { $0 }
        } catch {
            print("UI diagnostics failed: \(error)")
            return false
        }
    }

    private static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func noTextInputs(_ views: [NSView]) -> Bool {
        views.allSatisfy { view in
            if let field = view as? NSTextField, field.isEditable { return false }
            if let text = view as? NSTextView, text.isEditable { return false }
            return noTextInputs(view.subviews)
        }
    }
}
#endif
