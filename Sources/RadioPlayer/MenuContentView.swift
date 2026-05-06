import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let currentName = player.currentStation?.name ?? "Не играет"

        Text(player.isPlaying ? "▶ \(currentName)" : currentName)
            .foregroundStyle(.secondary)

        if player.isLoading {
            Text("Загрузка...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let error = player.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        } else if let track = player.currentTrack {
            let label = player.currentArtist.map { "\($0) — \(track)" } ?? track
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(label, forType: .string)
            } label: {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        ForEach(player.store.stations) { station in
            Button {
                if player.currentStation?.id == station.id && player.isPlaying {
                    player.stop()
                } else {
                    player.play(station: station)
                }
            } label: {
                HStack {
                    if player.currentStation?.id == station.id {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                    Text(station.name)
                }
            }
        }

        Divider()

        Button(player.isPlaying ? "Стоп" : "Играть") {
            player.togglePlay()
        }
        .keyboardShortcut("p", modifiers: [])

        Divider()

        Button("Настройки...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [])
    }
}
