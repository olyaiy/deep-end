import SwiftUI

@main
struct DeepWorkTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var timer: TimerModel

    init() {
        Prefs.registerDefaults()
        _timer = StateObject(wrappedValue: TimerModel())
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
    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Focus or wallpaper stuck on if the app quits mid-session.
        MainActor.assumeIsolated {
            SessionEffects.shared.revert()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var timer: TimerModel

    var body: some View {
        switch timer.phase {
        case .idle:
            Image(systemName: "brain.head.profile")
        case .work:
            Text("\(Image(systemName: timer.isPaused ? "pause.circle" : "brain.head.profile")) \(timer.displayTime)")
                .monospacedDigit()
        case .shortBreak, .longBreak:
            Text("\(Image(systemName: "cup.and.saucer")) \(timer.displayTime)")
                .monospacedDigit()
        }
    }
}
