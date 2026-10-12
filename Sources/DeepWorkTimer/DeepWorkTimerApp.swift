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
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if DesignPreview.previewRequested { DesignPreview.showWindow() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            urls.forEach(URLCommands.handle)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Focus or wallpaper stuck on if the app quits mid-session.
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
