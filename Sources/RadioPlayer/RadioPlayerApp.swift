import SwiftUI

@main
struct RadioPlayerApp: App {
    @StateObject private var player = PlayerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(player)
        } label: {
            Image(systemName: player.isPlaying
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash")
        }
        .menuBarExtraStyle(.menu)

        Window("Настройки", id: "settings") {
            SettingsView()
                .environmentObject(player.store)
        }
        .windowResizability(.contentSize)
    }
}
