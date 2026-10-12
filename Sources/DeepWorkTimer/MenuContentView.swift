import SwiftUI

/// The menu bar popover: the ring on the left, what you need right now on the
/// right, and today's progress along the bottom.
struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    @Namespace private var glass

    private var phase: Phase { timer.phase }
    private static let presets = [25, 50, 90]
    private static let ringSize: CGFloat = 156

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ring
                    .frame(width: Self.ringSize, height: Self.ringSize)
                controls
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.ringSize)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)

            today
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.fill.opacity(0.6))
        }
        .frame(width: 440)
        .tint(Theme.red)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .animation(Theme.morph, value: phase)
        .animation(Theme.morph, value: timer.isPaused)
        .background {
            // ⌘Q while the popover is open.
            Button("") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            TimerRing(
                fraction: phase == .idle
                    ? Double(workMinutes) / Double(Prefs.maxWorkMinutes)
                    : 1 - timer.progress,
                onDrag: phase == .idle ? setDuration : nil
            )
            .animation(phase == .idle ? .interactiveSpring : .linear(duration: 1), value: timer.progress)
            .animation(.interactiveSpring, value: workMinutes)

            VStack(spacing: 3) {
                Text(timeText)
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: phase != .idle))
                    .animation(.snappy, value: timeText)
                    .opacity(timer.isPaused ? 0.35 : 1)
                Text(ringCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .allowsHitTesting(false)
        }
    }

    private var timeText: String {
        phase == .idle ? TimerModel.format(TimeInterval(workMinutes * 60)) : timer.displayTime
    }

    private var ringCaption: String {
        if phase == .idle { return "Drag to set" }
        return timer.isPaused ? "Paused" : "Remaining"
    }

    private func setDuration(_ fraction: Double) {
        var minutes = Int((fraction * Double(Prefs.maxWorkMinutes) / 5).rounded()) * 5
        // Don't wrap around past 12 o'clock.
        if workMinutes >= 100 && minutes <= 20 { minutes = Prefs.maxWorkMinutes }
        if workMinutes <= 20 && minutes >= 100 { minutes = 5 }
        minutes = min(Prefs.maxWorkMinutes, max(5, minutes))
        guard minutes != workMinutes else { return }
        workMinutes = minutes
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 10)
            middle
            Spacer(minLength: 12)
            actions
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.isPaused ? "Paused" : phase.label)
                    .font(.system(size: 22, weight: .bold))
                    .contentTransition(.opacity)
                Text(headerCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            IconButton(systemImage: "gearshape", hoverRotation: 60) { SettingsWindow.show() }
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings  ⌘,")
        }
    }

    private var headerCaption: String {
        let session = "Session \(timer.sessionNumber) of \(sessionsPerLongBreak)"
        let end = Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened)
        switch phase {
        case .idle: return session
        case .work: return timer.isPaused ? session : "\(session) · ends \(end)"
        case .shortBreak, .longBreak: return timer.isPaused ? "Break paused" : "Back at \(end)"
        }
    }

    @ViewBuilder
    private var middle: some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField("What are you working on?", text: $timer.intention)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { timer.startWork() }
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(Theme.fill))

                Picker("Length", selection: $workMinutes) {
                    ForEach(Self.presets, id: \.self) { Text("\($0) min").tag($0) }
                    if !Self.presets.contains(workMinutes) {
                        Text("\(workMinutes) min").tag(workMinutes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .work, .shortBreak, .longBreak:
            VStack(alignment: .leading, spacing: 9) {
                Text(phase == .work ? (timer.intention.isEmpty ? "Heads down. You've got this." : timer.intention) : breakTip)
                    .font(.system(size: 13, weight: phase == .work && !timer.intention.isEmpty ? .medium : .regular))
                    .foregroundStyle(phase == .work && !timer.intention.isEmpty ? .primary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        GlassButton(height: 28, horizontalPadding: 11, namespace: glass, action: { timer.adjust(minutes: -5) }) {
                            Text("−5 min").font(.system(size: 11.5, weight: .medium))
                        }
                        .accessibilityLabel("5 minutes less")
                        .keyboardShortcut("-", modifiers: [])
                        .help("5 minutes less  −")
                        GlassButton(height: 28, horizontalPadding: 11, namespace: glass, action: { timer.adjust(minutes: 5) }) {
                            Text("+5 min").font(.system(size: 11.5, weight: .medium))
                        }
                        .keyboardShortcut("=", modifiers: [])
                        .help("5 minutes more  +")
                        GlassButton(shape: .circle, height: 28, namespace: glass, action: { timer.skip() }) {
                            Image(systemName: "forward.end.fill").font(.system(size: 10.5, weight: .semibold))
                        }
                        .accessibilityLabel(phase == .work ? "Take a break" : "Skip break")
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                        .help(phase == .work ? "End this session and take a break  ⌘→" : "Skip the rest of this break  ⌘→")
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
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

    /// One red Start capsule that morphs into Cancel + Pause once a session runs.
    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if phase != .idle {
                    GlassButton(shape: .circle, height: 38, glassID: "cancel", namespace: glass, action: { timer.stop() }) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    }
                    .accessibilityLabel("Cancel")
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Cancel  ⌘.")
                }

                GlassButton(prominent: phase == .idle || timer.isPaused, height: 38, expands: true,
                            glassID: "primary", namespace: glass, action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(phase != .idle && !timer.isPaused ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.white))
                }
                .keyboardShortcut(phase == .idle ? .defaultAction : KeyboardShortcut(.space, modifiers: []))
                .help(phase == .idle ? "Start  ↩" : "Pause or resume  Space")
            }
        }
    }

    private var primaryTitle: String {
        if phase == .idle { return "Start Focus" }
        return timer.isPaused ? "Resume" : "Pause"
    }

    private var primarySymbol: String {
        if phase == .idle || timer.isPaused { return "play.fill" }
        return "pause.fill"
    }

    private func primaryAction() {
        phase == .idle ? timer.startWork() : timer.togglePause()
    }

    // MARK: Today

    private var today: some View {
        let goal = Double(goalMinutes * 60)
        let fraction = min(1, timer.today.focusSeconds / goal)
        return Hoverable { hovered in
            HStack(spacing: 10) {
                Image(systemName: fraction >= 1 ? "checkmark.circle.fill" : "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
                    .symbolEffect(.bounce, value: timer.today.sessions)
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(DailyStats.durationText(timer.today.focusSeconds)) of \(DailyStats.durationText(goal))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(Theme.redGradient)
                            .frame(width: fraction > 0 ? max(hovered ? 6 : 4, geo.size.width * fraction) : 0)
                    }
                }
                .frame(height: hovered ? 6 : 4)
                Text(timer.today.sessions == 1 ? "1 session" : "\(timer.today.sessions) sessions")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .help("\(Int(fraction * 100))% of your daily goal")
        }
    }
}
