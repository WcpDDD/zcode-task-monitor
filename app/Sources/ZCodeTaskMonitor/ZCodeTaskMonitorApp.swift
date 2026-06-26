import AppKit

// Manual NSApplication bootstrap. We control the NSApplication lifecycle
// directly (rather than SwiftUI's @main App) because a pure SPM executable
// with only a Settings scene does not reliably drive the run loop / delegate.
@main
enum ZCodeTaskMonitorLaunch {
    static func main() {
        let app = NSApplication.shared

        // Disable AppKit's "Automatic Termination" — macOS will otherwise try
        // to kill an .accessory app that has "no windows open yet", which races
        // our panel creation and can suppress it. Also disable state restoration
        // so a previously-saved (broken) window state never blocks showing.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        ProcessInfo.processInfo.disableAutomaticTermination("floating-panel")

        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
