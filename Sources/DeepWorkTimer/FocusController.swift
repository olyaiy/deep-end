import AppKit

/// Turns a macOS Focus mode on for work sessions, through the Deep Work Focus
/// helper (Sources/DeepWorkFocus). The helper edits the Focus database, which
/// needs Full Disk Access; it runs from a LaunchAgent so that grant is its own,
/// not this app's (which a rebuild would reset).
///
/// Requests go through files: we write focus-request.json, launchd runs the
/// helper when it changes, and the helper answers in focus-status.json.
@MainActor
final class FocusController: ObservableObject {
    static let shared = FocusController()

    enum State: Equatable {
        case checking
        /// The helper app isn't installed (build.sh puts it in ~/Applications).
        case missingHelper
        /// Installed, but it hasn't been given Full Disk Access yet.
        case needsAccess
        case ready
        case failed(String)
    }

    struct Mode: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var modes: [Mode] = [Mode(id: FocusController.doNotDisturb, name: "Do Not Disturb")]

    static let doNotDisturb = "com.apple.donotdisturb.mode.default"
    static let helperURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Deep Work Focus.app")
    private static let agentLabel = "com.olyaiy.DeepWorkTimer.focus"

    private let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeepWorkTimer", isDirectory: true)
    private var requestURL: URL { support.appendingPathComponent("focus-request.json") }
    private var statusURL: URL { support.appendingPathComponent("focus-status.json") }
    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    // MARK: Session hooks

    func turnOn() {
        guard Prefs.effectsEnabled else { return }
        Task { await send(["action": "on", "mode": Prefs.focusMode]) }
    }

    /// Only ends the Focus the timer turned on, never one you set yourself.
    func turnOff() {
        Task { await send(["action": "off"]) }
    }

    // MARK: Setup

    /// Installs the LaunchAgent if needed and asks the helper how things stand.
    func refresh() {
        Task {
            guard FileManager.default.fileExists(atPath: Self.helperURL.path) else {
                state = .missingHelper
                return
            }
            installAgentIfNeeded()
            await send(["action": "status"])
        }
    }

    /// Opens Privacy & Security › Full Disk Access and shows the helper in Finder to drag in.
    func openFullDiskAccessSettings() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.helperURL])
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installAgentIfNeeded() {
        let executable = Self.helperURL.appendingPathComponent("Contents/MacOS/DeepWorkFocus").path
        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [executable],
            "WatchPaths": [requestURL.path],
            "ThrottleInterval": 1,
            "ProcessType": "Interactive",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: requestURL.path) {
            FileManager.default.createFile(atPath: requestURL.path, contents: Data("{}".utf8))
        }
        let loaded = launchctl(["print", "gui/\(getuid())/\(Self.agentLabel)"]) == 0
        if loaded, (try? Data(contentsOf: agentURL)) == data { return }

        try? FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: agentURL)
        if loaded { _ = launchctl(["bootout", "gui/\(getuid())/\(Self.agentLabel)"]) }
        _ = launchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
    }

    @discardableResult
    private func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: Talking to the helper

    /// Writes a request and waits (briefly) for the helper's answer.
    private func send(_ request: [String: String]) async {
        guard FileManager.default.fileExists(atPath: Self.helperURL.path) else {
            state = .missingHelper
            return
        }
        let id = UUID().uuidString
        var body = request
        body["id"] = id
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? data.write(to: requestURL, options: .atomic)

        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(150))
            guard let reply = readStatus(), reply["id"] as? String == id else { continue }
            apply(reply)
            return
        }
        state = .failed("The Focus helper didn't respond.")
    }

    private func readStatus() -> [String: Any]? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func apply(_ reply: [String: Any]) {
        if reply["ok"] as? Bool == true {
            state = .ready
            let list = (reply["modes"] as? [[String: String]] ?? []).compactMap { item -> Mode? in
                guard let id = item["id"], let name = item["name"] else { return nil }
                return Mode(id: id, name: name)
            }
            if !list.isEmpty { modes = list }
        } else if reply["error"] as? String == "no-access" {
            state = .needsAccess
        } else {
            state = .failed(reply["message"] as? String ?? "Something went wrong.")
        }
    }
}
