import Foundation

/// Resolves the two ZCode SQLite DB paths. ZCode stores its data under
/// `~/.zcode`. We resolve at runtime so the same binary works for any user.
enum ZCodePaths {
    static var home: String { ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory() }

    /// The task list DB (titles, workspace, task_status).
    static var tasksIndexDB: String { "\(home)/.zcode/v2/tasks-index.sqlite" }

    /// The live session/turn/usage DB (the source of truth for real-time status).
    static var sessionDB: String { "\(home)/.zcode/cli/db/db.sqlite" }

    static var tasksIndexExists: Bool { FileManager.default.fileExists(atPath: tasksIndexDB) }
    static var sessionDBExists: Bool { FileManager.default.fileExists(atPath: sessionDB) }
}

/// The HITL-detection threshold. A turn stuck in `running` with no tool/model
/// activity for this long is treated as "waiting on the user".
let hitlInactivitySeconds: TimeInterval = 45

/// Polls both DBs, joins them, and classifies each task's live status.
final class ZCodePoller {
    private let tasks = SQLiteReader(ZCodePaths.tasksIndexDB)
    private let sessions = SQLiteReader(ZCodePaths.sessionDB)

    /// Produce the full snapshot of all non-archived tasks with classified status.
    func snapshot() -> [TaskSnapshot] {
        guard ZCodePaths.tasksIndexExists else { return [] }

        // 1. Pull the task list (metadata + workspace grouping).
        let taskRows = tasks.query(
            """
            SELECT task_id, title, task_status, mode, workspace_path, updated_at
            FROM tasks
            WHERE archived = 0 AND deleted = 0
            """
        ) { stmt, _ in
            TaskRow(
                id: SQLiteReader.text(stmt, 0),
                title: SQLiteReader.text(stmt, 1),
                taskStatus: SQLiteReader.text(stmt, 2),
                mode: SQLiteReader.text(stmt, 3),
                workspacePath: SQLiteReader.text(stmt, 4),
                updatedAtMs: SQLiteReader.int64(stmt, 5)
            )
        }

        // 2. Pull live turn/activity state per session (db.sqlite). Only available
        //    when the session DB exists. Keyed by session id (= task id).
        var liveState: [String: LiveState] = [:]
        if ZCodePaths.sessionDBExists {
            let rows = sessions.query(
                """
                SELECT s.id,
                       t.status,
                       MAX(tu.completed_at) AS last_tool_at,
                       MAX(mu.completed_at) AS last_model_at,
                       (SELECT tool_name FROM tool_usage
                          WHERE session_id = s.id
                          ORDER BY started_at DESC LIMIT 1) AS last_tool_name,
                       (SELECT status FROM tool_usage
                          WHERE session_id = s.id
                          ORDER BY started_at DESC LIMIT 1) AS last_tool_status
                FROM session s
                LEFT JOIN turn_usage t ON t.session_id = s.id
                LEFT JOIN tool_usage tu ON tu.session_id = s.id
                LEFT JOIN model_usage mu ON mu.session_id = s.id
                WHERE s.task_type = 'interactive'
                GROUP BY s.id
                """
            ) { stmt, _ in
                LiveState(
                    sessionId: SQLiteReader.text(stmt, 0),
                    turnStatus: SQLiteReader.text(stmt, 1),
                    lastToolAtMs: SQLiteReader.int64OrNil(stmt, 2),
                    lastModelAtMs: SQLiteReader.int64OrNil(stmt, 3),
                    lastToolName: SQLiteReader.text(stmt, 4),
                    lastToolStatus: SQLiteReader.text(stmt, 5)
                )
            }
            for r in rows { liveState[r.sessionId] = r }
        }

        // 3. Merge + classify.
        return taskRows.map { row -> TaskSnapshot in
            let live = liveState[row.id]
            let status = classify(row: row, live: live)
            let lastActivityMs: Int64? = {
                guard let live = live else { return nil }
                return max(live.lastToolAtMs ?? 0, live.lastModelAtMs ?? 0)
            }()
            return TaskSnapshot(
                id: row.id,
                title: row.title.isEmpty ? "(未命名任务)" : row.title,
                workspacePath: row.workspacePath,
                mode: row.mode,
                status: status,
                updatedAt: Date(ms: row.updatedAtMs),
                lastActivityAt: lastActivityMs.flatMap { $0 > 0 ? Date(ms: $0) : nil }
            )
        }
    }

    // MARK: - Classification

    private func classify(row: TaskRow, live: LiveState?) -> TaskStatus {
        // Source of truth for "is this task still open": the tasks-index
        // task_status. ZCode marks a task 'running' while its tab is open and
        // considered active, even if the current turn has finished (turns are
        // per-message; a task sits 'running' between user messages). The
        // turn-level data is only used to refine running -> waiting (HITL).
        switch row.taskStatus {
        case "completed":
            return .completed
        case "running":
            return classifyRunning(row: row, live: live)
        default:
            // Unknown / archived-ish: treat as running if the task list says so.
            return row.taskStatus == "completed" ? .completed : classifyRunning(row: row, live: live)
        }
    }

    /// Given a task the task-list marks as 'running', decide running vs
    /// waiting (HITL) using live turn/tool activity.
    private func classifyRunning(row: TaskRow, live: LiveState?) -> TaskStatus {
        guard let live = live, !live.turnStatus.isEmpty else {
            // No live data available — can't detect HITL; assume running.
            return .running
        }

        // Only an actively-running turn can be "waiting on the user".
        guard live.turnStatus == "running" else {
            // Turn is completed/cancelled/error, but the task is still open.
            // The task is idle between turns — show as running (not completed).
            return live.turnStatus == "error" ? .error : .running
        }

        // Fast path: an interactive tool (AskUserQuestion / ExitPlanMode)
        // still running is an explicit "waiting on user" signal.
        if live.lastToolStatus == "running",
           let name = live.lastToolName as String?, name.isEmpty == false,
           isInteractiveTool(name) {
            return .waiting
        }
        // Inference path: turn running but no tool/model activity for >= threshold.
        let lastMs = max(live.lastToolAtMs ?? 0, live.lastModelAtMs ?? 0)
        let age: TimeInterval
        if lastMs > 0 {
            age = Date().timeIntervalSince(Date(ms: lastMs))
        } else {
            age = Date().timeIntervalSince(Date(ms: row.updatedAtMs))
        }
        return age >= hitlInactivitySeconds ? .waiting : .running
    }

    /// Tools that, when still running, unambiguously mean "waiting on the user".
    private func isInteractiveTool(_ name: String) -> Bool {
        // ZCode's HITL-style tools. AskUserQuestion is the clearest. ExitPlanMode
        // also blocks on the user.
        let interactive: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
        return interactive.contains(name)
    }
}

// MARK: - Internal row structs

private struct TaskRow {
    let id: String
    let title: String
    let taskStatus: String
    let mode: String
    let workspacePath: String
    let updatedAtMs: Int64
}

private struct LiveState {
    let sessionId: String
    let turnStatus: String
    let lastToolAtMs: Int64?
    let lastModelAtMs: Int64?
    let lastToolName: String
    let lastToolStatus: String
}

// MARK: - Date helpers

extension Date {
    init(ms: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }
}
