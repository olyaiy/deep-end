import AppKit

/// Music for focus sessions. Spotify is controlled directly (AppleScript), which
/// also gives the current track and lets a session start your focus playlist.
/// Without Spotify, or with "Any app" chosen, the controls drive whatever is
/// playing through macOS's media controls (no track info there).
@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()

    enum Source: String, CaseIterable {
        case spotify, system
        var title: String { self == .spotify ? "Spotify" : "Any app" }
    }

    enum OnStart: String, CaseIterable {
        case nothing, resume, playlist
        var title: String {
            switch self {
            case .nothing: "Do nothing"
            case .resume: "Resume music"
            case .playlist: "Play focus playlist"
            }
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var artworkURL: URL?
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var track: Track?
    @Published private(set) var spotifyRunning = false
    /// Whether the menu bar window is open.
    @Published private(set) var isVisible = false

    static let spotifyID = "com.spotify.client"
    var spotifyInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) != nil }

    /// Spotify when chosen and installed; otherwise system media controls.
    var usesSpotify: Bool { Prefs.musicSource == .spotify && spotifyInstalled }

    private let scriptQueue = DispatchQueue(label: "DeepWorkTimer.music")
    private var poller: Timer?
    /// Set when a session started music, so ending it only pauses what we played.
    private var playingForSession = false

    // MARK: Controls

    func playPause() {
        if usesSpotify {
            if !spotifyRunning, let uri = Prefs.focusPlaylistURI {
                playSpotify(uri: uri)
            } else {
                spotify("playpause")
            }
        } else {
            SystemMedia.send(.togglePlayPause)
        }
        refreshSoon()
    }

    func next() {
        usesSpotify ? spotify("next track") : SystemMedia.send(.nextTrack)
        refreshSoon()
    }

    func previous() {
        usesSpotify ? spotify("previous track") : SystemMedia.send(.previousTrack)
        refreshSoon()
    }

    // MARK: Session hooks

    func sessionStarted() {
        switch Prefs.musicOnStart {
        case .nothing: return
        case .resume:
            usesSpotify ? playSpotify(uri: nil) : SystemMedia.send(.play)
        case .playlist:
            if usesSpotify, let uri = Prefs.focusPlaylistURI { playSpotify(uri: uri) }
            else if usesSpotify { playSpotify(uri: nil) }
            else { SystemMedia.send(.play) }
        }
        playingForSession = true
        refreshSoon()
    }

    func sessionEnded() {
        guard playingForSession else { return }
        playingForSession = false
        guard Prefs.pauseMusicOnBreak else { return }
        usesSpotify ? spotify("pause") : SystemMedia.send(.pause)
        refreshSoon()
    }

    // MARK: Now playing

    /// Polls Spotify while the menu bar window is open.
    func setVisible(_ visible: Bool) {
        poller?.invalidate()
        poller = nil
        isVisible = visible
        guard visible else { return }
        refresh()
        poller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MusicController.shared.refresh() }
        }
    }

    func refresh() {
        spotifyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyID).isEmpty == false
        // Asking a closed Spotify anything would launch it.
        guard usesSpotify, spotifyRunning else {
            track = nil
            isPlaying = false
            return
        }
        let script = """
        tell application id "com.spotify.client"
            set s to player state as string
            try
                set t to current track
                return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (artwork url of t)
            on error
                return s
            end try
        end tell
        """
        run(script) { [weak self] result in
            guard let self else { return }
            let lines = (result ?? "").components(separatedBy: "\n")
            self.isPlaying = lines.first == "playing"
            if lines.count >= 3, !lines[1].isEmpty {
                let artwork = lines.count >= 4 ? URL(string: lines[3]) : nil
                self.track = Track(title: lines[1], artist: lines[2], artworkURL: artwork)
            } else {
                self.track = nil
            }
        }
    }

    /// Fakes a track for design snapshots.
    func preview(track: Track?, playing: Bool) {
        spotifyRunning = true
        self.track = track
        isPlaying = playing
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    // MARK: Spotify

    private func spotify(_ command: String) {
        guard spotifyRunning || NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyID).isEmpty == false else { return }
        run("tell application id \"com.spotify.client\" to \(command)")
    }

    /// Plays a playlist/album/track URI, or resumes if nil. Opens Spotify in the background if needed.
    private func playSpotify(uri: String?) {
        let command = uri.map { "play track \"\($0)\"" } ?? "play"
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyID).isEmpty == false {
            run("tell application id \"com.spotify.client\" to \(command)")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            // Spotify ignores commands for a moment after launching.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.run("tell application id \"com.spotify.client\" to \(command)")
                self?.refreshSoon()
            }
        }
    }

    private func run(_ source: String, completion: ((String?) -> Void)? = nil) {
        scriptQueue.async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            if let error { NSLog("DWT music script error: %@", error) }
            DispatchQueue.main.async { completion?(output) }
        }
    }

    /// "https://open.spotify.com/playlist/ID?si=…" or "spotify:playlist:ID" → "spotify:playlist:ID".
    static func spotifyURI(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("spotify:") { return text }
        guard let url = URL(string: text), url.host()?.hasSuffix("spotify.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2, ["playlist", "album", "track", "artist", "show", "episode"].contains(parts[0]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }
}

/// macOS's system media controls (the same ones as the keyboard's ⏯ keys), via
/// the private MediaRemote framework. Sending commands needs no permission.
enum SystemMedia {
    enum Command: Int32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }
}
