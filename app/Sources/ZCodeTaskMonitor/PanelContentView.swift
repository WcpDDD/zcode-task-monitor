import AppKit

/// Pure-AppKit content view for the floating panel. We avoid SwiftUI here
/// because NSHostingView/Controller intrinsic sizing is unreliable inside an
/// ad-hoc-signed bundle (collapses to a tiny height). AppKit lays out
/// deterministically regardless of signing context.
final class PanelContentView: NSView {
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "ZCode 任务")
    private let countLabel = NSTextField(labelWithString: "")

    var onTapTask: ((String) -> Void)?  // receives workspace path

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 210))
        wantsLayer = true
        layer?.cornerRadius = 12
        // Translucent vibrancy: use a visual-effect view as the backdrop so the
        // panel shows the desktop/windows behind it, like a macOS HUD.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Called when the user clicks the close button.
    var onClose: (() -> Void)?

    private func setupSubviews() {
        // Header: title | count | close button
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = NSColor(white: 1, alpha: 0.7)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(countLabel)

        let closeBtn = NSButton()
        closeBtn.bezelStyle = .inline
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = NSColor(white: 1, alpha: 0.6)
        closeBtn.isBordered = false
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.toolTip = "关闭浮窗(从菜单栏图标可重新打开)"
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        header.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 18),
            closeBtn.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Scrollable task list, anchored to the TOP so rows flow downward
        // (the panel's content grows from the top, not centered).
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            // Pin the stack to the TOP of the scroll content; do NOT constrain
            // its bottom so it sizes to its content and content starts at top.
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    @objc private func closeClicked() {
        onClose?()
    }

    /// Rebuild the task rows from a snapshot.
    func update(grouped: [(workspace: String, tasks: [TaskSnapshot])], waitingCount: Int, inProgressCount: Int, dbHealthy: Bool) {
        // Header text
        if waitingCount > 0 {
            countLabel.stringValue = "⚡ \(waitingCount) 待响应"
            countLabel.textColor = .systemOrange
        } else {
            countLabel.stringValue = "\(inProgressCount) 进行中"
            countLabel.textColor = .secondaryLabelColor
        }

        // Clear existing
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if grouped.isEmpty {
            let empty = NSTextField(labelWithString: dbHealthy ? "没有进行中的任务 ✅" : "未检测到 ZCode 数据")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = NSColor(white: 1, alpha: 0.6)
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(empty)
            // Add to the stack BEFORE activating constraints that pair the
            // wrap with the stack, so they share a common ancestor.
            stackView.addArrangedSubview(wrap)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                wrap.heightAnchor.constraint(equalToConstant: 80),
                wrap.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            ])
            return
        }

        // Build section headers + rows, then add them all at once so width
        // constraints (pinned to stackView.widthAnchor) always find a common
        // ancestor after insertion.
        var newViews: [NSView] = []
        for group in grouped {
            newViews.append(makeSectionHeader(group.workspace))
            for task in group.tasks {
                newViews.append(makeTaskRow(task))
            }
        }
        // Each row/header should match the stack's width so they scroll/clip
        // correctly. Add them first, then pin widths.
        for v in newViews { stackView.addArrangedSubview(v) }
        for v in newViews {
            NSLayoutConstraint.activate([
                v.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            ])
        }
    }

    private func makeSectionHeader(_ name: String) -> NSView {
        let label = NSTextField(labelWithString: name)
        label.font = .boldSystemFont(ofSize: 9)
        label.textColor = NSColor(white: 1, alpha: 0.55)
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        // Pin the label inside the wrap; the wrap's width is driven by the
        // stackView (which is constrained to the scrollView width in setup).
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -8),
            wrap.heightAnchor.constraint(equalToConstant: 16),
        ])
        return wrap
    }

    private func makeTaskRow(_ task: TaskSnapshot) -> NSView {
        let row = TaskRow()
        row.task = task
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.cornerRadius = 6

        let dot = NSTextField(labelWithString: task.status.dot)
        dot.font = .systemFont(ofSize: 11)
        dot.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: task.title)
        title.font = .systemFont(ofSize: 11)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.cell?.truncatesLastVisibleLine = true
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Right-side meta: elapsed duration + optional blocking-warning badge.
        let elapsed = NSTextField(labelWithString: task.elapsedLabel)
        elapsed.font = .systemFont(ofSize: 9)
        elapsed.textColor = NSColor(white: 1, alpha: 0.6)
        elapsed.translatesAutoresizingMaskIntoConstraints = false
        elapsed.setContentHuggingPriority(.required, for: .horizontal)
        elapsed.setContentCompressionResistancePriority(.required, for: .horizontal)

        let warn = NSTextField(labelWithString: "⚠ 可能阻塞")
        warn.font = .systemFont(ofSize: 9)
        warn.textColor = .systemOrange
        warn.isHidden = !task.blockingRisk
        warn.translatesAutoresizingMaskIntoConstraints = false
        warn.setContentHuggingPriority(.required, for: .horizontal)
        warn.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(dot)
        row.addSubview(title)
        row.addSubview(warn)
        row.addSubview(elapsed)

        // Constraints all within the row (row <-> its own subviews).
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            // Right edge: [title] ... [warn?] [elapsed]
            elapsed.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            elapsed.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            warn.trailingAnchor.constraint(equalTo: elapsed.leadingAnchor, constant: -6),
            warn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            title.trailingAnchor.constraint(lessThanOrEqualTo: warn.leadingAnchor, constant: -6),
        ])

        // Click to open workspace.
        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
        row.addGestureRecognizer(click)

        return row
    }

    @objc private func rowClicked(_ sender: NSClickGestureRecognizer) {
        guard let row = sender.view as? TaskRow, let ws = row.task?.workspacePath else { return }
        onTapTask?(ws)
    }

    private func color(for status: TaskStatus) -> NSColor {
        switch status {
        case .waiting: return .systemOrange
        case .running: return .systemGreen
        case .error: return .systemRed
        case .completed: return NSColor(white: 1, alpha: 0.6)
        }
    }
}

private final class TaskRow: NSView {
    var task: TaskSnapshot?
}
