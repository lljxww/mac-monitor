import AppKit
import MonitorCore
import SwiftUI

/// The only top-level UI is an NSStatusItem and its transient NSPopover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: MonitorStore
    private let preferences: MonitorPreferences
    private var lastImageKey: ImageKey?
    private var lastDescription: String?

    private struct ImageKey: Equatable {
        let metrics: [Metric]
        let layout: [Metric]
        let percentages: [Int]
        let numbers: [String]
        let appearance: NSAppearance.Name
    }

    init(store: MonitorStore, preferences: MonitorPreferences) {
        self.store = store
        self.preferences = preferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 850) - 32
        let height = min(738, max(460, availableHeight))
        let root = PopoverView(store: store, preferences: preferences, height: height)
        let hostingView = NoFocusHostingView(rootView: root)
        hostingView.frame = NSRect(x: 0, y: 0, width: 410, height: height)
        hostingView.onEscape = { [weak self] in self?.close() }
        let controller = NSViewController()
        controller.view = hostingView
        controller.preferredContentSize = NSSize(width: 410, height: height)
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.setAccessibilityLabel("Mac Monitor")
        }
        store.didSample = { [weak self] in self?.refresh() }
        preferences.didChange = { [weak self] change in
            guard let self else { return }
            self.refresh()
            if change != .display { self.store.restartSampling() }
        }
        refresh()
    }

    func refresh() {
        let metrics = preferences.orderedMetrics
        let snapshot = store.latestSnapshot
        let showNumbers = preferences.showPercentages
        let description = metrics.map { "\($0.title) \(DisplayFormat.percent(snapshot.percent(for: $0)))" }.joined(separator: " · ")
        if description != lastDescription {
            statusItem.button?.toolTip = "Mac Monitor\n\(description)\n点击查看进程排行"
            statusItem.button?.setAccessibilityValue(description)
            lastDescription = description
        }
        let layout = preferences.statusItemMetrics
        let key = ImageKey(metrics: metrics, layout: layout, percentages: metrics.map { metric in
            StatusItemGraphic.percentage(snapshot.percent(for: metric)) ?? -1
        }, numbers: showNumbers ? metrics.map { DisplayFormat.percent(snapshot.percent(for: $0)) } : [],
                           appearance: statusItem.button?.effectiveAppearance.name ?? .aqua)
        guard key != lastImageKey else { return }
        lastImageKey = key
        let size = NSSize(width: showNumbers ? 32 + CGFloat(metrics.count) * 37 : 32, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            StatusItemGraphic.draw(snapshot: snapshot, layout: layout, visibleMetrics: Set(metrics),
                                   center: NSPoint(x: 16, y: 11))
            if showNumbers {
                for (index, metric) in metrics.enumerated() {
                    let value = snapshot.percent(for: metric)
                    let text = DisplayFormat.percent(value)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: metric.nsColor
                    ]
                    (text as NSString).draw(at: NSPoint(x: 34 + CGFloat(index) * 37, y: 5), withAttributes: attributes)
                }
            }
            return true
        }
        image.isTemplate = false
        if statusItem.length != size.width { statusItem.length = size.width }
        statusItem.button?.image = image
    }

    @objc func togglePopover() {
        if popover.isShown { close() } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        store.setPresented(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Do not activate the app or assign focus to any input/control on opening.
        if let panel = popover.contentViewController?.view.window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = true
        }
        popover.contentViewController?.view.window?.initialFirstResponder = nil
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        button.state = .on
    }

    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.state = .off
        store.setPresented(false)
    }

    func close() {
        popover.close()
        statusItem.button?.state = .off
        store.setPresented(false)
    }

    #if DEBUG
    var diagnosticState: [String: Any] {
        let window = popover.contentViewController?.view.window
        return [
            "popoverShown": popover.isShown,
            "popoverWidth": popover.contentSize.width,
            "popoverHeight": popover.contentSize.height,
            "focusedResponder": window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none",
            "isMainWindow": window?.isMainWindow ?? false,
            "isDetachable": popover.isDetached,
            "statusItemWidth": statusItem.length,
            "statusItemVisible": statusItem.isVisible,
            "statusButtonWindow": statusItem.button?.window != nil,
            "statusButtonFrame": statusItem.button.map { NSStringFromRect($0.frame) } ?? "none",
            "contentFrame": popover.contentViewController.map { NSStringFromRect($0.view.frame) } ?? "none",
            "visibleMetrics": preferences.orderedMetrics.map(\.rawValue),
            "statusItemMetrics": preferences.statusItemMetrics.map(\.rawValue),
            "renderedStatusItemMetrics": lastImageKey?.layout.map(\.rawValue) ?? []
        ]
    }

    func savePopoverImage(to url: URL) throws {
        guard let view = popover.contentViewController?.view else { return }
        // SwiftUI retains unchanged layers across route updates. Invalidating the
        // full view tree makes cacheDisplay include those layers in diagnostics.
        func invalidate(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(invalidate)
        }
        invalidate(view)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }

    func setDiagnosticAppearance(_ name: NSAppearance.Name?) {
        popover.contentViewController?.view.window?.appearance = name.flatMap(NSAppearance.init(named:))
        statusItem.button?.appearance = name.flatMap(NSAppearance.init(named:))
        refresh()
    }

    func saveStatusItemImage(to url: URL) throws {
        guard let data = statusItem.button?.image?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
    #endif
}

@MainActor
private final class NoFocusHostingView<Content: View>: NSHostingView<Content> {
    var onEscape: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
