import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingWidget()
                .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(player.store.stations) { station in
                        StationRow(station: station)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                Button("Настройки...") {
                    openWindow(id: "settings")
                    NSApp.activate()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

private struct NowPlayingWidget: View {
    @EnvironmentObject var player: PlayerManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            artworkView
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(trackTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let error = player.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                HStack(spacing: 0) {
                    controlButton("backward.fill", font: .body) {
                        player.playPreviousStation()
                    }
                    controlButton(
                        player.isLoading ? "stop.circle" : (player.isPlaying ? "pause.fill" : "play.fill"),
                        font: .title3
                    ) {
                        player.togglePlay()
                    }
                    controlButton("forward.fill", font: .body) {
                        player.playNextStation()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var trackTitle: String {
        if player.isLoading { return "Загрузка..." }
        return player.currentTrack ?? player.currentStation?.name ?? "Не играет"
    }

    private var subtitle: String? {
        guard let station = player.currentStation else { return nil }
        if player.currentTrack != nil {
            return station.name
        }
        return nil
    }

    @ViewBuilder private var artworkView: some View {
        if let image = player.currentArtworkImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func controlButton(_ systemName: String, font: Font, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .frame(width: 40, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StationRow: View {
    @EnvironmentObject var player: PlayerManager
    let station: Station
    @State private var isHovered = false

    private var isActive: Bool { player.currentStation?.id == station.id }
    private var isPlaying: Bool { isActive && player.isPlaying }

    var body: some View {
        Button {
            if isPlaying {
                player.stop()
            } else {
                player.play(station: station)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .opacity(isActive ? 1 : 0)

                Text(station.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var rowBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(isHovered ? 0.25 : 0.15))
                .padding(.horizontal, 4)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.07))
                .padding(.horizontal, 4)
        }
    }
}
