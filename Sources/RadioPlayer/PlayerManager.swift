import AVFoundation
import AppKit
import MediaPlayer
import Foundation
import Network

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
    @Published var isReconnecting = false
    /// Переключается таймером во время переподключения — для мигания иконки в строке меню.
    @Published var statusBlink = false
    @Published var errorMessage: String?
    @Published var currentStation: Station?
    @Published var currentArtist: String?
    @Published var currentTrack: String?
    @Published var currentArtworkImage: NSImage?
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

    /// Намерение играть: остаётся true при обрыве сети, сбрасывается только явным stop().
    private var shouldBePlaying = false
    private var reconnectTask: Task<Void, Never>?
    private var stallWatchdog: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    private static let blinkInterval: Duration = .milliseconds(600)
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "radioplayer.network.monitor")
    /// Пауза между попытками переподключения (без backoff — фиксированный интервал).
    private static let reconnectInterval: Duration = .seconds(3)
    /// Сколько ждём выхода из буферизации, прежде чем считать поток зависшим.
    private static let stallTimeout: Duration = .seconds(6)

    init(store: StationStore) {
        self.store = store
        setupRemoteCommands()
        metadataOutput.setDelegate(metadataDelegate, queue: .main)
        metadataDelegate.owner = self
        startNetworkMonitor()
        if let raw = UserDefaults.standard.string(forKey: Self.lastStationKey),
            let id = UUID(uuidString: raw),
            let station = store.stations.first(where: { $0.id == id }) {
            currentStation = station
        }
    }

    func play(station: Station) {
        currentStation = station
        UserDefaults.standard.set(station.id.uuidString, forKey: Self.lastStationKey)
        currentArtist = nil
        currentTrack = nil
        currentArtworkData = nil
        currentArtworkImage = nil
        currentArtworkURL = nil
        errorMessage = nil

        shouldBePlaying = true
        cancelReconnect()
        isReconnecting = false
        loadAndPlay(station: station)
    }

    /// Создаёт новый item и запускает воспроизведение. Не трогает намерение и метаданные —
    /// используется и при первом запуске, и при каждом переподключении.
    private func loadAndPlay(station: Station) {
        guard let url = station.streamURL else { return }
        stopObserving()
        player?.pause()
        player?.currentItem?.remove(metadataOutput)

        let item = AVPlayerItem(url: url)
        item.add(metadataOutput)
        player = AVPlayer(playerItem: item)
        player?.play()

        isLoading = true
        isPlaying = true
        updateNowPlayingInfo()
        observePlayback()
    }

    func stop() {
        shouldBePlaying = false
        cancelReconnect()
        stopBlinking()
        stopObserving()
        player?.pause()
        player?.currentItem?.remove(metadataOutput)
        player = nil
        isPlaying = false
        isLoading = false
        isReconnecting = false
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
                    self.handlePlaybackStarted()
                case .waitingToPlayAtSpecifiedRate:
                    self.isLoading = true
                    self.armStallWatchdog()
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }

        itemObserver = player?.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, status == .failed else { return }
                // Для live-радио ошибка item почти всегда означает обрыв сети — переподключаемся.
                self.beginReconnecting()
            }
        }
    }

    /// Поток реально пошёл: гасим индикаторы загрузки/переподключения и сторожевые таймеры.
    private func handlePlaybackStarted() {
        isLoading = false
        if isReconnecting {
            isReconnecting = false
            cancelReconnect()
            stopBlinking()
        }
        stallWatchdog?.cancel()
        stallWatchdog = nil
        errorMessage = nil
        updateNowPlayingInfo()
    }

    private func stopObserving() {
        playerObserver = nil
        itemObserver = nil
        stallWatchdog?.cancel()
        stallWatchdog = nil
    }

    // MARK: - Reconnect

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleNetworkChange(satisfied: satisfied)
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    private func handleNetworkChange(satisfied: Bool) {
        guard shouldBePlaying else { return }
        if satisfied {
            // Сеть вернулась — пробуем сразу, не дожидаясь интервала цикла.
            if isReconnecting { attemptReconnect() }
        } else {
            beginReconnecting()
        }
    }

    /// Помечает потерю связи и запускает бесконечный цикл переподключения.
    private func beginReconnecting() {
        guard shouldBePlaying, !isReconnecting else { return }
        isReconnecting = true
        isLoading = false
        stallWatchdog?.cancel()
        stallWatchdog = nil
        updateNowPlayingInfo()
        startBlinking()
        startReconnectLoop()
    }

    private func startBlinking() {
        guard blinkTask == nil else { return }
        blinkTask = Task { @MainActor [weak self] in
            while let self, self.isReconnecting, !Task.isCancelled {
                self.statusBlink.toggle()
                try? await Task.sleep(for: Self.blinkInterval)
            }
        }
    }

    private func stopBlinking() {
        blinkTask?.cancel()
        blinkTask = nil
        statusBlink = false
    }

    private func startReconnectLoop() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            while let self, self.shouldBePlaying, self.isReconnecting, !Task.isCancelled {
                try? await Task.sleep(for: Self.reconnectInterval)
                guard self.shouldBePlaying, self.isReconnecting, !Task.isCancelled else { return }
                self.attemptReconnect()
            }
        }
    }

    private func attemptReconnect() {
        guard shouldBePlaying, let station = currentStation else { return }
        loadAndPlay(station: station)
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /// Если буферизация затянулась дольше stallTimeout — считаем поток зависшим и переподключаемся.
    private func armStallWatchdog() {
        guard stallWatchdog == nil, !isReconnecting else { return }
        stallWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard let self, !Task.isCancelled else { return }
            self.stallWatchdog = nil
            if self.shouldBePlaying, self.player?.timeControlStatus != .playing {
                self.beginReconnecting()
            }
        }
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
        guard let url = URL(string: urlString) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        currentArtworkData = data
        currentArtworkImage = NSImage(data: data)
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

    func playNextStation() {
        let stations = store.stations
        guard let current = currentStation,
            let idx = stations.firstIndex(where: { $0.id == current.id }) else {
            if let first = stations.first { play(station: first) }
            return
        }
        play(station: stations[(idx + 1) % stations.count])
    }

    func playPreviousStation() {
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
