import SwiftUI

/// GitHub-style grid of the last 26 weeks: one square per day, brighter the
/// closer you got to your daily goal. Hover a day for its total.
struct HistoryView: View {
    /// Seconds of focus per day key ("yyyy-MM-dd"). Defaults to the saved stats.
    var history: [String: TimeInterval] = DailyStats.history(days: HistoryView.weeks * 7)
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var goalMinutes = 240
    @StateObject private var hover = HoveredDay()

    static let weeks = 26
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            grid
            footer
        }
        .padding(16)
        .fixedSize()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            stat(DailyStats.durationText(total(lastDays: 7)), "Last 7 days")
            stat(streak == 1 ? "1 day" : "\(streak) days", "Streak")
            stat(DailyStats.durationText(history.values.max() ?? 0), "Best day")
            stat("\(goalDays)", "Goals hit")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
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
        return VStack(alignment: .leading, spacing: 4) {
            // Month labels over the first column of each month.
            HStack(spacing: gap) {
                Color.clear.frame(width: 24, height: 1)
                ForEach(columns.indices, id: \.self) { i in
                    Text(monthLabel(columns, i))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdayLabel(row))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: cell, alignment: .leading)
                    }
                }
                ForEach(columns.indices, id: \.self) { i in
                    VStack(spacing: gap) {
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
    }

    private func square(for date: Date) -> some View {
        let key = DailyStats.key(for: date)
        let seconds = history[key] ?? 0
        let isToday = Calendar.current.isDateInToday(date)
        let hovered = hover.day == key
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color(for: seconds))
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(hovered ? Color.primary.opacity(0.6) : (isToday ? Theme.red.opacity(0.7) : .clear), lineWidth: 1)
            )
            .frame(width: cell, height: cell)
            .scaleEffect(hovered ? 1.25 : 1)
            .animation(Theme.spring, value: hovered)
            .onHover { inside in
                if inside { hover.day = key; hover.date = date; hover.seconds = seconds }
                else if hover.day == key { hover.day = nil }
            }
            .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(DailyStats.durationText(seconds))")
    }

    /// Brightness tracks progress toward the daily goal, in five steps.
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

    private func monthLabel(_ columns: [[Date?]], _ i: Int) -> String {
        guard let first = columns[i].compactMap({ $0 }).first else { return "" }
        let cal = Calendar.current
        let month = cal.component(.month, from: first)
        if i > 0, let prev = columns[i - 1].compactMap({ $0 }).first, cal.component(.month, from: prev) == month { return "" }
        // Skip a label squeezed into the very first column if the month changes right after.
        if i == 0, let next = columns[safe: 1]?.compactMap({ $0 }).first, cal.component(.month, from: next) != month { return "" }
        return first.formatted(.dateTime.month(.abbreviated))
    }

    private func weekdayLabel(_ row: Int) -> String {
        guard row % 2 == 1 else { return "" }
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols
        return String(symbols[(row + cal.firstWeekday - 1) % 7].prefix(3))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Group {
                if let day = hover.day, let date = hover.date, history[day] != nil || hover.seconds == 0 {
                    let amount = Text(hover.seconds >= 60 ? DailyStats.durationText(hover.seconds) : "no focus").bold()
                    Text("\(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())): \(amount)")
                } else {
                    Text("\(DailyStats.durationText(history.values.reduce(0, +))) in the last \(Self.weeks) weeks")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            Spacer(minLength: 12)
            Text("Less").font(.system(size: 9.5)).foregroundStyle(.secondary)
            ForEach([0.0, 0.2, 0.4, 0.8, 1.2], id: \.self) { ratio in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color(for: ratio * Double(goalMinutes * 60)))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: Numbers

    private func total(lastDays n: Int) -> TimeInterval {
        (0..<n).reduce(0) { sum, offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            return sum + (history[DailyStats.key(for: date)] ?? 0)
        }
    }

    /// Days in a row with some focus, ending today (or yesterday, so an
    /// unstarted today doesn't break it).
    private var streak: Int {
        let cal = Calendar.current
        var offset = (history[DailyStats.key(for: Date())] ?? 0) >= 60 ? 0 : 1
        var count = 0
        while let date = cal.date(byAdding: .day, value: -offset, to: Date()), (history[DailyStats.key(for: date)] ?? 0) >= 60 {
            count += 1
            offset += 1
        }
        return count
    }

    private var goalDays: Int {
        history.values.filter { $0 >= Double(goalMinutes * 60) }.count
    }
}

final class HoveredDay: ObservableObject {
    @Published var day: String?
    @Published var date: Date?
    @Published var seconds: TimeInterval = 0
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension DailyStats {
    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    /// Focus seconds per day for the last `days` days, including today.
    static func history(days: Int) -> [String: TimeInterval] {
        var out: [String: TimeInterval] = [:]
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = key(for: date)
            let seconds = load(day: key).focusSeconds
            if seconds > 0 { out[key] = seconds }
        }
        return out
    }
}
