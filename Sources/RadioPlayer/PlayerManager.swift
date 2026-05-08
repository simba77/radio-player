import AVFoundation
import AppKit
import MediaPlayer
import Foundation

private struct SendableMetadataItem: @unchecked Sendable {
    let item: AVMetadataItem
}

private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    nonisolated(unsafe) weak var owner: PlayerManager?

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let items = groups.flatMap(\.items)

        let titleItem = items.first {
            $0.commonKey == .commonKeyTitle ||
            ($0.keySpace == AVMetadataKeySpace(rawValue: "icy") && ($0.key as? String) == "StreamTitle")
        }
        let artistItem = items.first { $0.commonKey == .commonKeyArtist }
        // Cover URL arrives as WXXX with an absolute https:// URL; the other WXXX is a relative metadata path
        let wxxxRefs = items.filter { ($0.key as? String) == "WXXX" }.map(SendableMetadataItem.init)

        let titleRef = titleItem.map(SendableMetadataItem.init)
        let artistRef = artistItem.map(SendableMetadataItem.init)

        Task {
            let title = (try? await titleRef?.item.load(.stringValue))?.trimmingCharacters(in: .whitespaces)
            let artist = (try? await artistRef?.item.load(.stringValue))?.trimmingCharacters(in: .whitespaces)
            var coverURL: String?
            for ref in wxxxRefs {
                if let str = try? await ref.item.load(.stringValue), str.hasPrefix("https://") {
                    coverURL = str
                    break
                }
            }
            await owner?.handleMetadata(artist: artist, title: title, coverURL: coverURL)
        }
    }
}

@MainActor
final class PlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentStation: Station?
    @Published var currentArtist: String?
    @Published var currentTrack: String?
    private var currentArtworkData: Data?

    var formattedTrack: String? {
        guard let track = currentTrack else { return nil }
        return currentArtist.map { "\($0) — \(track)" } ?? track
    }

    let store: StationStore

    private static let lastStationKey = "lastStationID"
    private var player: AVPlayer?
    private let metadataOutput = AVPlayerItemMetadataOutput()
    private let metadataDelegate = MetadataDelegate()
    private var playerObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var currentArtworkURL: String?

    init(store: StationStore) {
        self.store = store
        setupRemoteCommands()
        metadataOutput.setDelegate(metadataDelegate, queue: .main)
        metadataDelegate.owner = self
        if let raw = UserDefaults.standard.string(forKey: Self.lastStationKey),
            let id = UUID(uuidString: raw),
            let station = store.stations.first(where: { $0.id == id }) {
            currentStation = station
        }
    }

    func play(station: Station) {
        guard let url = station.streamURL else { return }
        stopObserving()
        player?.pause()
        player?.currentItem?.remove(metadataOutput)

        let item = AVPlayerItem(url: url)
        item.add(metadataOutput)
        player = AVPlayer(playerItem: item)
        player?.play()

        currentStation = station
        UserDefaults.standard.set(station.id.uuidString, forKey: Self.lastStationKey)
        currentArtist = nil
        currentTrack = nil
        currentArtworkData = nil
        currentArtworkURL = nil
        errorMessage = nil
        isLoading = true
        isPlaying = true
        updateNowPlayingInfo()
        observePlayback()
    }

    func stop() {
        stopObserving()
        player?.pause()
        player?.currentItem?.remove(metadataOutput)
        player = nil
        isPlaying = false
        isLoading = false
        updateNowPlayingInfo()
    }

    func togglePlay() {
        if isPlaying {
            stop()
        } else if let station = currentStation {
            play(station: station)
        } else if let first = store.stations.first {
            play(station: first)
        }
    }

    private func observePlayback() {
        playerObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    self.isLoading = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isLoading = true
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }

        itemObserver = player?.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor [weak self] in
                guard let self, status == .failed else { return }
                self.isPlaying = false
                self.isLoading = false
                self.errorMessage = error?.localizedDescription ?? "Не удалось воспроизвести поток"
                self.updateNowPlayingInfo()
            }
        }
    }

    private func stopObserving() {
        playerObserver = nil
        itemObserver = nil
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate func handleMetadata(artist: String?, title: String?, coverURL: String?) {
        guard let title, !title.isEmpty else { return }
        currentArtist = artist?.isEmpty == false ? artist : nil
        currentTrack = title
        if let coverURL, coverURL != currentArtworkURL {
            currentArtworkURL = coverURL
            Task { await loadArtwork(from: coverURL) }
        }
        updateNowPlayingInfo()
    }

    private func loadArtwork(from urlString: String) async {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        currentArtworkData = data
        updateNowPlayingInfo()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlay() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.stop() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlay() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playNextStation() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playPreviousStation() }
            return .success
        }
    }

    private func playNextStation() {
        let stations = store.stations
        guard let current = currentStation,
            let idx = stations.firstIndex(where: { $0.id == current.id }) else {
            if let first = stations.first { play(station: first) }
            return
        }
        play(station: stations[(idx + 1) % stations.count])
    }

    private func playPreviousStation() {
        let stations = store.stations
        guard let current = currentStation,
            let idx = stations.firstIndex(where: { $0.id == current.id }) else {
            if let first = stations.first { play(station: first) }
            return
        }
        play(station: stations[(idx - 1 + stations.count) % stations.count])
    }

    private nonisolated static func makeArtwork(from data: Data) -> MPMediaItemArtwork? {
        guard let image = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in
            NSImage(data: data) ?? NSImage()
        }
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        if isPlaying, let station = currentStation {
            var info: [String: Any] = [
                MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                MPNowPlayingInfoPropertyIsLiveStream: true
            ]
            if let track = currentTrack {
                info[MPMediaItemPropertyTitle] = track
                info[MPMediaItemPropertyArtist] = currentArtist ?? station.name
                info[MPMediaItemPropertyAlbumTitle] = station.name
            } else {
                info[MPMediaItemPropertyTitle] = station.name
            }
            if let artworkData = currentArtworkData {
                info[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: artworkData)
            }
            center.nowPlayingInfo = info
            center.playbackState = .playing
        } else {
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: currentStation?.name ?? "Radio Player",
                MPNowPlayingInfoPropertyIsLiveStream: true
            ]
            center.playbackState = .paused
        }
    }
}
