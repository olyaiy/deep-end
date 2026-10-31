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
            window.title = "Deep Work Timer"
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
    @AppStorage(Prefs.Key.focusOnShortcut) private var focusOnShortcut = "Deep Work On"
    @AppStorage(Prefs.Key.focusOffShortcut) private var focusOffShortcut = "Deep Work Off"
    @AppStorage(Prefs.Key.wallpaperPath) private var wallpaperPath = ""
    @AppStorage(Prefs.Key.playSound) private var playSound = true
    @AppStorage(Prefs.Key.showTimeInMenuBar) private var showTimeInMenuBar = true

    @StateObject private var state = SettingsState()

    var body: some View {
        Form {
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
                    shortcutPicker("Turn Focus on with", selection: $focusOnShortcut)
                    shortcutPicker("Turn Focus off with", selection: $focusOffShortcut)
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
            } header: {
                Text("During Focus")
            } footer: {
                if effectsEnabled, !state.shortcuts.isEmpty, missingShortcut {
                    Text("A selected shortcut doesn't exist yet. In the Shortcuts app, create one with a “Set Focus” action.")
                        .foregroundStyle(Theme.red)
                } else {
                    Text("Focus modes are switched with Shortcuts, since macOS has no direct way to do it.")
                        .foregroundStyle(.secondary)
                }
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
                    Button("Quit Deep Work Timer") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.red)
        .frame(width: 460)
        .frame(minHeight: 560)
        .task { state.shortcuts = await ShortcutRunner.list() }
    }

    private func stepper(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
                         format: @escaping (Int) -> String) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title) {
                Text(format(value.wrappedValue)).monospacedDigit()
            }
        }
    }

    private var missingShortcut: Bool {
        [focusOnShortcut, focusOffShortcut].contains { !$0.isEmpty && !state.shortcuts.contains($0) }
    }

    private func shortcutPicker(_ title: String, selection: Binding<String>) -> some View {
        // Keep the current value selectable even if the shortcut doesn't exist yet.
        let options = Array(Set(state.shortcuts + [selection.wrappedValue]).subtracting([""]))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Picker(title, selection: selection) {
            Text("None").tag("")
            Divider()
            ForEach(options, id: \.self) { Text($0).tag($0) }
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
