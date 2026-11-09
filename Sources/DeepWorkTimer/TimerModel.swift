import AppKit

enum Phase: String {
    case idle, work, shortBreak, longBreak

    var title: String {
        switch self {
        case .idle: "Ready"
        case .work: "Deep work"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// A phase that ended on its own, so the UI can announce it.
enum Transition {
    case workDone(breakMinutes: Int, longBreak: Bool)
    case breakDone(nextSession: Int)
}

@MainActor
final class TimerModel: ObservableObject {
    /// The running instance, for URL-scheme commands handled by the app delegate.
    static weak var live: TimerModel?

    @Published private(set) var phase: Phase = .idle { didSet { schedulePersist() } }
    @Published private(set) var now = Date()
    @Published private(set) var today = DailyStats.load()
    @Published private(set) var week = DailyStats.lastSevenDays()
    /// Completed work sessions since the last long break.
    @Published private(set) var cycleCount = 0 { didSet { schedulePersist() } }

    // The timer stores an end date rather than counting ticks, so it stays
    // accurate across sleep/wake and doesn't drift.
    @Published private(set) var endDate: Date? { didSet { schedulePersist() } }
    @Published private(set) var pausedRemaining: TimeInterval? { didSet { schedulePersist() } }
    @Published private(set) var phaseDuration: TimeInterval = 1 { didSet { schedulePersist() } }
    /// A break that's earned but not started. Breaks wait for you rather than
    /// starting on their own.
    @Published private(set) var pendingBreak: Phase? { didSet { schedulePersist() } }

    @Published var intention = UserDefaults.standard.string(forKey: "lastIntention") ?? "" {
        didSet { UserDefaults.standard.set(intention, forKey: "lastIntention") }
    }

    var onTransition: ((Transition) -> Void)?

    private var workStartedAt: Date? { didSet { schedulePersist() } }
    private var persistScheduled = false
    private var ticker: Task<Void, Never>?
    /// Preview models (for design snapshots) must never touch the real Focus or wallpaper.
    private let isLive: Bool

    init(live: Bool = true) {
        isLive = live
        guard live else { return }
        TimerModel.live = self
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    // MARK: Derived state

    var isPaused: Bool { pausedRemaining != nil }

    var remaining: TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(now))
    }

    var progress: Double {
        phase == .idle ? 0 : min(1, max(0, 1 - remaining / phaseDuration))
    }

    var displayTime: String { Self.format(remaining) }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Which session in the current cycle we're on (1-based).
    var sessionNumber: Int { min(cycleCount + 1, Prefs.sessionsPerLongBreak) }

    // MARK: Actions

    func startWork(minutes: Int? = nil) {
        if let minutes { UserDefaults.standard.set(minutes, forKey: Prefs.Key.workMinutes) }
        workStartedAt = Date()
        pendingBreak = nil
        begin(.work, minutes: Prefs.workMinutes)
        if isLive { SessionEffects.shared.apply() }
    }

    func pause() {
        guard !isPaused, endDate != nil else { return }
        pausedRemaining = remaining
        endDate = nil
    }

    func resume() {
        guard let pausedRemaining else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        now = Date()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    /// Lengthen or shorten the running phase. Never drops below one minute left.
    func adjust(minutes: Int) {
        adjust(by: TimeInterval(minutes * 60))
    }

    /// Change how long the running phase is in total, keeping the time already spent.
    func setPhaseLength(minutes: Int) {
        adjust(by: TimeInterval(minutes * 60) - phaseDuration)
    }

    /// Set the time left in the running phase (dragging the dial).
    func setRemaining(_ seconds: TimeInterval) {
        adjust(by: seconds - remaining)
    }

    private func adjust(by delta: TimeInterval) {
        guard phase != .idle else { return }
        let newRemaining = max(60, remaining + delta)
        let applied = newRemaining - remaining
        if pausedRemaining != nil {
            pausedRemaining = newRemaining
        } else {
            endDate = Date().addingTimeInterval(newRemaining)
        }
        phaseDuration = max(60, phaseDuration + applied)
        now = Date()
    }

    /// End the current phase early and move to the next one.
    func skip() {
        // Skipping out of focus means you asked for the break: start it now.
        finishPhase(completed: false)
        startBreak()
    }

    func startBreak() {
        guard let next = pendingBreak else { return }
        pendingBreak = nil
        begin(next, minutes: pendingBreakMinutes(next))
    }

    func skipBreak() {
        pendingBreak = nil
    }

    func pendingBreakMinutes(_ kind: Phase? = nil) -> Int {
        (kind ?? pendingBreak) == .longBreak ? Prefs.longBreakMinutes : Prefs.shortBreakMinutes
    }

    /// Stop everything and go back to idle.
    func stop() {
        if phase == .work {
            recordFocusTime(completed: false)
            if isLive { SessionEffects.shared.revert() }
        }
        pendingBreak = nil
        reset()
    }

    // MARK: Internals

    private func begin(_ next: Phase, minutes: Int) {
        phase = next
        phaseDuration = TimeInterval(max(1, minutes) * 60)
        endDate = Date().addingTimeInterval(phaseDuration)
        pausedRemaining = nil
        now = Date()
    }

    private func reset() {
        phase = .idle
        endDate = nil
        pausedRemaining = nil
        workStartedAt = nil
    }

    private func tick() {
        now = Date()
        if today.day != DailyStats.todayKey { reloadStats() }
        if let endDate, now >= endDate {
            finishPhase(completed: true)
        }
    }

    /// `announce: false` ends it quietly (one that ran out while the app wasn't running).
    private func finishPhase(completed: Bool, announce: Bool = true) {
        switch phase {
        case .idle:
            return

        case .work:
            recordFocusTime(completed: completed, endedAt: min(Date(), endDate ?? Date()))
            if isLive { SessionEffects.shared.revert() }
            if completed { cycleCount += 1 }
            let long = cycleCount >= Prefs.sessionsPerLongBreak
            if long { cycleCount = 0 }
            let minutes = long ? Prefs.longBreakMinutes : Prefs.shortBreakMinutes
            reset()
            pendingBreak = long ? .longBreak : .shortBreak
            if completed && announce {
                playSound("Glass")
                onTransition?(.workDone(breakMinutes: minutes, longBreak: long))
            }

        case .shortBreak, .longBreak:
            reset()
            if completed && announce {
                playSound("Hero")
                onTransition?(.breakDone(nextSession: sessionNumber))
            }
        }
    }

    private func recordFocusTime(completed: Bool, endedAt: Date = Date()) {
        guard workStartedAt != nil else { return }
        // Planned minus remaining excludes paused time.
        let elapsed = max(0, phaseDuration - remaining)
        workStartedAt = nil
        guard elapsed >= 60 else { return }
        today.focusSeconds += elapsed
        if completed { today.sessions += 1 }
        today.entries.append(.init(intention: intention, seconds: elapsed, endedAt: endedAt, completed: completed))
        today.save()
        week = DailyStats.lastSevenDays()
    }

    // MARK: Surviving a restart

    /// What's needed to pick a session back up in a new process: after an
    /// update swaps in a new build (see Relaunch), or after a crash. Saved on
    /// every change; the countdown itself is just an end date, so nothing drifts.
    private struct Snapshot: Codable {
        var phase: String
        var endDate: Date?
        var pausedRemaining: TimeInterval?
        var phaseDuration: TimeInterval
        var cycleCount: Int
        var pendingBreak: String?
        var workStartedAt: Date?
    }

    private static let snapshotKey = "timer.snapshot"

    private func schedulePersist() {
        guard isLive, !persistScheduled else { return }
        persistScheduled = true
        // Several properties change together; save once they've all landed.
        Task { @MainActor [weak self] in self?.persist() }
    }

    /// Saves the timer now. Call before the process exits.
    func persist() {
        persistScheduled = false
        guard isLive else { return }
        let snapshot = Snapshot(phase: phase.rawValue, endDate: endDate, pausedRemaining: pausedRemaining,
                                phaseDuration: phaseDuration, cycleCount: cycleCount,
                                pendingBreak: pendingBreak?.rawValue, workStartedAt: workStartedAt)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    /// Picks up where the previous run left off. Returns true if a focus
    /// session is still running, so its blocking and Focus should stay on.
    func restoreSession() -> Bool {
        guard isLive, let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
              let savedPhase = Phase(rawValue: saved.phase) else { return false }
        cycleCount = saved.cycleCount
        pendingBreak = saved.pendingBreak.flatMap(Phase.init(rawValue:))
        guard savedPhase != .idle else { return false }

        phase = savedPhase
        phaseDuration = saved.phaseDuration
        endDate = saved.endDate
        pausedRemaining = saved.pausedRemaining
        workStartedAt = saved.workStartedAt
        now = Date()
        if let endDate, now >= endDate {
            // It ran out while the app wasn't running. Only announce it if that was moments ago.
            finishPhase(completed: true, announce: now.timeIntervalSince(endDate) < 600)
            return false
        }
        return phase == .work
    }

    private func reloadStats() {
        today = DailyStats.load()
        week = DailyStats.lastSevenDays()
    }

    private func playSound(_ name: String) {
        if Prefs.playSound { NSSound(named: name)?.play() }
    }

    // MARK: Previews

    /// A frozen model for rendering snapshots of the UI.
    static func preview(
        phase: Phase, remaining: TimeInterval = 0, total: TimeInterval = 3000, paused: Bool = false,
        cycle: Int = 0, intention: String = "", pendingBreak: Phase? = nil, today: DailyStats, week: [DailyStats]
    ) -> TimerModel {
        let model = TimerModel(live: false)
        model.pendingBreak = pendingBreak
        model.phase = phase
        model.phaseDuration = total
        model.cycleCount = cycle
        model.intention = intention
        model.today = today
        model.week = week
        if phase != .idle {
            if paused { model.pausedRemaining = remaining } else { model.endDate = model.now.addingTimeInterval(remaining) }
        }
        return model
    }
}

/// Per-day totals, stored in UserDefaults keyed by date.
struct DailyStats: Codable, Identifiable {
    struct Entry: Codable, Hashable {
        var intention: String
        var seconds: TimeInterval
        var endedAt: Date
        var completed: Bool
    }

    var day: String
    var sessions = 0
    var focusSeconds: TimeInterval = 0
    var entries: [Entry] = []

    var id: String { day }

    init(day: String, sessions: Int = 0, focusSeconds: TimeInterval = 0, entries: [Entry] = []) {
        self.day = day
        self.sessions = sessions
        self.focusSeconds = focusSeconds
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        focusSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .focusSeconds) ?? 0
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
    }

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var todayKey: String { keyFormatter.string(from: Date()) }

    static func load(day: String = todayKey) -> DailyStats {
        if let data = UserDefaults.standard.data(forKey: "stats.\(day)"),
           let stats = try? JSONDecoder().decode(DailyStats.self, from: data) {
            return stats
        }
        return DailyStats(day: day)
    }

    /// Oldest first, ending with today.
    static func lastSevenDays() -> [DailyStats] {
        (0..<7).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return load(day: keyFormatter.string(from: date))
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "stats.\(day)")
        }
    }

    var weekdayInitial: String {
        guard let date = Self.keyFormatter.date(from: day) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
