import AppKit

/// The floating, always-on-top panel. Uses NSPanel with .nonactivatingPanel so
/// it floats above all windows (including ZCode) without stealing keyboard focus.
final class FloatingPanel {
    private var panel: NSPanel?
    private let contentView = PanelContentView()

    private let panelWidth: CGFloat = 280
    private let panelHeight: CGFloat = 210

    var onTapTask: ((String) -> Void)? {
        get { contentView.onTapTask }
        set { contentView.onTapTask = newValue }
    }

    init() {
        contentView.onTapTask = { ws in DeepLinker.openWorkspace(ws) }
        contentView.onClose = { [weak self] in self?.hide() }
    }

    func show() {
        if let panel = panel {
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Translucent: clear panel background lets the content view's material
        // (vibrancy) show through.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.isMovable = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Set the content view and pin it to the panel's content edges.
        let container = panel.contentView!
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        positionTopRight(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func updateContent(_ block: (PanelContentView) -> Void) {
        block(contentView)
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggleVisibility() {
        guard let panel = panel else { show(); return }
        if panel.isVisible { panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }
    }

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let x = screenFrame.maxX - size.width - 16
        let y = screenFrame.maxY - size.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
