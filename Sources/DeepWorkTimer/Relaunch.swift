import AppKit

/// Restarts the app into whatever build is installed, without interrupting a
/// session. build.sh swaps the new bundle in, then sends SIGUSR1 (or open
/// deepwork://relaunch by hand): this saves the timer, quits without undoing anything (sites stay blocked,
/// Focus stays on), and reopens the app, which picks the session back up from
/// the saved end date (TimerModel.restoreSession).
@MainActor
enum Relaunch {
    static func now() {
        TimerModel.live?.persist()
        UserDefaults.standard.synchronize()
        // A detached helper waits for this process to exit, then opens the app again.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath]
        try? process.run()
        // exit() skips applicationWillTerminate, so the session isn't ended.
        exit(0)
    }
}
