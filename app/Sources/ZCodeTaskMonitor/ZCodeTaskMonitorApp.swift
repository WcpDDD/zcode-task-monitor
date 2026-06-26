import SwiftUI

@main
struct ZCodeTaskMonitorApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            // Status-bar icon: shows a simple glyph plus a badge count of
            // tasks currently waiting on the user.
            if store.waitingCount > 0 {
                Text("⚡︎\(store.waitingCount)")
            } else {
                Image(systemName: "list.bullet.rectangle")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - TaskStore (observable, drives the UI + notifications)

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskSnapshot] = []
    @Published private(set) var lastUpdated: Date = Date()
    @Published private(set) var dbHealthy: Bool = true

    /// Previously-seen status per task id, used to detect transitions for
    /// notifications and to avoid re-alerting on every poll.
    private var lastStatus: [String: TaskStatus] = [:]
    /// Track which waiting tasks we've already notified, so we only notify
    /// once per waiting episode.
    private var notifiedWaiting: Set<String> = []

    private let poller = ZCodePoller()
    private var timer: Timer?

    var waitingCount: Int { tasks.filter { $0.status == .waiting }.count }

    init() {
        Notifier.shared.requestAuthorizationIfNeeded()
        poll()                      // immediate first poll
        schedule()
    }

    private func schedule() {
        // Poll every 5 seconds. Tolerance lets the run loop coalesce for power.
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 1.0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let snap = poller.snapshot()
        let now = Date()
        let healthy = ZCodePaths.tasksIndexExists

        // Detect notable transitions and fire notifications.
        for task in snap {
            let prev = lastStatus[task.id]
            lastStatus[task.id] = task.status

            if let prev = prev, TaskSnapshot.isNotableTransition(from: prev, to: task.status) {
                switch task.status {
                case .waiting:
                    // Only notify once per waiting episode.
                    if !notifiedWaiting.contains(task.id) {
                        Notifier.shared.notifyWaiting(task: task)
                        notifiedWaiting.insert(task.id)
                    }
                case .error:
                    Notifier.shared.notifyError(task: task)
                default:
                    break
                }
            }

            // Clear the "notified" flag once the task leaves the waiting state,
            // so a future re-entry alerts again.
            if task.status != .waiting {
                notifiedWaiting.remove(task.id)
            }
        }

        DispatchQueue.main.async {
            self.tasks = snap
            self.lastUpdated = now
            self.dbHealthy = healthy
        }
    }

    /// Tasks grouped by workspace, sorted: waiting first, then running, then
    /// completed/error; within a group, most-recently-updated first.
    var grouped: [(workspace: String, tasks: [TaskSnapshot])] {
        let order: [TaskStatus: Int] = [.waiting: 0, .running: 1, .error: 2, .completed: 3]
        let grouped = Dictionary(grouping: tasks) { $0.workspaceName }
        let mapped: [(workspace: String, tasks: [TaskSnapshot])] = grouped.map { (key, value) in
            let sorted = value.sorted {
                if order[$0.status] != order[$1.status] {
                    return order[$0.status]! < order[$1.status]!
                }
                return $0.updatedAt > $1.updatedAt
            }
            return (workspace: key, tasks: sorted)
        }
        return mapped.sorted { lhs, rhs in
            // Workspace with any waiting task floats to the top.
            let lhsWaiting = lhs.tasks.contains { $0.status == .waiting }
            let rhsWaiting = rhs.tasks.contains { $0.status == .waiting }
            if lhsWaiting != rhsWaiting { return lhsWaiting }
            return lhs.workspace < rhs.workspace
        }
    }
}

// MARK: - Menu UI

struct MenuView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.grouped, id: \.workspace) { group in
                            workspaceSection(group.workspace, tasks: group.tasks)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }

            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("ZCode 任务监控").font(.headline)
                if store.waitingCount > 0 {
                    Text("\(store.waitingCount) 个任务在等你").font(.caption).foregroundColor(.orange)
                } else {
                    Text("没有等待中的任务").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                // Manual refresh is implicit (timer runs), but offer a button.
                // We nudge by toggling nothing — the store polls on its own.
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("自动每 5 秒刷新")
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.title2).foregroundColor(.secondary)
            if store.dbHealthy {
                Text("暂无任务").font(.caption).foregroundColor(.secondary)
                Text("在 ZCode 里开始一个任务后，会显示在这里").font(.caption2).foregroundColor(.secondary)
            } else {
                Text("未检测到 ZCode 数据").font(.caption).foregroundColor(.red)
                Text("请确认 ZCode 已运行过").font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func workspaceSection(_ name: String, tasks: [TaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            ForEach(tasks) { task in
                TaskRowView(task: task)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("更新于 \(store.lastUpdated, style: .time)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("退出") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(8)
    }
}

struct TaskRowView: View {
    let task: TaskSnapshot

    var body: some View {
        Button {
            DeepLinker.openWorkspace(task.workspacePath)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(task.status.dot).font(.callout)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(task.status.label)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                        Text("·").font(.caption2).foregroundColor(.secondary)
                        Text(task.mode).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch task.status {
        case .waiting: return .orange
        case .running: return .green
        case .error: return .red
        case .completed: return .secondary
        }
    }
}
