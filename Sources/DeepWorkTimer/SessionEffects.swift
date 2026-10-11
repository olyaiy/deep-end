import AppKit

/// Turns on the Focus mode and swaps the wallpaper for a work session, and puts
/// everything back afterwards. The "active" flag and original wallpapers are
/// persisted so a crash mid-session can be cleaned up on next launch.
@MainActor
final class SessionEffects {
    static let shared = SessionEffects()

    private let defaults = UserDefaults.standard
    private let activeKey = "effects.active"
    private let savedWallpapersKey = "effects.savedWallpapers"

    private let fillOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true,
    ]

    func apply() {
        guard Prefs.effectsEnabled, !defaults.bool(forKey: activeKey) else { return }

        var saved: [String: String] = [:]
        if let wallpaper = Prefs.wallpaperURL ?? DefaultWallpaper.url() {
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if let current = NSWorkspace.shared.desktopImageURL(for: screen) {
                    saved[id] = current.path
                }
                try? NSWorkspace.shared.setDesktopImageURL(wallpaper, for: screen, options: fillOptions)
            }
        }
        defaults.set(saved, forKey: savedWallpapersKey)
        defaults.set(true, forKey: activeKey)

        ShortcutRunner.run(Prefs.focusOnShortcut)
    }

    func revert() {
        guard defaults.bool(forKey: activeKey) else { return }

        let saved = defaults.dictionary(forKey: savedWallpapersKey) as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let path = saved[id] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: fillOptions)
        }
        defaults.removeObject(forKey: savedWallpapersKey)
        defaults.set(false, forKey: activeKey)

        ShortcutRunner.run(Prefs.focusOffShortcut)
    }
}

extension NSScreen {
    var displayID: String? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
}

/// Runs Shortcuts by name via the `shortcuts` CLI. This is how we toggle Focus
/// modes, since macOS has no public API for it.
enum ShortcutRunner {
    private static let cli = URL(fileURLWithPath: "/usr/bin/shortcuts")

    static func run(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func list() async -> [String] {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = cli
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map(String.init)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }.value
    }
}

/// A calm dark wallpaper generated on first use, so effects work before you pick your own.
enum DefaultWallpaper {
    static func url() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("DeepWorkTimer", isDirectory: true)
        let url = dir.appendingPathComponent("deep-work-wallpaper.png")
        if fm.fileExists(atPath: url.path) { return url }

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let width = 3840, height = 2160
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(
            starting: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1),
            ending: NSColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: 1)
        )?.draw(in: rect, angle: -90)

        let text = NSAttributedString(string: "deep work", attributes: [
            .font: NSFont.systemFont(ofSize: 96, weight: .ultraLight),
            .foregroundColor: NSColor(white: 1, alpha: 0.14),
            .kern: 24,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
