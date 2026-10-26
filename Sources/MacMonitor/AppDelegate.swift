import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: MonitorStore?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-self-test")
        let testDomain = "com.liangjw.mac-monitor.ui-self-test.\(UUID().uuidString)"
        let preferences = MonitorPreferences(defaults: testing ? UserDefaults(suiteName: testDomain)! : .standard)
        #else
        let preferences = MonitorPreferences()
        #endif
        let store = MonitorStore(preferences: preferences)
        self.store = store
        statusController = StatusItemController(store: store, preferences: preferences)
        store.start()
        #if DEBUG
        if testing, let statusController {
            Task {
                let passed = await UIDiagnostics.run(store: store, controller: statusController, domain: testDomain)
                store.stop()
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusController?.showPopover()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showPopover()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { store?.stop() }
}
