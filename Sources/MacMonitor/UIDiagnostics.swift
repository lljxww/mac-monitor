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
            checks["defaultRingLayout"] = store.preferences.statusItemMetrics == [.memory, .cpu, .gpu]
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
            try controller.saveStatusItemImage(to: directory.appendingPathComponent("menu-rings.png"))
            try saveRingExamples(to: directory.appendingPathComponent("ring-states.png"))
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
            store.preferences.setMetric(.cpu, for: .outerRing)
            checks["assigningOccupiedMetricSwapsPositions"] = store.preferences.statusItemMetrics == [.cpu, .memory, .gpu]
            checks["layoutRedrawsImmediately"] = controller.diagnosticState["renderedStatusItemMetrics"] as? [String] == ["cpu", "memory", "gpu"]
            store.preferences.setMetric(.memory, for: .center)
            checks["centerMetricCanChange"] = store.preferences.statusItemMetrics == [.cpu, .gpu, .memory]
            try await Task.sleep(for: .milliseconds(200))
            try controller.savePopoverImage(to: directory.appendingPathComponent("settings-reassigned.png"))
            try controller.saveStatusItemImage(to: directory.appendingPathComponent("menu-rings-reassigned.png"))
            var permutationsPersist = true
            for outer in Metric.allCases {
                for inner in Metric.allCases where inner != outer {
                    store.preferences.setMetric(outer, for: .outerRing)
                    store.preferences.setMetric(inner, for: .innerRing)
                    let layout = store.preferences.statusItemMetrics
                    let restored = MonitorPreferences(defaults: UserDefaults(suiteName: domain)!)
                    permutationsPersist = permutationsPersist && layout[0] == outer && layout[1] == inner
                        && Set(layout) == Set(Metric.allCases) && restored.statusItemMetrics == layout
                }
            }
            checks["allSixLayoutsPersist"] = permutationsPersist
            let invalidDomain = domain + ".invalid-layout"
            let invalidDefaults = UserDefaults(suiteName: invalidDomain)!
            defer { invalidDefaults.removePersistentDomain(forName: invalidDomain) }
            invalidDefaults.set(["cpu", "cpu", "unknown"], forKey: "statusItemMetrics")
            checks["invalidLayoutUsesDefaults"] = MonitorPreferences(defaults: invalidDefaults).statusItemMetrics == [.memory, .cpu, .gpu]
            store.preferences.setMetric(.memory, for: .outerRing)
            store.preferences.setMetric(.cpu, for: .innerRing)
            checks["ringValuesHandleMissingAndBounds"] = StatusItemGraphic.percentage(nil) == nil
                && StatusItemGraphic.percentage(.nan) == nil && StatusItemGraphic.percentage(.infinity) == nil
                && StatusItemGraphic.percentage(-5) == 0 && StatusItemGraphic.percentage(150) == 100
            let compactWidth = controller.diagnosticState["statusItemWidth"] as? CGFloat
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
                && (controller.diagnosticState["statusItemWidth"] as? CGFloat ?? 0) > (compactWidth ?? 0)
            try controller.saveStatusItemImage(to: directory.appendingPathComponent("menu-rings-percentages.png"))
            store.preferences.setShowPercentages(false)
            store.route = .overview
            try await waitFor { store.snapshot.cpuProcessState == .available && store.snapshot.gpuProcessState == .available }
            try controller.savePopoverImage(to: directory.appendingPathComponent("overview-final.png"))
            controller.setDiagnosticAppearance(.darkAqua)
            try await Task.sleep(for: .milliseconds(200))
            try controller.savePopoverImage(to: directory.appendingPathComponent("overview-dark.png"))
            try controller.saveStatusItemImage(to: directory.appendingPathComponent("menu-rings-dark.png"))
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

    private static func saveRingExamples(to url: URL) throws {
        let snapshots = [
            SystemSnapshot(cpuPercent: 46, gpuPercent: 24,
                           memory: MemoryUsage(total: 100, app: 72, wired: 0, compressed: 0)),
            SystemSnapshot(cpuPercent: 0, gpuPercent: 0,
                           memory: MemoryUsage(total: 100, app: 0, wired: 0, compressed: 0)),
            SystemSnapshot(cpuPercent: 100, gpuPercent: 100,
                           memory: MemoryUsage(total: 100, app: 100, wired: 0, compressed: 0)),
            SystemSnapshot()
        ]
        let image = NSImage(size: NSSize(width: 240, height: 56), flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            for (index, snapshot) in snapshots.enumerated() {
                StatusItemGraphic.draw(snapshot: snapshot, layout: [.memory, .cpu, .gpu],
                                       visibleMetrics: Set(Metric.allCases),
                                       center: NSPoint(x: 30 + CGFloat(index) * 60, y: 28))
            }
            return true
        }
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
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
