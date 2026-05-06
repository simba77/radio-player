import Foundation

@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [Station] {
        didSet { save() }
    }

    private static let defaultsKey = "savedStations"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([Station].self, from: data),
           !decoded.isEmpty
        {
            stations = decoded
        } else {
            stations = Station.defaults
        }
    }

    func addNew() {
        stations.append(Station(name: "Новая станция", url: "https://"))
    }

    func reset() {
        stations = Station.defaults
    }

    func move(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
