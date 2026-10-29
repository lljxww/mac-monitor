import Combine
import Foundation
import MonitorCore

enum StatusItemPosition: Int, CaseIterable, Identifiable {
    case outerRing, innerRing, center

    var id: Self { self }
    var title: String {
        switch self {
        case .outerRing: "外环"
        case .innerRing: "内环"
        case .center: "中心数字"
        }
    }
}

@MainActor
final class MonitorPreferences: ObservableObject {
    enum Change { case metrics, interval, display }
    @Published private(set) var visibleMetrics: Set<Metric>
    @Published private(set) var refreshInterval: Double
    @Published private(set) var showPercentages: Bool
    @Published private(set) var statusItemMetrics: [Metric]
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
        let layout = defaults.stringArray(forKey: "statusItemMetrics")?.compactMap(Metric.init(rawValue:))
        statusItemMetrics = layout.flatMap { metrics in
            metrics.count == StatusItemPosition.allCases.count && Set(metrics).count == metrics.count ? metrics : nil
        } ?? [.memory, .cpu, .gpu]
    }

    var orderedMetrics: [Metric] { Metric.allCases.filter(visibleMetrics.contains) }

    func metric(for position: StatusItemPosition) -> Metric {
        statusItemMetrics[position.rawValue]
    }

    func setMetric(_ metric: Metric, for position: StatusItemPosition) {
        guard let previousIndex = statusItemMetrics.firstIndex(of: metric), previousIndex != position.rawValue else { return }
        var layout = statusItemMetrics
        layout.swapAt(position.rawValue, previousIndex)
        statusItemMetrics = layout
        defaults.set(layout.map(\.rawValue), forKey: "statusItemMetrics")
        didChange?(.display)
    }

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
