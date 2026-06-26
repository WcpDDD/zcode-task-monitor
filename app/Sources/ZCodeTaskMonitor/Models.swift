import Foundation

// MARK: - Task Status

/// The display status of a ZCode task, derived from the live session/turn DB.
enum TaskStatus: String, Codable {
    case running
    case waiting      // HITL: turn stuck in `running` with no recent activity
    case completed
    case error

    /// One-line label shown in the menu.
    var label: String {
        switch self {
        case .running:   return "运行中"
        case .waiting:   return "等待输入"
        case .completed: return "已完成"
        case .error:     return "出错"
        }
    }

    /// Emoji used as the colored dot in the menu.
    var dot: String {
        switch self {
        case .running:   return "🟢"
        case .waiting:   return "🟡"
        case .completed: return "⚪️"
        case .error:     return "🔴"
        }
    }
}

// MARK: - Task Snapshot

/// One task's full display state at a given poll.
struct TaskSnapshot: Identifiable, Hashable {
    let id: String                 // = session id = task id (sess_…)
    let title: String
    let workspacePath: String
    let mode: String               // build / yolo / draft …
    var status: TaskStatus
    let updatedAt: Date            // task row updated_at
    let lastActivityAt: Date?      // most recent tool/model completion (nil if none)

    /// Short label for the workspace, for grouping.
    var workspaceName: String {
        let url = URL(fileURLWithPath: workspacePath)
        return url.lastPathComponent.isEmpty ? workspacePath : url.lastPathComponent
    }

    /// Human-readable elapsed duration since the task was last updated (used as
    /// a proxy for "how long this task has been in its current state").
    var elapsedLabel: String {
        let secs = Date().timeIntervalSince(updatedAt)
        if secs < 60 { return "<1m" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let remMins = mins % 60
        if hours < 24 { return "\(hours)h\(remMins)m" }
        let days = hours / 24
        return "\(days)d\(hours % 24)h"
    }

    /// A soft "possibly stuck" hint: a running task that has shown no activity
    /// for a while may be blocked (waiting on user, hung, or long-thinking).
    /// This is purely advisory — surfaced as a small warning badge in the row.
    var blockingRisk: Bool {
        switch status {
        case .waiting:
            return true
        case .running:
            // Running but idle beyond the HITL threshold looks stuck.
            guard let last = lastActivityAt else { return false }
            return Date().timeIntervalSince(last) >= hitlInactivitySeconds
        default:
            return false
        }
    }

    /// True when a status change should surface a notification.
    static func isNotableTransition(from old: TaskStatus, to new: TaskStatus) -> Bool {
        // Any transition INTO waiting is notable (that's the HITL alert).
        // Also surface running -> error.
        if new == .waiting && old != .waiting { return true }
        if new == .error && old != .error { return true }
        return false
    }
}
