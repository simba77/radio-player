import Foundation

@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [Station] {
        didSet { save() }
    }

    private let defaultsKey = "savedStations"

    init() {
        if let data = UserDefaults.standard.data(forKey: "savedStations"),
           let decoded = try? JSONDecoder().decode([Station].self, from: data),
           !decoded.isEmpty
        {
            stations = decoded
        } else {
            stations = defaultStations
        }
    }

    func addNew() {
        stations.append(Station(name: "Новая станция", url: "https://"))
    }

    func reset() {
        stations = defaultStations
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
