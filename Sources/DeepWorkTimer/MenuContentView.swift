import SwiftUI

/// The menu bar popover: the dial on the left, three rows on the right
/// (title, task or status, buttons). Every state keeps the same three rows so
/// Start turns into Pause in place without the layout jumping.
struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @AppStorage(Prefs.Key.musicEnabled) private var musicEnabled = true
    @ObservedObject private var blocker = SiteBlocker.shared
    @StateObject private var blocklist = Flag()
    @StateObject private var quickSettings = Flag()
    @StateObject private var historyShown = Flag()
    @StateObject private var timeEdit = TimeEditState()
    /// The Today row is showing the current track instead (while you hover the music).
    @StateObject private var musicRow: Flag
    @ObservedObject private var music = MusicController.shared
    @FocusState private var timeFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var glass

    private var phase: Phase { timer.phase }
    private var isBreak: Bool { phase == .shortBreak || phase == .longBreak }
    /// A session just finished and its break is waiting to be started.
    private var breakReady: Bool { phase == .idle && timer.pendingBreak != nil }
    private var accent: Color { isBreak || breakReady ? Theme.green : Theme.red }
    private static let dialSize: CGFloat = 148
    /// Minutes around the whole dial.
    private static let dialMinutes = Double(Prefs.maxWorkMinutes)

    /// `musicExpanded` opens with the track row showing (for design previews).
    init(musicExpanded: Bool = false) {
        let row = Flag()
        row.value = musicExpanded
        _musicRow = StateObject(wrappedValue: row)
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 400)
        // The menu bar window is translucent; in light mode a dark wallpaper (like
        // the focus one) shows through as murky grey. A mostly-white layer keeps
        // contrast crisp while letting a hint of the desktop through.
        .background(colorScheme == .light ? Color.white.opacity(0.86) : .clear)
        .overlay(alignment: .topTrailing) { settingsButton.padding(8) }
        .tint(Theme.red)
        .animation(Theme.morph, value: phase)
        .animation(Theme.morph, value: timer.isPaused)
        .background { hiddenShortcuts }
        .contextMenu {
            Button("Settings…") { SettingsWindow.show() }
            Divider()
            Button("Quit Deep End") { NSApp.terminate(nil) }
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            TimerRing(fraction: dialFraction, tint: accent, onDrag: dialDrag, dragThreshold: phase == .idle ? 0 : 4)
                .opacity(timer.isPaused ? 0.5 : 1)
                .animation(.interactiveSpring, value: workMinutes)

            VStack(spacing: 4) {
                if timeEdit.editing {
                    timeField
                } else {
                    timeLabel
                }
                Text(timeEdit.editing ? "Minutes · ↩" : dialCaption)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: phase) { timeEdit.editing = false }
    }

    private var timeEditable: Bool { (phase == .idle && !breakReady) || phase == .work }

    /// The time. Hovering shows it can be edited; clicking turns it into a field.
    private var timeLabel: some View {
        Hoverable { hovered in
            let highlight = hovered && timeEditable
            Text(timeText)
                // h:mm:ss needs a smaller size to fit inside the ticks.
                .font(.system(size: timeText.count > 5 ? 27 : 34, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: phase != .idle))
                .animation(.snappy, value: timeText)
                .opacity(timer.isPaused ? 0.4 : 1)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(highlight ? Theme.fill : .clear)
                )
                .overlay(alignment: .bottom) {
                    // A short underline, like an editable field.
                    Capsule()
                        .fill(accent.opacity(highlight ? 0.7 : 0))
                        .frame(width: highlight ? 28 : 0, height: 2)
                        .offset(y: 1)
                }
                .contentShape(Rectangle())
                .pointerStyle(timeEditable ? .horizontalText : nil)
                .onTapGesture { if timeEditable { beginTimeEdit() } }
                .help(timeEditable ? "Click to type a time" : "")
        }
    }

    private var timeField: some View {
        TextField("", text: $timeEdit.draft)
            .textFieldStyle(.plain)
            .font(.system(size: 34, weight: .light))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 96)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.fill)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(accent.opacity(0.6), lineWidth: 1.5))
            )
            .focused($timeFieldFocused)
            .onSubmit(commitTimeEdit)
            .onExitCommand { timeEdit.editing = false }
            .onChange(of: timeFieldFocused) { _, focused in
                if !focused && timeEdit.editing { commitTimeEdit() }
            }
    }

    private func beginTimeEdit() {
        let minutes = phase == .idle ? workMinutes : Int((timer.remaining / 60).rounded())
        timeEdit.draft = "\(minutes)"
        timeEdit.editing = true
        DispatchQueue.main.async { timeFieldFocused = true }
    }

    private func commitTimeEdit() {
        defer { timeEdit.editing = false }
        guard let minutes = Self.parseMinutes(timeEdit.draft) else { return }
        let clamped = min(Prefs.maxWorkMinutes, max(1, minutes))
        switch phase {
        case .idle: workMinutes = clamped
        case .work: timer.setRemaining(TimeInterval(clamped * 60))
        case .shortBreak, .longBreak: break
        }
    }

    /// "45", "45m", "1:30", "1h30", "1h 30m", "1.5h" → minutes.
    static func parseMinutes(_ raw: String) -> Int? {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if s.isEmpty { return nil }
        if let colon = s.firstIndex(of: ":") {
            guard let h = Int(s[..<colon]), let m = Int(s[s.index(after: colon)...]), m < 60 else { return nil }
            return h * 60 + m
        }
        if let h = s.firstIndex(of: "h") {
            guard let hours = Double(s[..<h]) else { return nil }
            var rest = String(s[s.index(after: h)...])
            if rest.hasSuffix("min") { rest.removeLast(3) } else if rest.hasSuffix("m") { rest.removeLast() }
            let mins = rest.isEmpty ? 0 : (Int(rest) ?? -1)
            guard mins >= 0 else { return nil }
            return Int((hours * 60).rounded()) + mins
        }
        var digits = s
        if digits.hasSuffix("min") { digits.removeLast(3) } else if digits.hasSuffix("m") { digits.removeLast() }
        return Int(digits)
    }

    /// Focus time is shown on a fixed 120-minute face, like a kitchen timer, so
    /// the dial you set is the dial that drains. Breaks fill the whole face.
    private var dialFraction: Double {
        switch phase {
        case .idle: breakReady ? 1 : Double(workMinutes) / Self.dialMinutes
        case .work: timer.remaining / (Self.dialMinutes * 60)
        case .shortBreak, .longBreak: 1 - timer.progress
        }
    }

    private var dialDrag: ((Double) -> Void)? {
        switch phase {
        case .idle: breakReady ? nil : setDuration
        case .work: setRemaining
        case .shortBreak, .longBreak: nil
        }
    }

    private var timeText: String {
        if breakReady { return TimerModel.format(TimeInterval(timer.pendingBreakMinutes() * 60)) }
        return phase == .idle ? TimerModel.format(TimeInterval(workMinutes * 60)) : timer.displayTime
    }

    private var dialCaption: String {
        switch phase {
        case .idle: breakReady ? "Break" : "Minutes"
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
                // Long task names shrink to fit before they're cut off.
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .help(title)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
    }

    private var title: String {
        switch phase {
        case .idle: breakReady ? (timer.pendingBreak == .longBreak ? "Long break time" : "Break time") : "Deep Work"
        case .work: timer.intention.isEmpty ? "Deep Work" : timer.intention
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }

    /// Today's total lives in the footer, so this only says what's next.
    private var subtitle: String? {
        switch phase {
        case .idle: breakReady ? "Session done. Nice work." : nil
        case .work: timer.isPaused ? "Paused" : "Ends \(endTime)"
        case .shortBreak, .longBreak: timer.isPaused ? "Break paused" : "Back at \(endTime)"
        }
    }

    private var endTime: String {
        Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened)
    }

    /// The task field before a session; a status pill of the same size during one.
    @ViewBuilder
    private var middleRow: some View {
        switch phase {
        case .idle where breakReady:
            statusPill(symbol: "cup.and.saucer.fill", text: breakTip, trailing: nil)
        case .idle:
            TextField("What are you working on?", text: $timer.intention)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { timer.startWork() }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Theme.fill))
        case .work:
            blockPill
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

    // MARK: Today

    private static let goalOptions = [60, 120, 180, 240, 300, 360, 480]

    /// The Today row, or the current track while you hover the music at its end.
    private var footer: some View {
        ZStack {
            if musicEnabled && musicRow.value {
                NowPlayingRow()
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            } else {
                todayFooter
                    .transition(.opacity)
            }
        }
        .frame(height: 38)
        // Leaving the footer brings the Today row back.
        .onHover { inside in
            if !inside && musicRow.value { withAnimation(Theme.spring) { musicRow.value = false } }
        }
        .onChange(of: music.isVisible) { _, visible in
            if !visible { musicRow.value = false }
        }
    }

    private var musicTail: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 14)
            MusicTail()
                .onHover { inside in
                    if inside { withAnimation(Theme.spring) { musicRow.value = true } }
                }
        }
    }

    /// Today's focus time against your goal. Click the goal to change it.
    private var todayFooter: some View {
        let goal = Double(goalMinutes * 60)
        let fraction = min(1, timer.today.focusSeconds / goal)
        let sessions = timer.today.sessions
        let plan = sessionPlan
        return Hoverable { hovered in
            HStack(spacing: 8) {
                historyButton
                HStack(spacing: 3) {
                    Text(DailyStats.durationText(timer.today.focusSeconds))
                    Menu {
                        Section("Daily goal") {
                            ForEach(Self.goalOptions, id: \.self) { minutes in
                                Toggle(DailyStats.durationText(TimeInterval(minutes * 60)), isOn: Binding(
                                    get: { goalMinutes == minutes },
                                    set: { if $0 { goalMinutes = minutes } }
                                ))
                            }
                        }
                    } label: {
                        Text("of \(DailyStats.durationText(goal))")
                            .underline(hovered, color: .secondary.opacity(0.5))
                            // A menu's label otherwise draws in the primary colour.
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .pointerStyle(.link)
                    .fixedSize()
                    .help("Set your daily goal")
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)

                SessionBar(plan: plan, height: hovered ? 6 : 4)
                    .animation(Theme.spring, value: plan)

                if fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.green)
                        .symbolEffect(.bounce, value: sessions)
                }
                Text(sessionsText(plan))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if musicEnabled { musicTail }
            }
            .padding(.horizontal, 20)
            .frame(height: 38)
        }
    }

    /// "Today" doubles as the way into your history.
    private var historyButton: some View {
        Hoverable { hovered in
            Button { historyShown.value.toggle() } label: {
                HStack(spacing: 4) {
                    Text("Today").font(.system(size: 12, weight: .semibold))
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(hovered || historyShown.value ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.tertiary))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(hovered ? Theme.fill : .clear))
                .padding(.horizontal, -6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Your focus history")
        }
        .popover(isPresented: $historyShown.value, arrowEdge: .top) { HistoryView() }
    }

    private var sessionPlan: SessionPlan {
        let done = timer.today.entries.map { SessionPlan.Done(seconds: $0.seconds, completed: $0.completed, title: $0.intention) }
        let current = phase == .work
            ? (length: timer.phaseDuration, elapsed: max(0, timer.phaseDuration - timer.remaining), title: timer.intention)
            : nil
        return SessionPlan(done: done, current: current,
                           sessionLength: TimeInterval(workMinutes * 60), goal: TimeInterval(goalMinutes * 60))
    }

    private func sessionsText(_ plan: SessionPlan) -> String {
        let total = plan.segments.count
        let done = plan.doneCount
        return total == done ? (done == 1 ? "1 session" : "\(done) sessions") : "\(done) of \(total)"
    }

    // MARK: Settings

    /// Small and quiet in the corner until hovered.
    private var settingsButton: some View {
        Hoverable { hovered in
            Button { quickSettings.value.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovered || quickSettings.value ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .rotationEffect(.degrees(hovered ? 45 : 0))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(hovered ? Theme.fill : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .pointerStyle(.link)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .popover(isPresented: $quickSettings.value, arrowEdge: .bottom) { QuickSettingsView() }
    }

    // MARK: Blocking

    private var blockedCount: Int { blocker.blockedSites.count }
    private var blockingLive: Bool { blocker.settings.enabled && blockedCount > 0 && blocker.helperInstalled }

    /// Next to Start: what will be blocked. Opens the picker.
    private var blockButton: some View {
        Hoverable { hovered in
            Button { blocklist.value.toggle() } label: {
                Label(blockShortText, systemImage: blockingLive ? "shield.lefthalf.filled" : "shield.slash")
                    .overlay(alignment: .topLeading) {
                        // Sites are chosen but the one-time setup hasn't been done.
                        if blocker.settings.enabled && blockedCount > 0 && !blocker.helperInstalled {
                            Circle().fill(.orange).frame(width: 6, height: 6).offset(x: 9, y: -1)
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Capsule().fill(hovered ? Theme.fill : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Choose sites to block")
        }
        .popover(isPresented: $blocklist.value, arrowEdge: .bottom) { BlockPickerView() }
    }

    private var blockShortText: String {
        if !blocker.settings.enabled { return "Blocking off" }
        if blockedCount == 0 { return "Block sites" }
        return blockedCount == 1 ? "1 site" : "\(blockedCount) sites"
    }

    /// During a session: what's blocked right now. Opens the picker.
    private var blockPill: some View {
        Hoverable { hovered in
            Button { blocklist.value.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: blockingLive ? "shield.lefthalf.filled" : "shield.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(blockingLive ? Theme.red : .secondary)
                    Text(blockPillText).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Theme.fill.opacity(hovered ? 1.8 : 1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Choose sites to block")
        }
        .popover(isPresented: $blocklist.value, arrowEdge: .bottom) { BlockPickerView() }
        .transition(.opacity)
    }

    private var blockPillText: String {
        if !blocker.settings.enabled { return "Not blocking sites" }
        if blockedCount == 0 { return "Choose sites to block" }
        if !blocker.helperInstalled { return "Blocking needs setup" }
        return blockedCount == 1 ? "1 site blocked" : "\(blockedCount) sites blocked"
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
                GlassButton(prominent: true, tint: isBreak || breakReady ? Theme.green : nil, height: 30, horizontalPadding: 14,
                            glassID: "primary", namespace: glass, action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .keyboardShortcut(timeEdit.editing ? nil : phase == .idle ? .defaultAction : phase == .work ? KeyboardShortcut(.space, modifiers: []) : nil)
                .help(primaryHelp)

                if phase != .idle {
                    GlassButton(shape: .circle, height: 30, glassID: "cancel", namespace: glass, action: { timer.stop() }) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    }
                    .accessibilityLabel("End session")
                    .keyboardShortcut(".", modifiers: .command)
                    .help("End session  ⌘.")
                }

                if breakReady {
                    GlassButton(height: 30, horizontalPadding: 14, glassID: "cancel", namespace: glass, action: { timer.skipBreak() }) {
                        Text("Skip").font(.system(size: 12.5, weight: .semibold))
                    }
                    .help("Skip the break and get ready for the next session")
                } else if phase == .idle {
                    blockButton
                        .padding(.leading, 2)
                        .transition(.opacity)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch phase {
        case .idle: breakReady ? "Start Break" : "Start"
        case .work: timer.isPaused ? "Resume" : "Pause"
        case .shortBreak, .longBreak: "Skip"
        }
    }

    private var primarySymbol: String {
        switch phase {
        case .idle: breakReady ? "cup.and.saucer.fill" : "play.fill"
        case .work: timer.isPaused ? "play.fill" : "pause.fill"
        case .shortBreak, .longBreak: "forward.end.fill"
        }
    }

    private var primaryHelp: String {
        switch phase {
        case .idle: breakReady ? "Start your break  ↩" : "Start  ↩"
        case .work: "Pause or resume  Space"
        case .shortBreak, .longBreak: "Skip the rest of this break"
        }
    }

    private func primaryAction() {
        switch phase {
        case .idle: breakReady ? timer.startBreak() : timer.startWork()
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
            if phase != .idle && !timeEdit.editing {
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

final class TimeEditState: ObservableObject {
    @Published var editing = false
    @Published var draft = ""
}
