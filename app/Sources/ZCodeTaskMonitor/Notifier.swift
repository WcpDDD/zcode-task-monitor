import AppKit
import Foundation
import UserNotifications

/// Posts native macOS notifications when a task transitions into a notable
/// state (waiting / error). Requests authorization once on first launch.
///
/// All access to UNUserNotificationCenter is guarded: if the process has no
/// valid bundle proxy (e.g. the raw binary launched outside its .app bundle),
/// `UNUserNotificationCenter.current()` throws an ObjC NSException and would
/// crash the whole app before the window ever appears. We detect that case via
/// Bundle.main.bundleIdentifier and silently skip notifications.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// True only when it's safe to use UNUserNotificationCenter.
    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorizationIfNeeded() {
        guard notificationsAvailable else {
            NSLog("[ZCodeTaskMonitor] notifications disabled: no bundle identifier")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Fires a "task is waiting on you" notification.
    func notifyWaiting(task: TaskSnapshot) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "任务在等你 👋"
        content.body = task.title
        content.subtitle = "\(task.workspaceName) · \(task.status.label)"
        content.sound = .default
        content.userInfo = ["workspace": task.workspacePath, "taskId": task.id]
        let req = UNNotificationRequest(
            identifier: "zcode-task-\(task.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    func notifyError(task: TaskSnapshot) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "任务出错 ❌"
        content.body = task.title
        content.subtitle = task.workspaceName
        content.sound = .default
        content.userInfo = ["workspace": task.workspacePath, "taskId": task.id]
        let req = UNNotificationRequest(
            identifier: "zcode-task-err-\(task.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // Tap on a notification → open that task's workspace in ZCode.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let ws = response.notification.request.content.userInfo["workspace"] as? String {
            DeepLinker.openWorkspace(ws)
        }
        completionHandler()
    }

    // Show notifications even when our app is focused.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
