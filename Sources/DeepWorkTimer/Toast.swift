import SwiftUI

/// A small floating banner at the top of the screen when a phase ends on its own.
/// It's visible even with the popover closed and a Focus mode silencing notifications.
struct ToastView: View {
    let transition: Transition
    var onAction: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(phase.gradient)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: phase.tint.opacity(0.5), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: onAction)
                .buttonStyle(ChipButtonStyle(phase: phase, selected: true))
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(24) // room for the shadow inside the transparent window
    }

    private var phase: Phase {
        switch transition {
        case .workDone(_, let long): long ? .longBreak : .shortBreak
        case .breakDone: .work
        }
    }

    private var icon: String {
        switch transition {
        case .workDone: "checkmark"
        case .breakDone: "play.fill"
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
            long ? "Long break · \(minutes) min. Step away properly." : "Take \(minutes) min. You've earned it."
        case .breakDone(let next):
            "Ready for session \(next)?"
        }
    }

    private var actionTitle: String {
        switch transition {
        case .workDone: "Skip break"
        case .breakDone: "Start focus"
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
