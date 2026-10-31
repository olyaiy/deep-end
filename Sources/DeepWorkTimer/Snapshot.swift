import SwiftUI

/// Sample states for checking the design without clicking through the menu bar.
///
///   DeepWorkTimer --preview           opens a window showing every state live
///                                     (the only way to see Liquid Glass, which
///                                     the system compositor draws)
///   DeepWorkTimer --snapshot <dir>    renders states to PNGs and exits
///                                     (no glass; native controls are placeholders)
@MainActor
enum DesignPreview {
    static var previewRequested: Bool { CommandLine.arguments.contains("--preview") }

    private static func scenarios() -> [(String, TimerModel)] {
        let now = Date()
        let today = DailyStats(day: DailyStats.todayKey, sessions: 2, focusSeconds: 6900, entries: [
            .init(intention: "Outline the Q4 planning doc", seconds: 3000, endedAt: now.addingTimeInterval(-9000), completed: true),
            .init(intention: "Refactor auth middleware", seconds: 3000, endedAt: now.addingTimeInterval(-1800), completed: true),
        ])
        let week = [today]
        return [
            ("idle", .preview(phase: .idle, cycle: 2, today: today, week: week)),
            ("work", .preview(phase: .work, remaining: 1884, total: 3000, cycle: 2,
                              intention: "Write the Q4 planning doc", today: today, week: week)),
            ("paused", .preview(phase: .work, remaining: 1203, total: 3000, paused: true, cycle: 2,
                                intention: "Write the Q4 planning doc", today: today, week: week)),
            ("break", .preview(phase: .shortBreak, remaining: 412, total: 600, cycle: 1, today: today, week: week)),
        ]
    }

    // MARK: --preview

    private static var window: NSWindow?

    static func showWindow() {
        NSApp.setActivationPolicy(.regular)
        let models = scenarios()
        func column(_ scheme: ColorScheme) -> some View {
            VStack(spacing: 18) {
                ForEach(models.indices, id: \.self) { popover(models[$0].1) }
                ToastView(transition: .workDone(breakMinutes: 10, longBreak: false))
            }
            .padding(24)
            .background(scheme == .dark ? Color(white: 0.1) : Color(white: 0.9))
            .environment(\.colorScheme, scheme)
        }
        let content = HStack(spacing: 0) {
            column(.light)
            column(.dark)
        }

        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Deep Work Timer — Design Preview"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        NSLog("DWT preview window size: %@ visible: %d", NSStringFromSize(hosting.fittingSize), window.isVisible ? 1 : 0)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Mimics the menu bar popover's rounded window around the content.
    private static func popover(_ model: TimerModel) -> some View {
        MenuContentView()
            .environmentObject(model)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    // MARK: --snapshot

    static func snapshotIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var views: [(String, AnyView)] = scenarios().map { name, model in
            (name, AnyView(MenuContentView().environmentObject(model)))
        }
        views.append(("toast", AnyView(ToastView(transition: .workDone(breakMinutes: 10, longBreak: false)))))

        for (name, view) in views {
            let renderer = ImageRenderer(content: view.background(Color.white).environment(\.colorScheme, .light))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { continue }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name).png"))
        }
        print("Snapshots written to \(dir.path)")
        exit(0)
    }
}
