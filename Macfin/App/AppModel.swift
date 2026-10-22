import AVFoundation
import AVKit
import Foundation
import Observation
import SwiftUI

@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase { case signedOut, ready }

    private(set) var phase: Phase
    private(set) var client: JellyfinClient?
    private(set) var movies: [Item] = []
    private(set) var series: [Item] = []
    /// Episodes of the shows opened so far, by series id, in airing order.
    private(set) var episodes: [String: [Item]] = [:]
    private(set) var nextUp: [Item] = []
    private(set) var resume: [Item] = []
    private(set) var latest: [Item] = []
    private(set) var loadError: String?
    private(set) var hasLoaded = false
    private(set) var playback: PlaybackSession?
    private(set) var detail: Item?
    /// Kept here so the library scroll offset survives the player replacing it.
    var homeScroll = ScrollPosition(edge: .top)

    static let defaultServer = URL(string: "http://127.0.0.1:8096")!

    private init() {
        if let credentials = CredentialStore.load() {
            client = JellyfinClient(credentials: credentials)
            phase = .ready
        } else {
            phase = .signedOut
        }
    }

    var userName: String? { client?.credentials?.userName }

    /// Hero item: what's being watched, else the latest addition.
    var featured: Item? { resume.first ?? latest.first ?? movies.first }

    /// Freshest copy of an item (user data changes after playback).
    func current(_ item: Item) -> Item {
        if item.isEpisode, let seriesId = item.seriesId {
            return episodes[seriesId]?.first { $0.id == item.id } ?? item
        }
        return (item.isSeries ? series : movies).first { $0.id == item.id } ?? item
    }

    /// "Up Next" without the episodes already in "Continue Watching".
    var upNext: [Item] { nextUp.filter { next in !resume.contains { $0.id == next.id } } }

    func loadEpisodes(of seriesId: String) async {
        guard let client, let list = try? await client.episodes(ofSeries: seriesId) else { return }
        episodes[seriesId] = list
    }

    /// Episode that follows `item` in its show, across seasons.
    func episode(after item: Item) async -> Item? {
        guard item.isEpisode, let seriesId = item.seriesId else { return nil }
        if episodes[seriesId] == nil { await loadEpisodes(of: seriesId) }
        guard let list = episodes[seriesId], let index = list.firstIndex(where: { $0.id == item.id }),
              index + 1 < list.count else { return nil }
        return list[index + 1]
    }

    #if DEBUG
    /// Trickplay preview forced by DemoAutomation for screenshots.
    var demoPreviewTime: Double?

    /// Session for this launch only, used by DemoAutomation: nothing is saved to the keychain.
    func useDemoSession(_ credentials: Credentials) {
        client = JellyfinClient(credentials: credentials)
        phase = .ready
    }
    #endif

    func signIn(_ credentials: Credentials) {
        CredentialStore.save(credentials)
        client = JellyfinClient(credentials: credentials)
        withAnimation(Tokens.Motion.page) { phase = .ready }
        Task { await refresh() }
    }

    func signOut() async {
        await client?.logout()
        CredentialStore.delete()
        client = nil
        movies = []; series = []; episodes = [:]; nextUp = []; resume = []; latest = []
        hasLoaded = false
        withAnimation(Tokens.Motion.page) { phase = .signedOut }
    }

    func refresh() async {
        guard let client else { return }
        do {
            async let movies = client.movies()
            async let series = client.series()
            async let nextUp = client.nextUp()
            async let resume = client.resume()
            async let latest = client.latest()
            (self.movies, self.series, self.nextUp, self.resume, self.latest) = try await (movies, series, nextUp, resume, latest)
            loadError = nil
            // Episode lists already shown carry watched marks and progress that playback just changed
            for seriesId in episodes.keys { await loadEpisodes(of: seriesId) }
        } catch JellyfinError.unauthorized {
            await signOut()
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }

    func setPlayed(_ item: Item, _ played: Bool) async {
        try? await client?.setPlayed(item, played)
        await refresh()
    }

    var showsQuickConnect = false

    // MARK: Navigation

    /// An episode opens its show's page.
    func openDetail(_ item: Item) {
        var target = item
        if item.isEpisode, let seriesId = item.seriesId {
            guard let show = series.first(where: { $0.id == seriesId }) else { return }
            target = show
        }
        withAnimation(Tokens.Motion.page) { detail = target }
    }
    func closeDetail() { withAnimation(Tokens.Motion.page) { detail = nil } }

    // MARK: Playback

    func play(_ item: Item, fromStart: Bool = false) {
        guard let client, playback == nil else { return }
        let item = current(item)
        let session = PlaybackSession(item: item, client: client, startTicks: fromStart ? 0 : item.positionTicks)
        withAnimation(Tokens.Motion.page) { playback = session }
        if item.isEpisode { Task { session.next = await episode(after: item) } }
    }

    /// Ends the current episode and starts the following one from its beginning.
    func playNext() async {
        guard let next = playback?.next else { return }
        await closePlayer()
        play(next, fromStart: true)
    }

    func closePlayer() async {
        guard let playback else { return }
        withAnimation(Tokens.Motion.page) { self.playback = nil }
        await playback.stop()
        await refresh()
    }
}

