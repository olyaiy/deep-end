import SwiftUI

/// `DeepWorkTimer --snapshot <dir>` renders each screen to PNGs
/// and exits. Handy for checking the design without clicking through the menu bar.
/// Note: AppKit-backed controls (text fields, menus) render as placeholders.
@MainActor
enum Snapshotter {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let now = Date()
        let today = DailyStats(day: DailyStats.todayKey, sessions: 2, focusSeconds: 6900, entries: [
            .init(intention: "Outline the Q4 planning doc", seconds: 3000, endedAt: now.addingTimeInterval(-9000), completed: true),
            .init(intention: "", seconds: 900, endedAt: now.addingTimeInterval(-5400), completed: false),
            .init(intention: "Refactor auth middleware", seconds: 3000, endedAt: now.addingTimeInterval(-1800), completed: true),
        ])
        let pastMinutes = [180, 95, 0, 240, 150, 60]
        let week = pastMinutes.enumerated().map { offset, minutes in
            let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: now)!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return DailyStats(day: f.string(from: date), focusSeconds: TimeInterval(minutes * 60))
        } + [today]

        func screen(_ model: TimerModel) -> AnyView {
            AnyView(MenuContentView().environmentObject(model))
        }

        let scenarios: [(String, AnyView)] = [
            ("1-idle", screen(.preview(phase: .idle, cycle: 2, today: today, week: week))),
            ("2-work", screen(.preview(phase: .work, remaining: 1884, total: 3000, cycle: 2,
                                       intention: "Write the Q4 planning doc", today: today, week: week))),
            ("3-paused", screen(.preview(phase: .work, remaining: 1203, total: 3000, paused: true, cycle: 2,
                                         intention: "Write the Q4 planning doc", today: today, week: week))),
            ("4-short-break", screen(.preview(phase: .shortBreak, remaining: 412, total: 600, cycle: 1, today: today, week: week))),
            ("5-long-break", screen(.preview(phase: .longBreak, remaining: 950, total: 1200, today: today, week: week))),
            ("6-toast", AnyView(ToastView(transition: .workDone(breakMinutes: 10, longBreak: false)))),
        ]

        for scheme in [ColorScheme.light] {
            for (name, view) in scenarios {
                let content = view
                    .background(Color(white: 0.93))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let cg = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let file = dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        print("Snapshots written to \(dir.path)")
        exit(0)
    }
}
