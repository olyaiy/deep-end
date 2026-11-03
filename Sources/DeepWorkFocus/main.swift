// Deep Work Focus: a tiny helper that turns macOS Focus modes on and off.
//
// macOS has no public API for this, so it edits the Focus database directly
// (~/Library/DoNotDisturb/DB/Assertions.json) and restarts the Focus daemon so
// it picks the change up. That folder is privacy-protected, so this helper
// needs Full Disk Access. It's a separate, rarely rebuilt app so that grant
// survives rebuilds of the main app.
//
// It's run by a LaunchAgent whenever the timer writes a request file:
//   ~/Library/Application Support/DeepWorkTimer/focus-request.json
//     {"id": "...", "action": "on" | "off" | "status", "mode": "com.apple.donotdisturb.mode.default"}
// and answers in focus-status.json next to it.
//
// Flags (for testing): --db <dir> and --support <dir> use other folders;
// --no-restart skips restarting the daemons.
import Foundation
import notify

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let args = CommandLine.arguments
func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let support = flag("--support").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? home.appendingPathComponent("Library/Application Support/DeepWorkTimer", isDirectory: true)
let requestURL = support.appendingPathComponent("focus-request.json")
let statusURL = support.appendingPathComponent("focus-status.json")
/// The assertion we created, so "off" never ends a Focus you turned on yourself.
let ownedURL = support.appendingPathComponent("focus-owned.json")

let dbDir = flag("--db").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? home.appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
let restartDaemons = !args.contains("--no-restart")
let assertionsURL = dbDir.appendingPathComponent("Assertions.json")
let modesURL = dbDir.appendingPathComponent("ModeConfigurations.json")

/// What Control Center writes; donotdisturbd treats it as a user action.
let clientID = "com.apple.focus.activity-manager"

struct HelperError: Error { let code: String; let message: String }

// MARK: JSON helpers

func readJSON(_ url: URL) throws -> [String: Any] {
    let data: Data
    do { data = try Data(contentsOf: url) } catch let error as NSError {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw HelperError(code: "no-access", message: "Needs Full Disk Access")
        }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return [:] }
        throw HelperError(code: "read-failed", message: error.localizedDescription)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw HelperError(code: "bad-format", message: "\(url.lastPathComponent) isn't in the expected format")
    }
    return object
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    do { try data.write(to: url, options: .atomic) } catch {
        throw HelperError(code: "write-failed", message: error.localizedDescription)
    }
}

// MARK: Focus database

/// Every Focus mode set up on this Mac: [(identifier, name)].
func availableModes() throws -> [[String: String]] {
    let file = try readJSON(modesURL)
    var modes: [[String: String]] = []
    for store in file["data"] as? [[String: Any]] ?? [] {
        for (id, config) in store["modeConfigurations"] as? [String: Any] ?? [:] {
            let mode = (config as? [String: Any])?["mode"] as? [String: Any]
            modes.append(["id": id, "name": mode?["name"] as? String ?? id, "symbol": mode?["symbolImageName"] as? String ?? ""])
        }
    }
    return modes.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
}

/// The active assertion record, if any.
func activeRecord(_ file: [String: Any]) -> [String: Any]? {
    ((file["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]])?.first
}

/// Replaces the live assertions, keeping the history arrays and anything else untouched.
func writeAssertions(_ records: [[String: Any]], into file: [String: Any]) throws {
    var file = file
    var stores = file["data"] as? [[String: Any]] ?? []
    if stores.isEmpty { stores = [["storeInvalidationRecords": [], "storeInvalidationRequestRecords": []]] }
    stores[0]["storeAssertionRecords"] = records
    file["data"] = stores
    var header = file["header"] as? [String: Any] ?? ["version": 8]
    header["timestamp"] = Date().timeIntervalSinceReferenceDate
    file["header"] = header

    // One backup of the original, before we ever change it.
    let backup = support.appendingPathComponent("Assertions.backup.json")
    if !fm.fileExists(atPath: backup.path), fm.fileExists(atPath: assertionsURL.path) {
        try? fm.copyItem(at: assertionsURL, to: backup)
    }
    try writeJSON(file, to: assertionsURL)
}

func turnOn(_ mode: String) throws -> String {
    let file = try readJSON(assertionsURL)
    let uuid = UUID().uuidString.uppercased()
    let record: [String: Any] = [
        "assertionDetails": [
            "assertionDetailsIdentifier": clientID,
            "assertionDetailsModeIdentifier": mode,
            "assertionDetailsReason": "user-action",
        ],
        "assertionSource": ["assertionClientIdentifier": clientID],
        "assertionStartDateTimestamp": Date().timeIntervalSinceReferenceDate,
        "assertionUUID": uuid,
    ]
    try writeAssertions([record], into: file)
    try writeJSON(["uuid": uuid, "mode": mode], to: ownedURL)
    notifyChanged(enabled: true)
    return uuid
}

/// Ends the Focus only if it's still the one we turned on.
func turnOff() throws -> Bool {
    let file = try readJSON(assertionsURL)
    let owned = (try? readJSON(ownedURL))?["uuid"] as? String
    try? fm.removeItem(at: ownedURL)
    guard let owned, let active = activeRecord(file), active["assertionUUID"] as? String == owned else { return false }
    try writeAssertions([], into: file)
    notifyChanged(enabled: false)
    return true
}

/// Tell the system: notifications for listeners, then restart the Focus daemon
/// (and Control Center, for the menu bar icon) so they reread the database.
func notifyChanged(enabled: Bool) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(enabled ? "_NSDoNotDisturbEnabledNotification" : "_NSDoNotDisturbDisabledNotification"),
        object: nil, userInfo: nil, deliverImmediately: true
    )
    for name in ["com.apple.notificationcenter.dnd.state.changed", "com.apple.focus.assertion.state.changed",
                 "com.apple.focus.status.changed"] {
        notify_post(name)
    }
    guard restartDaemons else { return }
    for label in ["com.apple.donotdisturbd", "com.apple.ControlCenter"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: Main

var status: [String: Any] = ["time": Date().timeIntervalSince1970]
do {
    let request = try readJSON(requestURL)
    status["id"] = request["id"] as? String ?? ""
    let action = request["action"] as? String ?? "status"
    switch action {
    case "on":
        guard let mode = request["mode"] as? String, !mode.isEmpty else {
            throw HelperError(code: "bad-request", message: "No Focus mode given")
        }
        status["uuid"] = try turnOn(mode)
    case "off":
        status["ended"] = try turnOff()
    default:
        break
    }
    status["modes"] = try availableModes()
    status["active"] = (activeRecord(try readJSON(assertionsURL))?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String ?? ""
    status["ok"] = true
} catch let error as HelperError {
    status["ok"] = false
    status["error"] = error.code
    status["message"] = error.message
} catch {
    status["ok"] = false
    status["error"] = "failed"
    status["message"] = error.localizedDescription
}
try? fm.createDirectory(at: support, withIntermediateDirectories: true)
try? writeJSON(status, to: statusURL)
