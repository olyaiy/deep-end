import SwiftUI

/// A slim row in the menu bar window: what's playing and ⏮ ⏯ ⏭.
struct NowPlayingStrip: View {
    @ObservedObject private var music = MusicController.shared
    @AppStorage(Prefs.Key.musicSource) private var source = MusicController.Source.spotify.rawValue
    @AppStorage(Prefs.Key.focusPlaylist) private var playlist = ""

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                control("backward.fill", label: "Previous track") { music.previous() }
                control(music.isPlaying ? "pause.fill" : "play.fill", label: music.isPlaying ? "Pause" : "Play", size: 14) { music.playPause() }
                control("forward.fill", label: "Next track") { music.next() }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
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
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let url = music.track?.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderArt
            }
            .frame(width: 30, height: 30)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        } else {
            placeholderArt
                .frame(width: 30, height: 30)
                .clipShape(shape)
        }
    }

    private var placeholderArt: some View {
        ZStack {
            Theme.fill
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func control(_ symbol: String, label: String, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Hoverable { hovered in
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(hovered ? Theme.fill : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .pointerStyle(.link)
            .accessibilityLabel(label)
        }
    }
}
