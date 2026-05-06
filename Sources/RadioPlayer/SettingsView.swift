import SwiftUI

struct SettingsView: View {
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
            }

            Divider()

            HStack(spacing: 2) {
                Button { store.addNew() } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
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
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 440, height: 300)
    }

    private func urlColor(_ string: String) -> Color {
        URL(string: string) != nil && string.hasPrefix("http") ? .secondary : .red
    }
}
