import SwiftUI

/// A small floating banner at the top of the screen when a phase ends on its own.
/// It's visible even with the popover closed and a Focus mode silencing notifications.
struct ToastView: View {
    let transition: Transition
    var onAction: () -> Void = {}
    var onClose: () -> Void = {}
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.redGradient)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: Theme.red.opacity(0.35), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                GlassButton(prominent: true, height: 30, namespace: glass, action: onAction) {
                    Text(actionTitle).font(.system(size: 12, weight: .semibold))
                }
                IconButton(systemImage: "xmark", hoverRotation: 90, action: onClose)
                    .accessibilityLabel("Dismiss")
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .frame(width: 390)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(24) // room for the glass shadow inside the transparent window
    }

    private var icon: String {
        switch transition {
        case .workDone: "checkmark"
        case .breakDone: "timer"
        }
    }

    private var title: String {
        switch transition {
        case .workDone: "Session complete"
        case .breakDone: "Break's over"
        }
    }

    private var subtitle: String {
        switch transition {
        case .workDone(let minutes, let long):
            long ? "\(minutes)-minute long break. Step away." : "Enjoy a \(minutes)-minute break."
        case .breakDone(let next):
            "Ready for session \(next)?"
        }
    }

    private var actionTitle: String {
        switch transition {
        case .workDone: "Skip Break"
        case .breakDone: "Start"
        }
    }
}

@MainActor
final class ToastController {
    static let shared = ToastController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ transition: Transition, model: TimerModel) {
        dismiss(animated: false)

        let view = ToastView(
            transition: transition,
            onAction: { [weak self] in
                switch transition {
                case .workDone: model.skip()
                case .breakDone: model.startWork()
                }
                self?.dismiss()
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(contentRect: hosting.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height + 8))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss(animated: Bool = true) {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
