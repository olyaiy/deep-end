import Foundation

/// UserDefaults keys and registered defaults. Views bind to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let workMinutes = "workMinutes"
        static let shortBreakMinutes = "shortBreakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let sessionsPerLongBreak = "sessionsPerLongBreak"
        static let effectsEnabled = "effectsEnabled"
        static let focusOnShortcut = "focusOnShortcut"
        static let focusOffShortcut = "focusOffShortcut"
        static let wallpaperPath = "wallpaperPath"
        static let playSound = "playSound"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.workMinutes: 50,
            Key.shortBreakMinutes: 10,
            Key.longBreakMinutes: 20,
            Key.sessionsPerLongBreak: 3,
            Key.effectsEnabled: true,
            Key.focusOnShortcut: "Deep Work On",
            Key.focusOffShortcut: "Deep Work Off",
            Key.wallpaperPath: "",
            Key.playSound: true,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var workMinutes: Int { d.integer(forKey: Key.workMinutes) }
    static var shortBreakMinutes: Int { d.integer(forKey: Key.shortBreakMinutes) }
    static var longBreakMinutes: Int { d.integer(forKey: Key.longBreakMinutes) }
    static var sessionsPerLongBreak: Int { max(1, d.integer(forKey: Key.sessionsPerLongBreak)) }
    static var effectsEnabled: Bool { d.bool(forKey: Key.effectsEnabled) }
    static var focusOnShortcut: String { d.string(forKey: Key.focusOnShortcut) ?? "" }
    static var focusOffShortcut: String { d.string(forKey: Key.focusOffShortcut) ?? "" }
    static var playSound: Bool { d.bool(forKey: Key.playSound) }

    /// The user's chosen wallpaper, or nil to use the generated default.
    static var wallpaperURL: URL? {
        let path = d.string(forKey: Key.wallpaperPath) ?? ""
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
