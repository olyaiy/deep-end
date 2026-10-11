import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    // Plain ObservableObjects instead of @State: the @State macro plugin ships
    // only with full Xcode, and this builds with just the Command Line Tools.
    @StateObject private var ui: MenuUIState

    init(showingSettings: Bool = false) {
        _ui = StateObject(wrappedValue: MenuUIState(showingSettings: showingSettings))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Soft phase-colored glow behind everything.
            RadialGradient(
                colors: [timer.phase.tint.opacity(ui.showingSettings ? 0.08 : 0.2), .clear],
                center: .top, startRadius: 0, endRadius: 280
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.6), value: timer.phase)

            Group {
                if ui.showingSettings {
                    SettingsView(done: { withAnimation(.snappy) { ui.showingSettings = false } })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    TimerScreen(openSettings: { withAnimation(.snappy) { ui.showingSettings = true } })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(16)
        }
        .frame(width: 320)
    }
}

final class MenuUIState: ObservableObject {
    @Published var showingSettings: Bool
    init(showingSettings: Bool) { self.showingSettings = showingSettings }
}

// MARK: - Timer screen

struct TimerScreen: View {
    @EnvironmentObject private var timer: TimerModel
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    let openSettings: () -> Void

    private var phase: Phase { timer.phase }
    private static let presets = [25, 50, 90]

    var body: some View {
        VStack(spacing: 16) {
            header
            dial
            intention
            controls
            TodayCard(today: timer.today, week: timer.week, goalMinutes: goalMinutes)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(phase.gradient)
                .frame(width: 7, height: 7)
                .shadow(color: phase.tint.opacity(0.8), radius: 3)
            Text(headerTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer()
            Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings  ⌘,")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit  ⌘Q")
        }
    }

    private var headerTitle: String {
        switch phase {
        case .idle: "READY TO FOCUS"
        case .work: timer.isPaused ? "PAUSED" : "DEEP WORK · \(timer.sessionNumber) OF \(sessionsPerLongBreak)"
        case .shortBreak: timer.isPaused ? "PAUSED" : "SHORT BREAK"
        case .longBreak: timer.isPaused ? "PAUSED" : "LONG BREAK"
        }
    }

    // MARK: Dial

