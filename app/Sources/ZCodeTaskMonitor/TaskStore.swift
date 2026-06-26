import Foundation

// MARK: - TaskStore (observable, drives the UI + notifications)

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskSnapshot] = []
    @Published private(set) var lastUpdated: Date = Date()
    @Published private(set) var dbHealthy: Bool = true

    /// Fired on the main thread whenever a poll completes (so the UI can refresh).
    var onUpdate: (() -> Void)?

    private var lastStatus: [String: TaskStatus] = [:]
    private var notifiedWaiting: Set<String> = []

    private let poller = ZCodePoller()
    private var timer: Timer?
    private var started = false

    var waitingCount: Int { tasks.filter { $0.status == .waiting }.count }

    /// Begin polling. Called once by the owner AFTER setting `onUpdate`, so the
    /// first poll's results are guaranteed to flow through onUpdate.
    func start() {
        guard !started else { return }
        started = true
        poll()
        schedule()
    }

    /// All in-progress tasks: running, waiting, error. Excludes completed.
    var inProgress: [TaskSnapshot] {
        tasks.filter { $0.status != .completed }
    }

    /// In-progress tasks grouped by workspace (waiting first, then running,
    /// then error), most-recently-updated first within a group.
    var groupedInProgress: [(workspace: String, tasks: [TaskSnapshot])] {
        let order: [TaskStatus: Int] = [.waiting: 0, .running: 1, .error: 2]
        let grouped = Dictionary(grouping: inProgress) { $0.workspaceName }
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
            let lhsWaiting = lhs.tasks.contains { $0.status == .waiting }
            let rhsWaiting = rhs.tasks.contains { $0.status == .waiting }
            if lhsWaiting != rhsWaiting { return lhsWaiting }
            return lhs.workspace < rhs.workspace
        }
    }

    init() {
        Notifier.shared.requestAuthorizationIfNeeded()
    }

    private func schedule() {
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

        for task in snap {
            let prev = lastStatus[task.id]
            lastStatus[task.id] = task.status

            if let prev = prev, TaskSnapshot.isNotableTransition(from: prev, to: task.status) {
                switch task.status {
                case .waiting:
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
            if task.status != .waiting {
                notifiedWaiting.remove(task.id)
            }
        }

        DispatchQueue.main.async {
            self.tasks = snap
            self.lastUpdated = now
            self.dbHealthy = healthy
            self.onUpdate?()
        }
    }
}
