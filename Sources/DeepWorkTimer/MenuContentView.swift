import SwiftUI

/// The menu bar popover: ring on the left, controls on the right, today along the bottom.
struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240

    private var phase: Phase { timer.phase }
    private static let presets = [25, 50, 90]
    private static let ringSize: CGFloat = 164

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

            Divider()

            today
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
        }
        .frame(width: 440)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
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

            VStack(spacing: 5) {
                Text(timeText)
                    .font(.system(size: 36, weight: .thin))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: phase != .idle))
                    .animation(.snappy, value: timeText)
                    .opacity(timer.isPaused ? 0.35 : 1)
                ringCaption
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
        }
    }

    private var timeText: String {
        phase == .idle ? TimerModel.format(TimeInterval(workMinutes * 60)) : timer.displayTime
    }

    @ViewBuilder
    private var ringCaption: some View {
        if phase == .idle {
            Text("Drag to adjust")
        } else if timer.isPaused {
            Text("Paused")
        } else {
            HStack(spacing: 4) {
                Image(systemName: phase == .work ? "bell.fill" : "cup.and.saucer.fill")
                    .font(.system(size: 10))
                Text(Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened))
            }
        }
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
            Spacer(minLength: 8)
            middle
            Spacer(minLength: 10)
            buttons
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.isPaused ? "Paused" : phase.label)
                    .font(.system(size: 20, weight: .semibold))
                Text(headerCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { SettingsWindow.show() } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings  ⌘,")
        }
    }

    private var headerCaption: String {
        switch phase {
        case .idle, .work: "Session \(timer.sessionNumber) of \(sessionsPerLongBreak)"
        case .shortBreak: "Back to it soon"
        case .longBreak: "Nice cycle. Step away."
        }
    }

    @ViewBuilder
    private var middle: some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                TextField("What are you working on?", text: $timer.intention)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fill))
                    .onSubmit { timer.startWork() }
                SegmentedControl(options: Self.presets, selection: $workMinutes) { "\($0) min" }
            }

        case .work, .shortBreak, .longBreak:
            VStack(alignment: .leading, spacing: 8) {
                Text(phase == .work ? (timer.intention.isEmpty ? "Heads down." : timer.intention) : breakTip)
                    .font(.system(size: 13))
                    .foregroundStyle(phase == .work && !timer.intention.isEmpty ? .primary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("−5 min") { timer.adjust(minutes: -5) }
                        .keyboardShortcut("-", modifiers: [])
                        .help("5 minutes less  −")
                    Button("+5 min") { timer.adjust(minutes: 5) }
                        .keyboardShortcut("=", modifiers: [])
                        .help("5 minutes more  +")
                    Button(phase == .work ? "Take Break" : "Skip Break") { timer.skip() }
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                        .help(phase == .work ? "End this session and start a break  ⌘→" : "Skip the rest of this break  ⌘→")
                }
                .buttonStyle(PillButtonStyle())
            }
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

    private var buttons: some View {
        HStack {
            Button("Cancel") { timer.stop() }
                .buttonStyle(ClockButtonStyle(kind: .neutral))
                .disabled(phase == .idle)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop  ⌘.")
            Spacer()
            if phase == .idle {
                Button("Start") { timer.startWork() }
                    .buttonStyle(ClockButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .help("Start  ↩")
            } else {
                Button(timer.isPaused ? "Resume" : "Pause") { timer.togglePause() }
                    .buttonStyle(ClockButtonStyle(kind: timer.isPaused ? .primary : .tinted))
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Pause or resume  Space")
            }
        }
    }

    // MARK: Today

    private var today: some View {
        let goal = Double(goalMinutes * 60)
        let fraction = min(1, timer.today.focusSeconds / goal)
        return HStack(spacing: 10) {
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
                        .fill(Theme.red)
                        .frame(width: fraction > 0 ? max(4, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 4)
            Text(timer.today.sessions == 1 ? "1 session" : "\(timer.today.sessions) sessions")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
