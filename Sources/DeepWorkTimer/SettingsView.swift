import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let done: () -> Void

    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.shortBreakMinutes) private var shortBreakMinutes = 10
    @AppStorage(Prefs.Key.longBreakMinutes) private var longBreakMinutes = 20
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var dailyGoalMinutes = 240
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @AppStorage(Prefs.Key.focusOnShortcut) private var focusOnShortcut = "Deep Work On"
    @AppStorage(Prefs.Key.focusOffShortcut) private var focusOffShortcut = "Deep Work Off"
    @AppStorage(Prefs.Key.wallpaperPath) private var wallpaperPath = ""
    @AppStorage(Prefs.Key.playSound) private var playSound = true
    @AppStorage(Prefs.Key.showTimeInMenuBar) private var showTimeInMenuBar = true

    @StateObject private var state = SettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            group("Timer") {
                row("Focus", icon: "brain.head.profile") {
                    ValueStepper(value: $workMinutes, range: 5...Prefs.maxWorkMinutes, step: 5) { "\($0) min" }
                }
                row("Short break", icon: "cup.and.saucer") {
                    ValueStepper(value: $shortBreakMinutes, range: 1...60) { "\($0) min" }
                }
                row("Long break", icon: "figure.walk") {
                    ValueStepper(value: $longBreakMinutes, range: 5...90, step: 5) { "\($0) min" }
                }
                row("Long break after", icon: "repeat") {
                    ValueStepper(value: $sessionsPerLongBreak, range: 1...8) { "\($0) \($0 == 1 ? "session" : "sessions")" }
                }
                row("Daily goal", icon: "target") {
                    ValueStepper(value: $dailyGoalMinutes, range: 30...720, step: 30) { DailyStats.durationText(TimeInterval($0 * 60)) }
                }
            }

            group("During focus") {
                Toggle(isOn: $effectsEnabled.animation(.snappy)) {
                    label("Focus mode & wallpaper", icon: "moon.stars")
                }
                .toggleStyle(SwitchStyle())
                .padding(.vertical, 2)

                if effectsEnabled {
                    row("Turn on with", icon: "bolt") { shortcutMenu($focusOnShortcut) }
                    row("Turn off with", icon: "bolt.slash") { shortcutMenu($focusOffShortcut) }
                    if !state.shortcuts.isEmpty, missingShortcut {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Phase.longBreak.tint)
                            Text("That shortcut doesn't exist yet. In Shortcuts, make one with a “Set Focus” action.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 2)
                    }
                    wallpaperRow
                }
            }

            group("General") {
                Toggle(isOn: $playSound) { label("Sound when a phase ends", icon: "speaker.wave.2") }
                    .toggleStyle(SwitchStyle())
                Toggle(isOn: $showTimeInMenuBar) { label("Time in menu bar", icon: "menubar.rectangle") }
                    .toggleStyle(SwitchStyle())
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })) {
                    label("Launch at login", icon: "power")
                }
                .toggleStyle(SwitchStyle())
            }

            HStack(spacing: 6) {
                Image(systemName: "link")
                Text("Control from anywhere: deepwork://start, pause, stop, add")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        }
        .task { state.shortcuts = await ShortcutRunner.list() }
    }

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
            HStack {
                Button(action: done) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title: title).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .card(padding: 12)
        }
    }

    private func row<Control: View>(_ title: String, icon: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            label(title, icon: icon)
            Spacer(minLength: 8)
            control()
        }
    }

    private func label(_ title: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Phase.work.gradient)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
        }
    }

    private var missingShortcut: Bool {
        [focusOnShortcut, focusOffShortcut].contains { !$0.isEmpty && !state.shortcuts.contains($0) }
    }

    private func shortcutMenu(_ selection: Binding<String>) -> some View {
        // Keep the current value selectable even if the shortcut doesn't exist yet.
        let options = Array(Set(state.shortcuts + [selection.wrappedValue]).subtracting([""]))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Menu {
            Button("None") { selection.wrappedValue = "" }
            Divider()
            ForEach(options, id: \.self) { name in
                Button {
                    selection.wrappedValue = name
                } label: {
                    if name == selection.wrappedValue { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            Text(selection.wrappedValue.isEmpty ? "None" : selection.wrappedValue)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var wallpaperRow: some View {
        HStack {
            label("Wallpaper", icon: "photo")
            Spacer(minLength: 8)
            if let thumbnail = WallpaperThumbnail.image(for: Prefs.wallpaperURL ?? DefaultWallpaper.url()) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .id(wallpaperPath)
            }
            Button("Change") { chooseWallpaper() }
                .buttonStyle(ChipButtonStyle(phase: .work))
            if !wallpaperPath.isEmpty {
                Button { wallpaperPath = "" } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
                    .help("Use the default wallpaper")
            }
        }
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a wallpaper for deep work sessions"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            wallpaperPath = url.path
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var shortcuts: [String] = []
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
