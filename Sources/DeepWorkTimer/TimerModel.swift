import AppKit
import UserNotifications

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
}

@MainActor
final class TimerModel: ObservableObject {
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var now = Date()
    @Published private(set) var today = DailyStats.loadToday()
    /// Completed work sessions since the last long break.
    @Published private(set) var cycleCount = 0

    // The timer stores an end date rather than counting ticks, so it stays
    // accurate across sleep/wake and doesn't drift.
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    private var phaseDuration: TimeInterval = 1
    private var workStartedAt: Date?

    private var ticker: Task<Void, Never>?

    init() {
        // If we crashed mid-session last time, put the wallpaper and Focus back.
        SessionEffects.shared.revert()
        requestNotificationPermission()
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

    var displayTime: String {
        let total = Int(remaining.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Which session number in the current cycle we're on (1-based).
    var sessionNumber: Int { cycleCount + (phase == .work ? 1 : 0) }

    // MARK: Actions

    func startWork() {
        workStartedAt = Date()
        begin(.work, minutes: Prefs.workMinutes)
        SessionEffects.shared.apply()
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

    /// End the current phase early and move to the next one.
    func skip() {
        finishPhase(completed: false)
    }

    /// Stop everything and go back to idle.
    func stop() {
        if phase == .work {
            recordFocusTime()
            SessionEffects.shared.revert()
        }
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
        if today.day != DailyStats.todayKey { today = DailyStats.loadToday() }
        if let endDate, now >= endDate {
            finishPhase(completed: true)
        }
    }

    private func finishPhase(completed: Bool) {
        switch phase {
        case .idle:
            return

        case .work:
            recordFocusTime()
            SessionEffects.shared.revert()
            if completed {
                today.sessions += 1
                today.save()
                cycleCount += 1
                alert(title: "Session done", body: "Nice work. Time for a break.")
            }
            if cycleCount >= Prefs.sessionsPerLongBreak {
                cycleCount = 0
                begin(.longBreak, minutes: Prefs.longBreakMinutes)
            } else {
                begin(.shortBreak, minutes: Prefs.shortBreakMinutes)
            }

        case .shortBreak, .longBreak:
            if completed {
                alert(title: "Break's over", body: "Ready for the next session?")
            }
            reset()
        }
    }

    private func recordFocusTime() {
        guard let start = workStartedAt else { return }
        // Planned minus remaining excludes paused time; cap at wall-clock time as a sanity check.
        let elapsed = min(phaseDuration - remaining, Date().timeIntervalSince(start))
        today.focusSeconds += max(0, elapsed)
        today.save()
        workStartedAt = nil
    }

    // MARK: Alerts

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func alert(title: String, body: String) {
        if Prefs.playSound { NSSound(named: "Glass")?.play() }
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Per-day totals, stored in UserDefaults keyed by date.
struct DailyStats: Codable {
    var day: String
    var sessions = 0
    var focusSeconds: TimeInterval = 0

    static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func loadToday() -> DailyStats {
        let key = todayKey
        if let data = UserDefaults.standard.data(forKey: "stats.\(key)"),
           let stats = try? JSONDecoder().decode(DailyStats.self, from: data) {
            return stats
        }
        return DailyStats(day: key)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "stats.\(day)")
        }
    }

    var focusText: String {
        let minutes = Int(focusSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
