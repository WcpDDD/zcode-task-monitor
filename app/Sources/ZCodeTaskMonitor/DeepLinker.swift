import AppKit
import Foundation

/// Opens a task's workspace in ZCode via the `zcode://` deep link.
/// ZCode registers the `zcode` URL scheme (CFBundleURLSchemes) and handles
/// `zcode://workspace/open?path=<encoded>` by focusing the app and switching
/// to that workspace.
enum DeepLinker {
    static func openWorkspace(_ path: String) {
        // Build the deep link. Encode the path as a query param.
        var components = URLComponents()
        components.scheme = "zcode"
        components.host = "workspace"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        guard let url = components.url else {
            NSLog("[ZCodeTaskMonitor] failed to build deep link for \(path)")
            return
        }

        let success = NSWorkspace.shared.open(url)
        if !success {
            NSLog("[ZCodeTaskMonitor] NSWorkspace.open failed for \(url.absoluteString)")
        }
    }

    /// True if ZCode.app appears to be installed.
    static var zcodeInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/ZCode.app")
    }
}
