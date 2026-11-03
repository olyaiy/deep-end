import SwiftUI

/// Screenshots for the README, captured from real on-screen windows so glass,
/// materials and native controls look exactly as they do in the app.
///
///   DeepWorkTimer --showcase <dir>    captures every scene, light and dark, and exits
///
/// Runs on sample data; never touches your settings, Focus or wallpaper.
@MainActor
enum Showcase {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--showcase"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Sample history and music, in memory only (the registration domain is never saved).
        let history = DesignPreview.sampleHistory()
        var defaults: [String: Any] = [:]
        for (day, stats) in history {
            if let data = try? JSONEncoder().encode(stats) { defaults["stats.\(day)"] = data }
        }
        UserDefaults.standard.register(defaults: defaults)
        MusicController.shared.preview(track: sampleTrack, playing: true)
        let jobs = scenes.flatMap { scene in [ColorScheme.light, .dark].map { (scene, $0) } }
        DispatchQueue.main.async { capture(jobs[...], into: dir) }
        app.run()
    }

    private struct Scene {
        let name: String
        let size: CGSize
        let view: (ColorScheme) -> AnyView
    }

    /// Opens each scene in turn, waits for it to draw, and screenshots its window.
    private static func capture(_ jobs: ArraySlice<(Scene, ColorScheme)>, into dir: URL) {
        guard let (scene, scheme) = jobs.first else {
            print("Showcase written to \(dir.path)")
            exit(0)
        }
        UserDefaults.standard.register(defaults: [Prefs.Key.appearance: scheme == .dark ? Appearance.dark.rawValue : Appearance.light.rawValue])

        let window = ActiveLookingWindow(contentRect: NSRect(origin: .zero, size: scene.size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: scene.view(scheme)
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .key))
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let file = dir.appendingPathComponent("\(scene.name)-\(scheme == .dark ? "dark" : "light").png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l\(window.windowNumber)", file.path]
            try? process.run()
            process.waitUntilExit()
            window.orderOut(nil)
            capture(jobs.dropFirst(), into: dir)
        }
    }

    // MARK: Scenes

    private static var scenes: [Scene] {
        let models = Dictionary(uniqueKeysWithValues: sampleModels())
        let history = DailyStats.history(days: HistoryView.weeks * 7)
        return [
            Scene(name: "hero", size: CGSize(width: 1000, height: 340)) { scheme in
                AnyView(Desktop(scheme: scheme) {
                    VStack(alignment: .trailing, spacing: 6) {
                        MenuBar(timeText: "31:24", remaining: 0.63)
                        Popover { MenuContentView().environmentObject(models["work"]!) }
                            .padding(.trailing, 100)
                        Spacer(minLength: 0)
                    }
                })
            },
            Scene(name: "states", size: CGSize(width: 1376, height: 400)) { scheme in
                AnyView(Desktop(scheme: scheme) {
                    HStack(alignment: .top, spacing: 36) {
                        ForEach(["idle", "work", "break-ready"], id: \.self) { name in
                            Popover { MenuContentView().environmentObject(models[name]!) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                })
            },
            Scene(name: "blocking", size: CGSize(width: 900, height: 620)) { scheme in
                AnyView(Desktop(scheme: scheme) {
                    HStack(alignment: .top, spacing: 28) {
                        Popover { MenuContentView().environmentObject(models["idle"]!) }
                        Popover { BlockPickerView() }
                    }
                    .frame(maxHeight: .infinity)
                })
            },
            Scene(name: "history", size: CGSize(width: 900, height: 560)) { scheme in
                AnyView(Desktop(scheme: scheme) {
                    HStack(alignment: .top, spacing: 28) {
                        Popover { HistoryView(days: history) }
                        Popover { QuickSettingsView() }
                    }
                    .frame(maxHeight: .infinity)
                })
            },
            Scene(name: "music", size: CGSize(width: 900, height: 360)) { scheme in
                AnyView(Desktop(scheme: scheme) {
                    HStack(alignment: .top, spacing: 28) {
                        Popover { MenuContentView().environmentObject(models["work"]!) }
                        Popover { MenuContentView(musicExpanded: true).environmentObject(models["work"]!) }
                    }
                    .frame(maxHeight: .infinity)
                })
            },
        ]
    }

    private static func sampleModels() -> [(String, TimerModel)] {
        let now = Date()
        let today = DailyStats(day: DailyStats.todayKey, sessions: 2, focusSeconds: 6000, entries: [
            .init(intention: "Outline the Q4 planning doc", seconds: 3000, endedAt: now.addingTimeInterval(-9000), completed: true),
            .init(intention: "Refactor auth middleware", seconds: 3000, endedAt: now.addingTimeInterval(-1800), completed: true),
        ])
        return [
            ("idle", .preview(phase: .idle, cycle: 2, today: today, week: [today])),
            ("work", .preview(phase: .work, remaining: 1884, total: 3000, cycle: 2,
                              intention: "Write the Q4 planning doc", today: today, week: [today])),
            ("break-ready", .preview(phase: .idle, cycle: 2, intention: "Write the Q4 planning doc",
                                     pendingBreak: .shortBreak, today: today, week: [today])),
        ]
    }

    private static var sampleTrack: MusicController.Track {
        MusicController.Track(title: "Weightless", artist: "Marconi Union", artworkURL: sampleArtwork())
    }

    /// A stand-in album cover, so the screenshots don't show anyone's real artwork.
    private static func sampleArtwork() -> URL? {
        let size = NSSize(width: 120, height: 120)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.62, green: 0.71, blue: 0.84, alpha: 1),
                                NSColor(red: 0.36, green: 0.44, blue: 0.60, alpha: 1),
                                NSColor(red: 0.18, green: 0.23, blue: 0.36, alpha: 1)])?
                .draw(in: rect, angle: -50)
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deep-end-artwork.png")
        try? png.write(to: url)
        return url
    }
}

// MARK: Pieces

/// Draws its controls as if focused (switches tinted, not grey) without taking
/// the keyboard from whatever you're doing while the screenshots run.
private final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// A soft, wallpaper-like backdrop.
private struct Desktop<Content: View>: View {
    let scheme: ColorScheme
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 0.47, green: 0.16, blue: 0.27).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.18, y: 0.25), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.55).opacity(0.5), .clear],
                               center: UnitPoint(x: 0.85, y: 0.75), startRadius: 0, endRadius: 560)
            } else {
                Color(red: 0.93, green: 0.94, blue: 0.96)
                RadialGradient(colors: [Color(red: 1, green: 0.82, blue: 0.78), .clear],
                               center: UnitPoint(x: 0.15, y: 0.2), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Color(red: 0.85, green: 0.88, blue: 1), .clear],
                               center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.82), .clear],
                               center: UnitPoint(x: 0.5, y: 1.15), startRadius: 0, endRadius: 600)
            }
            content
        }
    }
}

/// The menu bar window's look: popover material, rounded, with a shadow.
private struct Popover<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
    }
}

/// A stand-in menu bar with the timer's item open.
private struct MenuBar: View {
    let timeText: String
    let remaining: Double

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Spacer()
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.ring(remaining: remaining, paused: false))
                Text(timeText).monospacedDigit()
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(0.12)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text("Tue Nov 3  10:42")
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 18)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
