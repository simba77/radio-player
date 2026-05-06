import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Основные", systemImage: "gearshape") }

            StationsSettingsView()
                .tabItem { Label("Станции", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 440)
        .fixedSize()
    }
}

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !enabled
                    }
                }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct StationsSettingsView: View {
    @EnvironmentObject var store: StationStore
    @State private var selection: Station.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($store.stations) { $station in
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Название", text: $station.name)
                            .textFieldStyle(.plain)
                        TextField("URL потока", text: $station.urlString)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(urlColor(station.urlString))
                    }
                    .padding(.vertical, 4)
                    .tag(station.id)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 2) {
                Button { store.addNew() } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Добавить станцию")

                Button {
                    guard let sel = selection,
                          let idx = store.stations.firstIndex(where: { $0.id == sel })
                    else { return }
                    store.stations.remove(at: idx)
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("Удалить выбранную")

                Spacer()

                Button("Сбросить") {
                    store.reset()
                    selection = nil
                }
                .foregroundStyle(.red)
                .help("Восстановить встроенный список станций")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(height: 300)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .padding(16)
    }

    private func urlColor(_ string: String) -> Color {
        URL(string: string) != nil && string.hasPrefix("http") ? .secondary : .red
    }
}