/// One playback: AVPlayer + progress reports to Jellyfin every 10 s, on pause and on stop.
@Observable
final class PlaybackSession {
    let item: Item
    let player: AVPlayer
    let client: JellyfinClient
    private let sessionId = UUID().uuidString
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stopped = false
    private var clockObserver: Any?

    /// Mirrored player state for the custom controls.
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if player.timeControlStatus != .paused { player.rate = rate }
        }
    }
    /// Following episode of the same show, loaded after playback starts.
    var next: Item?
    /// Set by the video surface once its AVPlayerLayer exists.
    var pictureInPicture: AVPictureInPictureController?

    init(item: Item, client: JellyfinClient, startTicks: Int64) {
        self.item = item
        self.client = client
        player = AVPlayer(url: client.streamURL(item))
        duration = Double(item.runTimeTicks ?? 0) / 10_000_000
        time = Double(startTicks) / 10_000_000
        clockObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] now in
            MainActor.assumeIsolated { self?.tick(now) }
        }
        Task { await start(at: startTicks) }
    }

    private var positionTicks: Int64 {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? Int64(seconds * 10_000_000) : 0
    }

    private var isPaused: Bool { player.timeControlStatus == .paused }

    private func start(at ticks: Int64) async {
        if ticks > 0 {
            await player.seek(to: CMTime(value: ticks, timescale: 10_000_000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        await client.report(.start, item: item, sessionId: sessionId, positionTicks: ticks, paused: false)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendProgress() }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPlaying = self.player.timeControlStatus != .paused
                    self.sendProgress()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: player.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if self?.next != nil { await AppModel.shared.playNext() } else { await AppModel.shared.closePlayer() }
            }
        }
    }

    private func tick(_ now: CMTime) {
        if now.seconds.isFinite { time = now.seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
    }

    // MARK: Controls

    func togglePlay() {
        // Update the icon immediately instead of waiting for the KVO round trip.
        if player.timeControlStatus == .paused { isPlaying = true; player.play() } else { isPlaying = false; player.pause() }
    }

    func seek(to seconds: Double) async {
        let target = min(max(seconds, 0), max(duration - 1, 0))
        time = target
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        sendProgress()
    }

    func skip(_ delta: Double) { Task { await seek(to: time + delta) } }

    func togglePictureInPicture() {
        guard let pip = pictureInPicture else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    private func sendProgress() {
        guard !stopped, player.timeControlStatus != .waitingToPlayAtSpecifiedRate else { return }
        let ticks = positionTicks, paused = isPaused
        Task { await client.report(.progress, item: item, sessionId: sessionId, positionTicks: ticks, paused: paused) }
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let clockObserver { player.removeTimeObserver(clockObserver) }
        pictureInPicture?.stopPictureInPicture()
        statusObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        await client.report(.stopped, item: item, sessionId: sessionId, positionTicks: positionTicks, paused: true)
        player.replaceCurrentItem(with: nil)
    }
}
