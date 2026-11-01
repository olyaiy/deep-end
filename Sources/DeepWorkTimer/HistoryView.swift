import SwiftUI

/// Your focus history: one sentence on how it's going, a GitHub-style grid of
/// the last 26 weeks (shaded by progress toward the daily goal), and what you
/// actually worked on. Hovering a day swaps the list for that day's sessions.
struct HistoryView: View {
    /// Stats per day key ("yyyy-MM-dd"). Defaults to the saved stats.
    var days: [String: DailyStats]
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    @StateObject private var hover: HoveredDay

    /// `hovering` pre-selects a day (for design previews).
    init(days: [String: DailyStats] = DailyStats.history(days: HistoryView.weeks * 7), hovering: Date? = nil) {
        self.days = days
        let state = HoveredDay()
        if let hovering { state.day = DailyStats.key(for: hovering); state.date = hovering }
        _hover = StateObject(wrappedValue: state)
    }

    static let weeks = 26
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            insight
            VStack(alignment: .trailing, spacing: 8) {
                grid
                legend
            }
            Divider()
            detail
        }
        .padding(20)
        .frame(width: labelWidth + gap + CGFloat(Self.weeks) * (cell + gap) - gap + 40)
        .monospacedDigit()
    }

    // MARK: Insight

    /// The single most interesting thing about your recent focus, as a sentence.
    private var insight: some View {
        Group {
            switch insightKind {
            case .empty:
                Text("Your sessions will show up here.")
            case .keepStreak(let n):
                Text("Focus today to keep your \(bold("\(n)-day streak")).")
            case .bestWeekSince(let label):
                Text("\(bold(duration(week(0)))) in the last 7 days, your best week since \(label).")
            case .bestWeekYet:
                Text("\(bold(duration(week(0)))) in the last 7 days, your best week yet.")
            case .nearStreakRecord(let left, let best):
                Text("\(bold("\(left) more \(left == 1 ? "day" : "days")")) beats your longest streak of \(best).")
            case .versusLastWeek(let up, let percent):
                Text("\(bold(duration(week(0)))) in the last 7 days, \(up ? "up" : "down") \(percent)% on the week before.")
            case .plain:
                Text("\(bold(duration(week(0)))) in the last 7 days.")
            }
        }
        .font(.system(size: 13.5))
        .foregroundStyle(.secondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum Insight {
        case empty, keepStreak(Int), bestWeekSince(String), bestWeekYet
        case nearStreakRecord(left: Int, best: Int), versusLastWeek(up: Bool, percent: Int), plain
    }

    private var insightKind: Insight {
        guard days.values.contains(where: { $0.focusSeconds >= 60 }) else { return .empty }

        let streak = currentStreak
        if focus(onDaysAgo: 0) < 60, streak >= 2 { return .keepStreak(streak) }

        let thisWeek = week(0), lastWeek = week(1)
        if thisWeek > lastWeek, thisWeek >= 3600 {
            // The most recent earlier week that matched or beat this one.
            if let k = (2..<Self.weeks).first(where: { week($0) >= thisWeek }) {
                if k >= 4 { return .bestWeekSince(monthLabel(weeksAgo: k)) }
            } else if (1..<Self.weeks).filter({ week($0) > 0 }).count >= 3 {
                return .bestWeekYet
            }
        }

        let best = longestStreak
        if streak >= 3, best > streak, best - streak <= 3 { return .nearStreakRecord(left: best - streak + 1, best: best) }

        if lastWeek >= 3600 {
            let change = Int(((thisWeek - lastWeek) / lastWeek * 100).rounded())
            if abs(change) >= 10 { return .versusLastWeek(up: change > 0, percent: abs(change)) }
        }
        return .plain
    }

    private func bold(_ s: String) -> Text {
        Text(s).fontWeight(.semibold).foregroundStyle(.primary)
    }

    // MARK: Grid

    /// Columns of 7 days, oldest first. The last column ends today; days after
    /// today in that week are nil.
    private var columns: [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekdayIndex = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -(Self.weeks - 1) * 7 - weekdayIndex, to: today)!
        return (0..<Self.weeks).map { w in
            (0..<7).map { d in
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                return date <= today ? date : nil
            }
        }
    }

    private var grid: some View {
        let columns = self.columns
        return HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .leading, spacing: gap) {
                Color.clear.frame(width: labelWidth, height: 12)
                ForEach(0..<7, id: \.self) { row in
                    Text(weekdayLabel(row))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: labelWidth, height: cell, alignment: .leading)
                }
            }
            ForEach(columns.indices, id: \.self) { i in
                VStack(spacing: gap) {
                    Text(monthLabel(columns, i))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .frame(width: cell, height: 12, alignment: .leading)
                    ForEach(0..<7, id: \.self) { row in
                        if let date = columns[i][row] {
                            square(for: date)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func square(for date: Date) -> some View {
        let key = DailyStats.key(for: date)
        let seconds = days[key]?.focusSeconds ?? 0
        let isToday = Calendar.current.isDateInToday(date)
        let hovered = hover.day == key
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color(for: seconds))
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(hovered ? Color.primary.opacity(0.7) : (isToday ? Theme.red : .clear), lineWidth: 1.2)
            )
            .frame(width: cell, height: cell)
            .onHover { inside in
                if inside { hover.day = key; hover.date = date }
                else if hover.day == key { hover.day = nil }
            }
            .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(seconds >= 60 ? duration(seconds) : "no focus")")
    }

    /// Brightness tracks progress toward the daily goal, in four steps.
    private func color(for seconds: TimeInterval) -> Color {
        guard seconds >= 60 else { return Theme.track }
        let ratio = seconds / Double(max(1, goalMinutes * 60))
        let opacity: Double = switch ratio {
        case ..<0.25: 0.25
        case ..<0.5: 0.45
        case ..<1: 0.7
        default: 1
        }
        return Theme.red.opacity(opacity)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").padding(.trailing, 2)
            ForEach([0.0, 0.2, 0.4, 0.8, 1.2], id: \.self) { ratio in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color(for: ratio * Double(goalMinutes * 60)))
                    .frame(width: 10, height: 10)
            }
            Text("More").padding(.leading, 2)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private func monthLabel(_ columns: [[Date?]], _ i: Int) -> String {
        guard i < columns.count - 1, let first = columns[i].compactMap({ $0 }).first else { return "" }
        let cal = Calendar.current
        let month = cal.component(.month, from: first)
        if i > 0, let prev = columns[i - 1].compactMap({ $0 }).first, cal.component(.month, from: prev) == month { return "" }
        // No label squeezed into the first column when the month changes right after.
        if i == 0, let next = columns[1].compactMap({ $0 }).first, cal.component(.month, from: next) != month { return "" }
        return first.formatted(.dateTime.month(.abbreviated))
    }

    private func weekdayLabel(_ row: Int) -> String {
        guard row % 2 == 1 else { return "" }
        let cal = Calendar.current
        return String(cal.shortWeekdaySymbols[(row + cal.firstWeekday - 1) % 7].prefix(3))
    }

    // MARK: Detail

    /// What you worked on this week, or the hovered day's sessions.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let key = hover.day, let date = hover.date {
                let stats = days[key]
                let total = stats?.focusSeconds ?? 0
                sectionHeader(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                              trailing: total >= 60 ? duration(total) : nil)
                let entries = (stats?.entries ?? []).sorted { $0.endedAt < $1.endedAt }
                if entries.isEmpty {
                    placeholder(total >= 60 ? "Session details weren't saved for this day." : "No focus sessions this day.")
                } else {
                    ForEach(Array(entries.prefix(Self.detailRows).enumerated()), id: \.offset) { _, entry in
                        sessionRow(entry)
                    }
                    if entries.count > Self.detailRows { more(entries.count - Self.detailRows) }
                }
            } else {
                let items = workedOn
                sectionHeader("This week", trailing: week(0) >= 60 ? duration(week(0)) : nil)
                if items.isEmpty {
                    placeholder("No sessions in the last 7 days.")
                } else {
                    let top = items.first?.seconds ?? 1
                    ForEach(items.prefix(Self.detailRows), id: \.name) { item in
                        topicRow(item.name, seconds: item.seconds, fraction: item.seconds / top)
                    }
                    if items.count > Self.detailRows { more(items.count - Self.detailRows) }
                }
            }
        }
        // Keep the panel from jumping as you move across days.
        .frame(minHeight: 16 + CGFloat(Self.detailRows) * 26 + 14, alignment: .top)
    }

    private static let detailRows = 4

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .frame(height: 16)
    }

    private func topicRow(_ name: String, seconds: TimeInterval, fraction: Double) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.redGradient).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(width: 110, height: 5)
            Text(duration(seconds))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .frame(height: 16)
    }

    private func sessionRow(_ entry: DailyStats.Entry) -> some View {
        let start = entry.endedAt.addingTimeInterval(-entry.seconds)
        return HStack(spacing: 12) {
            Text(start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(entry.intention.isEmpty ? "Untitled session" : entry.intention)
                .font(.system(size: 12.5))
                .foregroundStyle(entry.intention.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(duration(entry.seconds))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Image(systemName: entry.completed ? "checkmark.circle.fill" : "stop.circle")
                .font(.system(size: 11))
                .foregroundStyle(entry.completed ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.tertiary))
                .help(entry.completed ? "Finished" : "Ended early")
        }
        .frame(height: 16)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
    }

    private func more(_ n: Int) -> some View {
        Text("+\(n) more").font(.system(size: 11)).foregroundStyle(.tertiary)
    }

    /// Session names from the last 7 days, most time first. Names are matched
    /// ignoring case and surrounding spaces; unnamed sessions are grouped.
    private var workedOn: [(name: String, seconds: TimeInterval)] {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for offset in 0..<7 {
            for entry in day(offsetBack: offset)?.entries ?? [] {
                let trimmed = entry.intention.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = trimmed.isEmpty ? "Untitled sessions" : trimmed
                let key = name.lowercased()
                totals[key] = (totals[key]?.name ?? name, (totals[key]?.seconds ?? 0) + entry.seconds)
            }
        }
        return totals.values.sorted { $0.seconds > $1.seconds }
    }

    // MARK: Numbers

    private func day(offsetBack offset: Int) -> DailyStats? {
        guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
        return days[DailyStats.key(for: date)]
    }

    private func focus(onDaysAgo offset: Int) -> TimeInterval { day(offsetBack: offset)?.focusSeconds ?? 0 }

    /// Total for the 7 days ending `k` weeks ago (k = 0: the last 7 days).
    private func week(_ k: Int) -> TimeInterval {
        (0..<7).reduce(0) { $0 + focus(onDaysAgo: k * 7 + $1) }
    }

    private func monthLabel(weeksAgo k: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -k * 7, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.wide))
    }

    /// Days in a row with some focus, ending today (or yesterday, so an
    /// unstarted today doesn't break it).
    private var currentStreak: Int {
        var offset = focus(onDaysAgo: 0) >= 60 ? 0 : 1
        var count = 0
        while offset < Self.weeks * 7, focus(onDaysAgo: offset) >= 60 {
            count += 1
            offset += 1
        }
        return count
    }

    private var longestStreak: Int {
        var best = 0, run = 0
        for offset in (0..<(Self.weeks * 7)).reversed() {
            run = focus(onDaysAgo: offset) >= 60 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    private func duration(_ seconds: TimeInterval) -> String { DailyStats.durationText(seconds) }
}

final class HoveredDay: ObservableObject {
    @Published var day: String?
    @Published var date: Date?
}

extension DailyStats {
    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    /// Saved stats for the last `days` days, including today. Days with nothing saved are left out.
    static func history(days: Int) -> [String: DailyStats] {
        var out: [String: DailyStats] = [:]
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let stats = load(day: key(for: date))
            if stats.focusSeconds > 0 || !stats.entries.isEmpty { out[stats.day] = stats }
        }
        return out
    }
}
