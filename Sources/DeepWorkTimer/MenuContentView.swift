import SwiftUI

/// The menu bar popover: the dial on the left, three rows on the right
/// (title, task or status, buttons). Every state keeps the same three rows so
/// Start turns into Pause in place without the layout jumping.
struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @Namespace private var glass

    private var phase: Phase { timer.phase }
    private var isBreak: Bool { phase == .shortBreak || phase == .longBreak }
    private var accent: Color { isBreak ? Theme.green : Theme.red }
    private static let dialSize: CGFloat = 148
    /// Minutes around the whole dial.
    private static let dialMinutes = Double(Prefs.maxWorkMinutes)

    var body: some View {
        HStack(spacing: 20) {
            dial
                .frame(width: Self.dialSize, height: Self.dialSize)
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                middleRow
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 400)
        .tint(Theme.red)
        .animation(Theme.morph, value: phase)
        .animation(Theme.morph, value: timer.isPaused)
        .background { hiddenShortcuts }
        .contextMenu {
            Button("Settings…") { SettingsWindow.show() }
            Divider()
            Button("Quit Deep Work Timer") { NSApp.terminate(nil) }
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            TimerRing(fraction: dialFraction, tint: accent, onDrag: dialDrag, dragThreshold: phase == .idle ? 0 : 4)
                .opacity(timer.isPaused ? 0.5 : 1)
                .animation(.interactiveSpring, value: workMinutes)

            VStack(spacing: 4) {
                Text(timeText)
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: phase != .idle))
                    .animation(.snappy, value: timeText)
                    .opacity(timer.isPaused ? 0.4 : 1)
                Text(dialCaption)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .allowsHitTesting(false)
        }
    }

    /// Focus time is shown on a fixed 120-minute face, like a kitchen timer, so
    /// the dial you set is the dial that drains. Breaks fill the whole face.
    private var dialFraction: Double {
        switch phase {
        case .idle: Double(workMinutes) / Self.dialMinutes
        case .work: timer.remaining / (Self.dialMinutes * 60)
        case .shortBreak, .longBreak: 1 - timer.progress
        }
    }

    private var dialDrag: ((Double) -> Void)? {
        switch phase {
        case .idle: setDuration
        case .work: setRemaining
        case .shortBreak, .longBreak: nil
        }
    }

    private var timeText: String {
        phase == .idle ? TimerModel.format(TimeInterval(workMinutes * 60)) : timer.displayTime
    }

    private var dialCaption: String {
        switch phase {
        case .idle: "Minutes"
        case .work: timer.isPaused ? "Paused" : "Remaining"
        case .shortBreak, .longBreak: timer.isPaused ? "Paused" : "Break"
        }
    }

    /// Minutes for a dial position, without wrapping past 12 o'clock.
    private func minutes(at fraction: Double, current: Int, step: Int) -> Int {
        let max = Prefs.maxWorkMinutes
        var minutes = Int((fraction * Self.dialMinutes / Double(step)).rounded()) * step
        if current >= max - 20 && minutes <= 20 { minutes = max }
        if current <= 20 && minutes >= max - 20 { minutes = step }
        return min(max, Swift.max(step, minutes))
    }

    private func setDuration(_ fraction: Double) {
        let new = minutes(at: fraction, current: workMinutes, step: 5)
        guard new != workMinutes else { return }
        workMinutes = new
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func setRemaining(_ fraction: Double) {
        let current = Int((timer.remaining / 60).rounded())
        let new = minutes(at: fraction, current: current, step: 1)
        guard new != current else { return }
        timer.setRemaining(TimeInterval(new * 60))
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Rows

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
            Text(subtitle)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
    }

    private var title: String {
        switch phase {
        case .idle: "Deep Work"
        case .work: timer.intention.isEmpty ? "Deep Work" : timer.intention
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }

    private var subtitle: String {
        let today = "\(DailyStats.durationText(timer.today.focusSeconds)) of \(DailyStats.durationText(Double(goalMinutes * 60))) today"
        if isBreak { return timer.isPaused ? "Break paused" : "Back at \(endTime)" }
        return today
    }

    private var endTime: String {
        Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened)
    }

    /// The task field before a session; a status pill of the same size during one.
    @ViewBuilder
    private var middleRow: some View {
        switch phase {
        case .idle:
            TextField("What are you working on?", text: $timer.intention)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { timer.startWork() }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Theme.fill))
        case .work:
            statusPill(symbol: effectsEnabled ? "moon.fill" : "timer",
                       text: timer.isPaused ? "Paused" : "Ends at \(endTime)",
                       trailing: nil)
        case .shortBreak, .longBreak:
            statusPill(symbol: "cup.and.saucer.fill", text: breakTip, trailing: nil)
        }
    }

    private func statusPill(symbol: String, text: String, trailing: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Theme.fill))
        .transition(.opacity)
    }

    private var breakTip: String {
        let tips = [
            "Stand up and stretch.",
            "Look at something far away.",
            "Refill your water.",
            "Step outside for a minute.",
            "Close your eyes and breathe.",
        ]
        return tips[timer.today.entries.count % tips.count]
    }

    /// Start, which morphs into Pause/Resume (or Skip on a break) plus ✕.
    private var actions: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                GlassButton(prominent: true, tint: isBreak ? Theme.green : nil, height: 30, horizontalPadding: 14,
                            glassID: "primary", namespace: glass, action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .keyboardShortcut(phase == .idle ? .defaultAction : phase == .work ? KeyboardShortcut(.space, modifiers: []) : nil)
                .help(primaryHelp)

                if phase != .idle {
                    GlassButton(shape: .circle, height: 30, glassID: "cancel", namespace: glass, action: { timer.stop() }) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    }
                    .accessibilityLabel("End session")
                    .keyboardShortcut(".", modifiers: .command)
                    .help("End session  ⌘.")
                }

                if phase == .idle && effectsEnabled {
                    Label("Focus mode", systemImage: "moon.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .transition(.opacity)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch phase {
        case .idle: "Start"
        case .work: timer.isPaused ? "Resume" : "Pause"
        case .shortBreak, .longBreak: "Skip"
        }
    }

    private var primarySymbol: String {
        switch phase {
        case .idle: "play.fill"
        case .work: timer.isPaused ? "play.fill" : "pause.fill"
        case .shortBreak, .longBreak: "forward.end.fill"
        }
    }

    private var primaryHelp: String {
        switch phase {
        case .idle: "Start  ↩"
        case .work: "Pause or resume  Space"
        case .shortBreak, .longBreak: "Skip the rest of this break"
        }
    }

    private func primaryAction() {
        switch phase {
        case .idle: timer.startWork()
        case .work: timer.togglePause()
        case .shortBreak, .longBreak: timer.skip()
        }
    }

    // MARK: Keyboard

    /// Shortcuts for things that no longer have a visible button.
    private var hiddenShortcuts: some View {
        ZStack {
            Button("") { SettingsWindow.show() }.keyboardShortcut(",", modifiers: .command)
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            if phase != .idle {
                // Not while idle: these would swallow keystrokes in the task field.
                Button("") { timer.adjust(minutes: -5) }.keyboardShortcut("-", modifiers: [])
                Button("") { timer.adjust(minutes: 5) }.keyboardShortcut("=", modifiers: [])
                Button("") { timer.skip() }.keyboardShortcut(.rightArrow, modifiers: .command)
            }
            if isBreak {
                Button("") { timer.togglePause() }.keyboardShortcut(.space, modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
