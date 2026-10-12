import SwiftUI

@main
struct DeepWorkTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var timer: TimerModel

    init() {
        Prefs.registerDefaults()
        DesignPreview.snapshotIfRequested()
        let model = TimerModel()
        model.onTransition = { [weak model] transition in
            guard let model else { return }
            ToastController.shared.show(transition, model: model)
        }
        _timer = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(timer)
        } label: {
            MenuBarLabel(timer: timer)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if DesignPreview.previewRequested {
                // The preview shares settings with the real app; leave its effects alone.
                DesignPreview.showWindow()
                return
            }
            // Clean up after a crash or kill mid-session. This runs after launch
            // finishes, once macOS has reported the connected displays.
            SessionEffects.shared.revert()
        }

        // A display that was unplugged mid-session gets its wallpaper back when it returns.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if TimerModel.live?.phase != .work { SessionEffects.shared.restoreWallpapers() }
            }
        }

        // `kill`/`pkill` (SIGTERM) skips applicationWillTerminate; clean up anyway.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { SessionEffects.shared.revert() }
            exit(0)
        }
        source.resume()
        terminationSignal = source
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            urls.forEach(URLCommands.handle)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Focus or wallpaper stuck on if the app quits mid-session.
        guard !DesignPreview.previewRequested else { return }
        MainActor.assumeIsolated {
            SessionEffects.shared.revert()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var timer: TimerModel
    @AppStorage(Prefs.Key.showTimeInMenuBar) private var showTime = true

    var body: some View {
        if timer.phase == .idle {
            Image(systemName: "timer")
        } else {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.ring(remaining: 1 - timer.progress, paused: timer.isPaused))
                if showTime {
                    Text(timer.displayTime).monospacedDigit()
                }
            }
        }
    }
}

/// `deepwork://` commands, for Shortcuts, Raycast, Alfred, or `open` in a terminal:
///   deepwork://start?minutes=50&intent=Write%20docs   deepwork://toggle
///   deepwork://pause   deepwork://resume   deepwork://stop   deepwork://skip
///   deepwork://add?minutes=5   deepwork://subtract?minutes=5
@MainActor
enum URLCommands {
    static func handle(_ url: URL) {
        guard url.scheme == "deepwork", let timer = TimerModel.live else { return }
        let command = (url.host ?? url.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let minutes = query.first { $0.name == "minutes" }?.value.flatMap(Int.init)
        let intent = query.first { $0.name == "intent" }?.value

        switch command {
        case "start":
            if let intent { timer.intention = intent }
            if timer.phase == .idle || timer.phase.isBreak {
                if timer.phase.isBreak { timer.stop() }
                timer.startWork(minutes: minutes.map { min(Prefs.maxWorkMinutes, max(1, $0)) })
            } else if timer.isPaused {
                timer.resume()
            }
        case "toggle":
            timer.phase == .idle ? timer.startWork() : timer.togglePause()
        case "pause": timer.pause()
        case "resume": timer.resume()
        case "stop": timer.stop()
        case "skip": timer.skip()
        case "add": timer.adjust(minutes: minutes ?? 5)
        case "subtract": timer.adjust(minutes: -(minutes ?? 5))
        default: break
        }
    }
}
