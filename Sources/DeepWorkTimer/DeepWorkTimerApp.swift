import AppKit
import SwiftUI

// A plain AppKit app: the menu bar item is an NSStatusItem (see MenuBarController),
// which SwiftUI's App lifecycle would only get in the way of.
@main
enum Main {
    static func main() {
        MainActor.assumeIsolated {
            Prefs.registerDefaults()
            DesignPreview.snapshotIfRequested()
            Showcase.runIfRequested()
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?
    private var timer: TimerModel?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if DesignPreview.previewRequested {
                // The preview shares settings with the real app; leave its effects alone.
                DesignPreview.showWindow()
                return
            }
            Appearance.apply()
            let timer = TimerModel()
            let menuBar = MenuBarController(timer: timer)
            // Pop the window open when a phase ends, without stealing the keyboard.
            timer.onTransition = { [weak menuBar] _ in menuBar?.show(focus: false) }
            self.timer = timer
            self.menuBar = menuBar
            // Sets up the Focus helper's LaunchAgent and checks it has access.
            FocusController.shared.refresh()
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

    // Take URL events directly (application(_:open:) isn't reliably called for
    // a menu bar app with no windows).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        MainActor.assumeIsolated { URLCommands.handle(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Focus or wallpaper stuck on if the app quits mid-session.
        guard !DesignPreview.previewRequested else { return }
        MainActor.assumeIsolated {
            SessionEffects.shared.revert()
        }
    }
}

/// `deepwork://` commands, for Shortcuts, Raycast, Alfred, or `open` in a terminal:
///   deepwork://start?minutes=50&intent=Write%20docs   deepwork://toggle
///   deepwork://pause   deepwork://resume   deepwork://stop   deepwork://skip
///   deepwork://add?minutes=5   deepwork://subtract?minutes=5   deepwork://open
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
        case "open": MenuBarController.shared?.show()
        default: break
        }
    }
}
