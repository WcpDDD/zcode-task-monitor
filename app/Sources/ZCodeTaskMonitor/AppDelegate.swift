import AppKit

// MARK: - AppDelegate: owns the floating panel + a status-bar toggle.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let panel = FloatingPanel()
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Clear any persisted restoration archive so AppKit has nothing to restore.
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        if !bundleId.isEmpty {
            let stateURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
            try? FileManager.default.removeItem(at: stateURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorizationIfNeeded()
        setupStatusBar()

        // Show the floating panel.
        panel.show()

        // Wire the update callback BEFORE starting the poller, so the first
        // poll's results are guaranteed to trigger a render.
        store.onUpdate = { [weak self] in
            DispatchQueue.main.async { self?.render() }
        }
        store.start()
        render()
    }

    static func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    // MARK: Status bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.grid.1x2",
                accessibilityDescription: "ZCode Task Monitor"
            )
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    @objc private func togglePanel() {
        panel.toggleVisibility()
    }

    private func render() {
        panel.updateContent { view in
            view.update(
                grouped: store.groupedInProgress,
                waitingCount: store.waitingCount,
                inProgressCount: store.inProgress.count,
                dbHealthy: store.dbHealthy
            )
        }
        if let button = statusItem?.button {
            button.title = store.waitingCount > 0 ? " \(store.waitingCount)" : ""
        }
    }
}
