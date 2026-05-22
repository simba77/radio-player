import SwiftUI

@main
struct RadioPlayerApp: App {
    @StateObject private var store: StationStore
    @StateObject private var player: PlayerManager

    init() {
        let store = StationStore()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: PlayerManager(store: store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(player)
        } label: {
            Image(systemName: statusIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Настройки", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }

    /// Иконка строки меню: мигает во время переподключения, иначе отражает состояние воспроизведения.
    private var statusIcon: String {
        if player.isReconnecting {
            return player.statusBlink
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash"
        }
        return player.isPlaying
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
    }
}
