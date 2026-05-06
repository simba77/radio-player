import AVFoundation
import MediaPlayer
import Foundation

private struct SendableMetadataItem: @unchecked Sendable {
    let item: AVMetadataItem
}

private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    nonisolated(unsafe) var onMetadata: (String?, String?) -> Void = { _, _ in }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        let titleRef = items.first(where: {
            $0.commonKey == .commonKeyTitle ||
            ($0.keySpace == AVMetadataKeySpace(rawValue: "icy") && ($0.key as? String) == "StreamTitle")
        }).map(SendableMetadataItem.init)
        let artistRef = items.first(where: { $0.commonKey == .commonKeyArtist })
            .map(SendableMetadataItem.init)
        Task {
            let title = (try? await titleRef?.item.load(.stringValue))?.trimmingCharacters(in: .whitespaces)
            let artist = (try? await artistRef?.item.load(.stringValue))?.trimmingCharacters(in: .whitespaces)
            await MainActor.run { self.onMetadata(artist, title) }
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

    let store = StationStore()

    private var player: AVPlayer?
    private let metadataOutput = AVPlayerItemMetadataOutput()
    private let metadataDelegate = MetadataDelegate()
    private var playerObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?

    init() {
        setupRemoteCommands()
        metadataOutput.setDelegate(metadataDelegate, queue: .main)
        metadataDelegate.onMetadata = { [weak self] artist, title in
            self?.handleMetadata(artist: artist, title: title)
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
        currentArtist = nil
        currentTrack = nil
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

    private func handleMetadata(artist: String?, title: String?) {
        guard let title, !title.isEmpty else { return }
        currentArtist = artist?.isEmpty == false ? artist : nil
        currentTrack = title
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

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        if isPlaying, let station = currentStation {
            var info: [String: Any] = [
                MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                MPNowPlayingInfoPropertyIsLiveStream: true,
            ]
            if let track = currentTrack {
                info[MPMediaItemPropertyTitle] = track
                info[MPMediaItemPropertyArtist] = currentArtist ?? station.name
                info[MPMediaItemPropertyAlbumTitle] = station.name
            } else {
                info[MPMediaItemPropertyTitle] = station.name
            }
            center.nowPlayingInfo = info
            center.playbackState = .playing
        } else {
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: currentStation?.name ?? "Radio Player",
                MPNowPlayingInfoPropertyIsLiveStream: true,
            ]
            center.playbackState = .paused
        }
    }
}