    private var dial: some View {
        VStack(spacing: 12) {
            ZStack {
                Dial(
                    progress: phase == .idle ? Double(workMinutes) / Double(Prefs.maxWorkMinutes) : timer.progress,
                    phase: phase,
                    onDrag: phase == .idle ? setDuration : nil
                )
                .frame(width: 200, height: 200)
                .animation(phase == .idle ? .interactiveSpring : .linear(duration: 1), value: timer.progress)

                VStack(spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: phase != .idle))
                        .animation(.snappy, value: timeText)
                        .opacity(timer.isPaused ? 0.45 : 1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }

            CycleDots(
                total: sessionsPerLongBreak,
                // The cycle count resets when a long break starts; show it as a full set.
                completed: phase == .longBreak ? sessionsPerLongBreak : timer.cycleCount,
                current: phase == .idle || phase == .work ? timer.cycleCount : nil,
                phase: phase == .idle ? .work : phase
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var timeText: String {
        phase == .idle ? TimerModel.format(TimeInterval(workMinutes * 60)) : timer.displayTime
    }

    private var subtitle: String {
        if phase == .idle { return "drag the ring to adjust" }
        if timer.isPaused { return "paused" }
        let end = Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened)
        return phase == .work ? "ends at \(end)" : "back at \(end)"
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

    // MARK: Intention

    @ViewBuilder
    private var intention: some View {
        switch phase {
        case .idle:
            HStack(spacing: 9) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Phase.work.tint)
                TextField("What will you focus on?", text: $timer.intention)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { timer.startWork() }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

        case .work:
            if !timer.intention.isEmpty {
                VStack(spacing: 4) {
                    SectionLabel(title: "Focusing on")
                    Text(timer.intention)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }

        case .shortBreak, .longBreak:
            Text(breakTip)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var breakTip: String {
        let tips = [
            "Stand up and stretch.",
            "Look at something far away for a bit.",
            "Refill your water.",
            "Step outside for a minute.",
            "Close your eyes and take a few slow breaths.",
        ]
        return tips[timer.today.entries.count % tips.count]
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if phase == .idle {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button("\(minutes) min") {
                            withAnimation(.snappy) { workMinutes = minutes }
                        }
                        .buttonStyle(ChipButtonStyle(phase: .work, selected: workMinutes == minutes))
                    }
                }
                Button { timer.startWork() } label: {
                    Label("Start focus", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(phase: .work))
                .keyboardShortcut(.defaultAction)
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Button { timer.adjust(minutes: -5) } label: { Text("−5").font(.system(size: 13, weight: .semibold, design: .rounded)) }
                        .buttonStyle(CircleButtonStyle(phase: phase, size: 38))
                        .keyboardShortcut("-", modifiers: [])
                        .help("5 minutes less  −")
                    Button { timer.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(CircleButtonStyle(phase: phase, size: 42))
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop  ⌘.")
                    Button { timer.togglePause() } label: {
                        Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(CircleButtonStyle(phase: phase, size: 58, prominent: true))
                    .keyboardShortcut(.space, modifiers: [])
                    .help(timer.isPaused ? "Resume  Space" : "Pause  Space")
                    Button { timer.skip() } label: { Image(systemName: "forward.end.fill") }
                        .buttonStyle(CircleButtonStyle(phase: phase, size: 42))
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                        .help(phase == .work ? "End session, start break  ⌘→" : "Skip break  ⌘→")
                    Button { timer.adjust(minutes: 5) } label: { Text("+5").font(.system(size: 13, weight: .semibold, design: .rounded)) }
                        .buttonStyle(CircleButtonStyle(phase: phase, size: 38))
                        .keyboardShortcut("=", modifiers: [])
                        .help("5 minutes more  +")
                }
                Text("space pause · +/− adjust · ⌘. stop")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Today

struct TodayCard: View {
    let today: DailyStats
    let week: [DailyStats]
    let goalMinutes: Int

    private var goalSeconds: Double { Double(goalMinutes * 60) }
    private var fraction: Double { min(1, today.focusSeconds / goalSeconds) }
    private var goalReached: Bool { today.focusSeconds >= goalSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                SectionLabel(title: "Today")
                Spacer()
                if goalReached {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Phase.shortBreak.gradient)
                }
                Text(DailyStats.durationText(today.focusSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("of \(DailyStats.durationText(goalSeconds))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(goalReached ? Phase.shortBreak.gradient : Phase.work.gradient)
                        .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)

            HStack(alignment: .bottom) {
                weekBars
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(today.sessions)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(today.sessions == 1 ? "session" : "sessions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !today.entries.isEmpty {
                Divider().opacity(0.6)
                VStack(spacing: 7) {
                    ForEach(Array(today.entries.suffix(3).reversed()), id: \.self) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .card()
    }

    private var weekBars: some View {
        let peak = max(goalSeconds, week.map(\.focusSeconds).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(week) { day in
                let isToday = day.day == today.day
                let seconds = isToday ? today.focusSeconds : day.focusSeconds
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.06)).frame(width: 12, height: 34)
                        Capsule()
                            .fill(isToday ? AnyShapeStyle(Phase.work.gradient) : AnyShapeStyle(Color.primary.opacity(0.28)))
                            .frame(width: 12, height: seconds > 0 ? max(4, 34 * seconds / peak) : 0)
                    }
                    Text(day.weekdayInitial)
                        .font(.system(size: 9, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .help("\(DailyStats.durationText(seconds)) focused")
            }
        }
    }

    private func entryRow(_ entry: DailyStats.Entry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(entry.completed ? AnyShapeStyle(Phase.work.gradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                .frame(width: 6, height: 6)
            Text(entry.intention.isEmpty ? "Untitled session" : entry.intention)
                .font(.system(size: 12))
                .foregroundStyle(entry.intention.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(DailyStats.durationText(entry.seconds))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(entry.endedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
