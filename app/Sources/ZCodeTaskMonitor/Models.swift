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

    /// True when a status change should surface a notification.
    static func isNotableTransition(from old: TaskStatus, to new: TaskStatus) -> Bool {
        // Any transition INTO waiting is notable (that's the HITL alert).
        // Also surface running -> error.
        if new == .waiting && old != .waiting { return true }
        if new == .error && old != .error { return true }
        return false
    }
}
