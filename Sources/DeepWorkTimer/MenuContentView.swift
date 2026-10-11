import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var timer: TimerModel
    // Plain ObservableObjects instead of @State: the @State macro plugin ships
    // only with full Xcode, and this builds with just the Command Line Tools.
    @StateObject private var ui = MenuUIState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ui.showingSettings {
                SettingsView(done: { ui.showingSettings = false })
            } else {
                timerSection
                Divider()
                footer
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(timer.phase.title)
                    .font(.headline)
                Spacer()
                if timer.phase == .work {
                    Text("Session \(timer.sessionNumber) of \(Prefs.sessionsPerLongBreak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(timer.phase == .idle ? idleTime : timer.displayTime)
                .font(.system(size: 52, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timer.isPaused ? .secondary : .primary)
                .frame(maxWidth: .infinity)

            ProgressView(value: timer.progress)
                .tint(timer.phase == .work ? .accentColor : .green)

            controls
        }
    }

    private var idleTime: String { "\(Prefs.workMinutes):00" }

    @ViewBuilder
    private var controls: some View {
        if timer.phase == .idle {
            Button {
                timer.startWork()
            } label: {
                Label("Start deep work", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            HStack {
                if timer.isPaused {
                    Button { timer.resume() } label: { Label("Resume", systemImage: "play.fill") }
                } else {
                    Button { timer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                }
                Button { timer.skip() } label: {
                    Label(timer.phase == .work ? "Break" : "Skip", systemImage: "forward.fill")
                }
                Spacer()
                Button(role: .destructive) { timer.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            .controlSize(.regular)
        }
    }

    private var footer: some View {
        HStack {
            Label("Today: \(timer.today.sessions) sessions · \(timer.today.focusText)", systemImage: "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { ui.showingSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
                .help("Quit")
        }
    }
}

struct SettingsView: View {
    let done: () -> Void

    @AppStorage(Prefs.Key.workMinutes) private var workMinutes = 50
    @AppStorage(Prefs.Key.shortBreakMinutes) private var shortBreakMinutes = 10
    @AppStorage(Prefs.Key.longBreakMinutes) private var longBreakMinutes = 20
    @AppStorage(Prefs.Key.sessionsPerLongBreak) private var sessionsPerLongBreak = 3
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @AppStorage(Prefs.Key.focusOnShortcut) private var focusOnShortcut = "Deep Work On"
    @AppStorage(Prefs.Key.focusOffShortcut) private var focusOffShortcut = "Deep Work Off"
    @AppStorage(Prefs.Key.wallpaperPath) private var wallpaperPath = ""
    @AppStorage(Prefs.Key.playSound) private var playSound = true

    @StateObject private var state = SettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done", action: done)
            }

            section("Timer") {
                Stepper("Work: \(workMinutes) min", value: $workMinutes, in: 5...180, step: 5)
                Stepper("Short break: \(shortBreakMinutes) min", value: $shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(longBreakMinutes) min", value: $longBreakMinutes, in: 5...90, step: 5)
                Stepper("Long break every \(sessionsPerLongBreak) sessions", value: $sessionsPerLongBreak, in: 1...8)
                Toggle("Play sound", isOn: $playSound)
            }

            section("During work sessions") {
                Toggle("Turn on Focus & change wallpaper", isOn: $effectsEnabled)
                Group {
                    shortcutPicker("Focus on", selection: $focusOnShortcut)
                    shortcutPicker("Focus off", selection: $focusOffShortcut)
                    if !state.shortcuts.isEmpty, missingShortcut {
                        Text("A shortcut above doesn't exist yet. Create it in the Shortcuts app with a “Set Focus” action.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("Wallpaper")
                        Spacer()
                        Text(wallpaperPath.isEmpty ? "Default (dark)" : URL(fileURLWithPath: wallpaperPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Choose…", action: chooseWallpaper)
                        if !wallpaperPath.isEmpty {
                            Button("Use default") { wallpaperPath = "" }
                        }
                    }
                }
                .disabled(!effectsEnabled)
            }

            section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
            }
        }
        .task { state.shortcuts = await ShortcutRunner.list() }
    }

    private var missingShortcut: Bool {
        [focusOnShortcut, focusOffShortcut].contains { !$0.isEmpty && !state.shortcuts.contains($0) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func shortcutPicker(_ label: String, selection: Binding<String>) -> some View {
        // Keep the current value selectable even if the shortcut doesn't exist yet.
        let options = Array(Set(state.shortcuts + [selection.wrappedValue]).subtracting([""]))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Picker(label, selection: selection) {
            Text("None").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
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

final class MenuUIState: ObservableObject {
    @Published var showingSettings = false
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
