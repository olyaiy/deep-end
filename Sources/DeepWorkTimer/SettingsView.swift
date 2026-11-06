import ServiceManagement
import SwiftUI

/// A standard macOS settings window, opened from the gear in the popover.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Deep End"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 460, height: 600))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.shortBreakMinutes) private var shortBreakMinutes = 10
    @AppStorage(Prefs.Key.longBreakMinutes) private var longBreakMinutes = 20
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var dailyGoalMinutes = 240
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @AppStorage(Prefs.Key.hideDesktopIcons) private var hideDesktopIcons = false
    @AppStorage(Prefs.Key.focusMode) private var focusMode = FocusController.doNotDisturb
    @AppStorage(Prefs.Key.musicEnabled) private var musicEnabled = true
    @AppStorage(Prefs.Key.musicSource) private var musicSource = MusicController.Source.spotify.rawValue
    @AppStorage(Prefs.Key.musicOnStart) private var musicOnStart = MusicController.OnStart.nothing.rawValue
    @AppStorage(Prefs.Key.focusPlaylist) private var focusPlaylist = ""
    @AppStorage(Prefs.Key.pauseMusicOnBreak) private var pauseMusicOnBreak = true
    @AppStorage(Prefs.Key.wallpaperPath) private var wallpaperPath = ""
    @AppStorage(Prefs.Key.playSound) private var playSound = true
    @AppStorage(Prefs.Key.showTimeInMenuBar) private var showTimeInMenuBar = true

    @StateObject private var state = SettingsState()
    @ObservedObject private var focus = FocusController.shared

    var body: some View {
        Form {
            Section("History") {
                HistoryView()
                    .padding(-16)
                    .padding(.vertical, 4)
            }

            Section("Timer") {
                stepper("Focus", value: $workMinutes, in: 5...Prefs.maxWorkMinutes, step: 5) { "\($0) min" }
                stepper("Short break", value: $shortBreakMinutes, in: 1...60) { "\($0) min" }
                stepper("Long break", value: $longBreakMinutes, in: 5...90, step: 5) { "\($0) min" }
                stepper("Long break after", value: $sessionsPerLongBreak, in: 1...8) { $0 == 1 ? "1 session" : "\($0) sessions" }
                stepper("Daily goal", value: $dailyGoalMinutes, in: 30...720, step: 30) { DailyStats.durationText(TimeInterval($0 * 60)) }
            }

            Section {
                Toggle("Turn on Focus and change wallpaper", isOn: $effectsEnabled)
                if effectsEnabled {
                    Picker("Focus mode", selection: $focusMode) {
                        ForEach(focus.modes) { Text($0.name).tag($0.id) }
                        if !focus.modes.contains(where: { $0.id == focusMode }) {
                            Text(focusMode).tag(focusMode)
                        }
                    }
                    focusStatus
                    LabeledContent("Wallpaper") {
                        HStack(spacing: 10) {
                            if let thumbnail = WallpaperThumbnail.image(for: Prefs.wallpaperURL ?? DefaultWallpaper.url()) {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 52, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                                    .id(wallpaperPath)
                            }
                            Button("Choose…", action: chooseWallpaper)
                            if !wallpaperPath.isEmpty {
                                Button("Use Default") { wallpaperPath = "" }
                            }
                        }
                    }
                }
                Toggle("Hide desktop icons", isOn: $hideDesktopIcons)
            } header: {
                Text("During Focus")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if effectsEnabled {
                        Text("Only the Focus the timer turned on is switched off afterwards; one you set yourself is left alone.")
                    }
                    if hideDesktopIcons {
                        Text("Hiding and showing the icons restarts Finder; its open windows come back on their own.")
                    }
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show music controls", isOn: $musicEnabled)
                Picker("Control", selection: $musicSource) {
                    ForEach(MusicController.Source.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Picker("When a session starts", selection: $musicOnStart) {
                    ForEach(MusicController.OnStart.allCases, id: \.rawValue) { option in
                        if option != .playlist || musicSource == MusicController.Source.spotify.rawValue {
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                }
                if musicSource == MusicController.Source.spotify.rawValue {
                    LabeledContent("Focus playlist") {
                        HStack(spacing: 6) {
                            TextField("Paste a Spotify link", text: $focusPlaylist)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                            if !focusPlaylist.isEmpty {
                                Image(systemName: MusicController.spotifyURI(from: focusPlaylist) != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(MusicController.spotifyURI(from: focusPlaylist) != nil ? .green : .orange)
                                    .help(MusicController.spotifyURI(from: focusPlaylist) != nil ? "Looks good" : "That isn't a Spotify link")
                            }
                        }
                    }
                }
                Toggle("Pause music when a session ends", isOn: $pauseMusicOnBreak)
            } header: {
                Text("Music")
            } footer: {
                Text(musicFooter).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Play a sound when a session or break ends", isOn: $playSound)
                Toggle("Show time in menu bar", isOn: $showTimeInMenuBar)
                Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            }

            Section {
                LabeledContent("Control from anywhere") {
                    Text("deepwork://start · pause · stop")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Quit Deep End") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.red)
        .frame(width: 460)
        .frame(minHeight: 560)
        .onAppear { focus.refresh() }
    }

    private func stepper(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
                         format: @escaping (Int) -> String) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title) {
                Text(format(value.wrappedValue)).monospacedDigit()
            }
        }
    }

    private var musicFooter: String {
        if musicSource == MusicController.Source.spotify.rawValue {
            return MusicController.shared.spotifyInstalled
                ? "In Spotify, use Share › Copy link to playlist (or album), then paste it here."
                : "Spotify isn't installed, so the controls work whatever app is playing."
        }
        return "Play, pause and skip whatever is playing: Music, a browser, podcasts…"
    }

    /// Whether the Focus helper can do its job, and how to fix it if not.
    @ViewBuilder
    private var focusStatus: some View {
        switch focus.state {
        case .checking:
            LabeledContent("Focus control") { ProgressView().controlSize(.small) }
        case .ready:
            LabeledContent("Focus control") {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .needsAccess:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Focus control") {
                    Label("Needs Full Disk Access", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text("Click Open Settings, then drag “Deep Work Focus” from the Finder window into the Full Disk Access list and switch it on. It's a small helper that only switches Focus modes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Settings") { focus.openFullDiskAccessSettings() }
                    Button("Check Again") { focus.refresh() }
                }
            }
        case .missingHelper:
            LabeledContent("Focus control") {
                Text("Helper not installed. Run build.sh.").foregroundStyle(.secondary)
            }
        case .failed(let message):
            LabeledContent("Focus control") {
                HStack {
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                    Button("Retry") { focus.refresh() }
                }
            }
        }
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a wallpaper for focus sessions"
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperPath = url.path
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Small cached thumbnails so settings doesn't decode a 4K image on every render.
@MainActor
enum WallpaperThumbnail {
    private static var cache: [String: NSImage] = [:]

    static func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let cached = cache[url.path] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[url.path] = image
        return image
    }
}
