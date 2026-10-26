import Combine
import Foundation
import MonitorCore

enum PopoverRoute: Equatable {
    case overview, processes(Metric), settings
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    private(set) var history: [SystemHistoryPoint] = []
    private(set) var latestSnapshot = SystemSnapshot()
    @Published var route: PopoverRoute = .overview {
        didSet { if oldValue != route && isPresented { restartSampling() } }
    }
    private(set) var isPresented = false
    var didSample: (() -> Void)?
    let preferences: MonitorPreferences
    private let sampler = SystemSampler()
    private var samplingTask: Task<Void, Never>?

    init(preferences: MonitorPreferences) { self.preferences = preferences }

    func start() { restartSampling() }

    func setPresented(_ presented: Bool) {
        guard isPresented != presented else { return }
        isPresented = presented
        if presented {
            route = .overview
            snapshot = latestSnapshot
        } else {
            snapshot = latestSnapshot.systemOnly
        }
        restartSampling()
    }

    func restartSampling() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            var firstSample = true
            while !Task.isCancelled {
                guard let self else { return }
                let processMetrics: Set<Metric>
                switch (self.isPresented, self.route) {
                case (false, _), (_, .settings): processMetrics = []
                case (true, .overview): processMetrics = self.preferences.visibleMetrics
                case let (true, .processes(metric)): processMetrics = [metric]
                }
                let result = await self.sampler.sample(systemMetrics: self.preferences.visibleMetrics,
                                                       processMetrics: processMetrics)
                guard !Task.isCancelled else { return }
                self.latestSnapshot = result
                self.history.append(result.historyPoint)
                self.history.removeAll { result.date.timeIntervalSince($0.date) > 120 }
                // A retained, closed popover must not recompute its SwiftUI tree.
                if self.isPresented { self.snapshot = result }
                self.didSample?()
                // Prime process deltas quickly on opening, then use the chosen interval.
                let delay = firstSample && !processMetrics.isEmpty ? 0.8 : self.preferences.refreshInterval
                firstSample = false
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stop() { samplingTask?.cancel() }
}
