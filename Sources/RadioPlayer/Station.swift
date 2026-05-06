import Foundation

struct Station: Identifiable, Sendable, Codable {
    let id: UUID
    var name: String
    var urlString: String

    var streamURL: URL? { URL(string: urlString) }

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.urlString = url
    }
}

extension Station {
    static let defaults: [Station] = [
        Station(name: "Radio Record — Lady Waks", url: "https://hls-01-radiorecord.hostingradio.ru/record-ladywaks/112/playlist.m3u8"),
        Station(name: "Radio Record — Main",      url: "https://hls-01-radiorecord.hostingradio.ru/record/playlist.m3u8"),
    ]
}
