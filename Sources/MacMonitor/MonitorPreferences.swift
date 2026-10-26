import Combine
import Foundation
import MonitorCore

@MainActor
final class MonitorPreferences: ObservableObject {
    enum Change { case metrics, interval, display }
    @Published private(set) var visibleMetrics: Set<Metric>
    @Published private(set) var refreshInterval: Double
    @Published private(set) var showPercentages: Bool
    var didChange: ((Change) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: "visibleMetrics")?.compactMap(Metric.init(rawValue:))
        let selection = saved.map(Set.init) ?? Set(Metric.allCases)
        visibleMetrics = selection.isEmpty ? [.cpu] : selection
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = [1.0, 2.0, 3.0, 5.0].contains(interval) ? interval : 2
        showPercentages = defaults.bool(forKey: "showPercentages")
    }

    var orderedMetrics: [Metric] { Metric.allCases.filter(visibleMetrics.contains) }

    func setVisible(_ metric: Metric, visible: Bool) {
        guard visibleMetrics.contains(metric) != visible else { return }
        guard visible || visibleMetrics.count > 1 else { return }
        if visible { visibleMetrics.insert(metric) } else { visibleMetrics.remove(metric) }
        defaults.set(orderedMetrics.map(\.rawValue), forKey: "visibleMetrics")
        didChange?(.metrics)
    }

    func setInterval(_ interval: Double) {
        guard [1.0, 2.0, 3.0, 5.0].contains(interval), interval != refreshInterval else { return }
        refreshInterval = interval
        defaults.set(interval, forKey: "refreshInterval")
        didChange?(.interval)
    }

    func setShowPercentages(_ show: Bool) {
        guard show != showPercentages else { return }
        showPercentages = show
        defaults.set(show, forKey: "showPercentages")
        didChange?(.display)
    }
}
