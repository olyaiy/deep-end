import AppKit

/// Turns on the Focus mode and swaps the wallpaper for a work session, and puts
/// everything back afterwards.
///
/// The rule: a screen's wallpaper is only swapped once its original is saved,
/// and a saved original is only discarded once it's actually been put back.
/// Originals are persisted, so a crash, a kill, or a display that's unplugged
/// mid-session gets restored later (on next launch or when it reconnects).
@MainActor
final class SessionEffects {
    static let shared = SessionEffects()

    private let defaults = UserDefaults.standard
    private let activeKey = "effects.active"
    private let savedWallpapersKey = "effects.savedWallpapers"

    /// Originals we've restored this run. macOS can keep reporting the old
    /// wallpaper for a moment after a change, so this is more reliable than
    /// re-reading it if a new session starts soon after one ends.
    private var lastRestored: [String: String] = [:]

    private let fillOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true,
    ]

    private var saved: [String: String] {
        get { defaults.dictionary(forKey: savedWallpapersKey) as? [String: String] ?? [:] }
        set { newValue.isEmpty ? defaults.removeObject(forKey: savedWallpapersKey) : defaults.set(newValue, forKey: savedWallpapersKey) }
    }

    func apply() {
        SiteBlocker.shared.apply()
        guard Prefs.effectsEnabled, !defaults.bool(forKey: activeKey) else { return }
        defaults.set(true, forKey: activeKey)

        if let wallpaper = Prefs.wallpaperURL ?? DefaultWallpaper.url() {
            var originals = saved
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if originals[id] == nil, let original = originalWallpaper(for: screen, id: id) {
                    originals[id] = original
                }
                // Without a known original we couldn't put it back, so leave it alone.
                guard originals[id] != nil else { continue }
                // Save before changing anything, so a crash right here is still recoverable.
                saved = originals
                setWallpaper(wallpaper, for: screen)
            }
        }

        FocusController.shared.turnOn()
    }

    func revert() {
        SiteBlocker.shared.clear()
        let wasActive = defaults.bool(forKey: activeKey)
        restoreWallpapers()
        defaults.set(false, forKey: activeKey)
        if wasActive { FocusController.shared.turnOff() }
    }

    /// Put back any saved originals for the screens connected right now.
    /// Ones for disconnected screens stay saved until they reconnect.
    func restoreWallpapers() {
        var remaining = saved
        guard !remaining.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let path = remaining[id] else { continue }
            if setWallpaper(URL(fileURLWithPath: path), for: screen) {
                remaining[id] = nil
                lastRestored[id] = path
            }
        }
        saved = remaining
    }

    /// The screen's current wallpaper, as long as it's a real image file and not
    /// one of ours (e.g. left over from an interrupted session).
    private func originalWallpaper(for screen: NSScreen, id: String) -> String? {
        if let current = NSWorkspace.shared.desktopImageURL(for: screen), current.isFileURL,
           FileManager.default.fileExists(atPath: current.path), !isSessionWallpaper(current) {
            return current.path
        }
        return lastRestored[id]
    }

    private func isSessionWallpaper(_ url: URL) -> Bool {
        let ours = [Prefs.wallpaperURL, DefaultWallpaper.url()].compactMap { $0?.standardizedFileURL.path }
        return ours.contains(url.standardizedFileURL.path)
    }

    @discardableResult
    private func setWallpaper(_ url: URL, for screen: NSScreen) -> Bool {
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: fillOptions)
            return true
        } catch {
            NSLog("Deep Work Timer: couldn't set wallpaper on %@: %@", screen.localizedName, String(describing: error))
            return false
        }
    }
}

extension NSScreen {
    var displayID: String? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
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
