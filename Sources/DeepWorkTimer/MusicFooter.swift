import SwiftUI

/// Music lives at the end of the Today row: ⏯ and a now-playing glyph.
/// Hovering it turns the whole row into the track with ⏮ ⏯ ⏭ (see NowPlayingRow).
struct MusicTail: View {
    @ObservedObject private var music = MusicController.shared

    var body: some View {
        HStack(spacing: 0) {
            MusicButton.playPause(music)
            // Sits where ⏭ will be once the row expands, so ⏯ never moves under the cursor.
            NowPlayingGlyph(music: music)
                .frame(width: MusicButton.size, height: MusicButton.size)
        }
        .padding(.trailing, -5)
    }
}

/// The track, with ⏮ ⏯ ⏭; replaces the Today row while you hover the music.
struct NowPlayingRow: View {
    @ObservedObject private var music = MusicController.shared
    @AppStorage(Prefs.Key.focusPlaylist) private var playlist = ""

    var body: some View {
        HStack(spacing: 9) {
            artwork
            (Text(title).font(.system(size: 12, weight: .semibold))
                + Text(" · \(subtitle)").font(.system(size: 12)).foregroundColor(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                MusicButton.make("backward.fill", label: "Previous track") { music.previous() }
                MusicButton.playPause(music)
                MusicButton.make("forward.fill", label: "Next track") { music.next() }
            }
            .padding(.trailing, -5)
        }
        .animation(Theme.spring, value: music.track)
    }

    private var title: String {
        if let track = music.track { return track.title }
        if !music.usesSpotify { return "Media" }
        return music.spotifyRunning ? "Not playing" : "Spotify"
    }

    private var subtitle: String {
        if let track = music.track { return track.artist }
        if !music.usesSpotify { return "Controls whatever's playing" }
        if !music.spotifyRunning {
            return MusicController.spotifyURI(from: playlist) != nil ? "Press play for your focus playlist" : "Press play to start"
        }
        return "Paused"
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if let url = music.track?.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderArt
                }
            } else {
                placeholderArt
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }

    private var placeholderArt: some View {
        ZStack {
            Theme.fill
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Bars that move while music plays; a note when Spotify isn't open.
private struct NowPlayingGlyph: View {
    @ObservedObject var music: MusicController

    var body: some View {
        if music.usesSpotify && !music.spotifyRunning {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(music.isPlaying ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.tertiary))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: music.isPlaying)
        }
    }
}

enum MusicButton {
    static let size: CGFloat = 24

    @MainActor
    static func playPause(_ music: MusicController) -> some View {
        make(music.isPlaying ? "pause.fill" : "play.fill", label: music.isPlaying ? "Pause music" : "Play music", iconSize: 11) {
            music.playPause()
        }
    }

    static func make(_ symbol: String, label: String, iconSize: CGFloat = 9.5, action: @escaping () -> Void) -> some View {
        Hoverable { hovered in
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .background(Circle().fill(hovered ? Theme.fill : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .pointerStyle(.link)
            .accessibilityLabel(label)
            .help(label)
        }
    }
}
