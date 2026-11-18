// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The one podcast player. It streams an episode with AVPlayer and tells the app what it is
// doing. The rules (where to resume, how far to skip, the speed range, who owns the lock
// screen) come from PodcastPlayback; the lock screen is PodcastLockScreen; the book is
// watched through LofiNarratorBridge so only one of the two plays at a time.

import AVFoundation
import Foundation
import MediaPlayer
import PodcastAds
import PodcastPlayback
import Readium

@MainActor
final class PodcastPlayer {
  static let shared = PodcastPlayer()

  /// Where events go: the module's `sendEvent`.
  var sink: (@MainActor (String, [String: Any]) -> Void)?

  let player = AVPlayer()
  let lockScreen = PodcastLockScreen()
  private var episodeId: String?
  private var knownDuration: Double?
  var speed = Speed.normal
  /// The show's settings for the loaded episode (PodcastPlayer+ShowSettings.swift).
  var showState = ShowPlaybackState()
  /// What the listener asked for: playing, even while the stream is still buffering.
  var wantsToPlay = false
  private var timeObserver: Any?
  private var playerObservation: NSKeyValueObservation?
  private var itemObservation: NSKeyValueObservation?
  private var itemObservers: [NSObjectProtocol] = []
  var watchingBook = false
  /// Up Next: the episodes after this one (see PodcastPlayer+UpNext.swift).
  var queue = UpNextQueue.load(from: UpNextFile.url)
  /// The episode loaded now, as a queue item, so it can go back to the queue.
  var current: QueueItem?
  /// The loaded episode played to its end.
  var currentEnded = false
  /// Skips the saved ads of a downloaded episode (see PodcastPlayer+Ads.swift).
  lazy var adSkipping = PodcastAdSkipping(self)
  /// Voice boost and silence trimming (see PodcastPlayer+Sound.swift).
  lazy var sound = PodcastSound(self)
  private var ticks = 0
  /// Feeds the loaded item from its own download, while there is one (PodcastPlayer+Stream.swift).
  var streamDownload: PodcastStreamDownload?
  /// The loaded item is the episode's plain address, so no ad is skipped (the app says so).
  var playsPlainAddress = false
  /// Where the loaded episode was told to start (PodcastPlayer+Stream.swift's fallback).
  var itemStart = 0.0
  /// A seek has been asked for and has not landed. `player.currentTime()` is the old place until
  /// it does (for a resume on a stream, until the bytes up to the place have arrived), so an ad
  /// is not left from it (PodcastPlayer+Ads.swift).
  var seekPending = false
  /// Where the latest seek is going, which is where the episode is as soon as it lands.
  var seekTarget = 0.0
  /// Counts the seeks, so only the latest one's completion ends the pending state.
  private var seekCount = 0
  /// Play is waiting a moment for the first look at a stream's start (PodcastPlayer+StartHold).
  var startHold: PodcastStartHold?
  /// The last good place and whether the item failed, so Play can start it again
  /// (PodcastPlayer+Reload.swift).
  var recovery = PlayRecovery()

  private init() {
    lockScreen.onCommand = { [weak self] command in self?.handle(command) }
    observeSession()
    // Starts watching the network, so "on Wi-Fi now" is known by the first play.
    _ = PodcastNetwork.shared
  }

  // MARK: Loading

  struct Episode {
    var id: String
    var url: URL
    var title: String
    var showTitle: String
    var artworkUrl: String?
    var savedPosition: Double
    var duration: Double?
    var played: Bool
    var autoplay: Bool
    /// The feed's audio type, kept for Up Next.
    var type = ""
    /// The show, for its settings.
    var showId: String?
    /// The feed's JSON chapters file (PodcastPlayer+Chapters.swift).
    var chaptersUrl: String?
    /// The app asks to play through the episode's own download (PodcastPlayer+Stream.swift).
    var playThroughDownload = false
    /// The feed's language, for the transcript of an episode that starts downloading here.
    var language: String?
    /// The episode's notes and the show's web page, for the sponsors the ad rules look for.
    var notes: String?
    var showLink: String?
    /// The address to keep in Up Next when `url` is a local file (an episode started from the
    /// queue plays its download), so the item can go back to the queue and be fetched again.
    var queueURL: String?
  }

  /// The listener chose this episode. The one playing goes back to the top of Up Next.
  func load(_ episode: Episode) {
    queue.startedFromList(episode.id, previous: playingItem(), previousFinished: currentEnded)
    saveQueue()
    emitQueue()
    begin(episode)
  }

  /// Loads an episode and, unless told not to, starts it.
  func begin(_ episode: Episode) {
    // At once, not with the look at Up Next a few seconds from now (see PodcastDownloadAhead).
    PodcastDownloadAhead.shared.handOver(episode.id)
    cancelStartHold()
    watchTheBook()
    currentEnded = false
    current = QueueItem(
      id: episode.id, url: episode.queueURL ?? episode.url.absoluteString, type: episode.type,
      title: episode.title, showTitle: episode.showTitle, artworkUrl: episode.artworkUrl,
      duration: episode.duration, position: episode.savedPosition, showId: episode.showId,
      chaptersUrl: episode.chaptersUrl, language: episode.language)
    wantsToPlay = false
    player.pause()
    removeItemObservers()
    episodeId = episode.id
    knownDuration = episode.duration
    applyShowSettings(forShow: episode.showId)
    // The ads of this episode are remembered under its show (PodcastKnownAds).
    EpisodeShows.shared.remember(episode.showId, for: episode.id)

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
    } catch {
      emitError(episode.id, "The audio session couldn't start: \(error.localizedDescription)")
    }

    // A downloaded episode plays from its file; any other streams from its address, or from
    // its own download as it arrives.
    let item = makeItem(for: episode)
    // Keeps voices natural at any speed.
    item.audioTimePitchAlgorithm = .timeDomain
    player.defaultRate = Float(speed.value)
    forgetPendingSeek()
    player.replaceCurrentItem(with: item)
    watch(item)
    lockScreen.setEpisode(
      title: episode.title, showTitle: episode.showTitle, artworkUrl: episode.artworkUrl)

    let start = ShowRules.start(
      savedPosition: episode.savedPosition, duration: episode.duration, played: episode.played,
      intro: showState.settings.introSeconds)
    itemStart = start
    recovery.loaded(startingAt: start)
    if start > 0 { movePlayhead(to: start) }
    noteSaved(
      .skipping,
      audioSeconds: ListeningStats.introSkipped(
        savedPosition: episode.savedPosition, duration: episode.duration,
        played: episode.played, intro: showState.settings.introSeconds))
    adSkipping.begin(episode.id, startingAt: start)
    // The episode that plays is transcribed and checked for ads before the others.
    PodcastTranscriber.shared.prefer(episode.id)
    PodcastAdFinder.shared.prefer(episode.id)
    sound.begin(episode.id, startingAt: start)
    beginChapters(episode, startingAt: start)
    publish()
    if episode.autoplay { play() }
  }

  // MARK: Controls

  func play() {
    guard player.currentItem != nil else { return }
    if reloadIfFailed() { return }
    // A stream nothing is known about may wait a moment first; a second tap ends that wait.
    if holdTheStart() { return }
    startPlaying()
  }

  /// Starts the audio (the rest of Play, once any wait for a stream's first look is over).
  func startPlaying() {
    wantsToPlay = true
    try? AVAudioSession.sharedInstance().setActive(true)
    // A finished episode starts over. It must be finished by the clock and by the listener's place:
    // a resume past the feed's length is a seek on its way (the clock is behind it), and a scrub
    // back after the end is a seek on its way too (the place is behind it). Neither starts over.
    if let duration = currentDuration, position >= duration - 0.5, place >= duration - 0.5 {
      seek(to: 0)
    }
    rewindAfterLongPause()
    player.defaultRate = Float(speed.value)
    player.play()
    // An ad found while paused, with the playhead inside it, is left now (unless it was entered
    // by a seek, or a seek is still on its way).
    adSkipping.refresh()
    takeTheLockScreen()
    publish()
  }

  func pause() {
    cancelStartHold()
    wantsToPlay = false
    player.pause()
    publish()
  }

  func togglePlayPause() {
    // What the player really does decides, not what the listener last asked for: iOS can pause
    // it by itself (headphones out, a call), and then one press must play.
    if player.timeControlStatus != .paused { pause() } else { play() }
  }

  func seek(to seconds: Double) {
    let target = Skip.clamp(seconds, duration: currentDuration)
    adSkipping.seeked(to: target)
    sound.seeked(to: target)
    chapterSeeked(to: target)
    movePlayhead(to: target)
    recovery.moved(to: target)
    // Report the new place at once, before the seek has finished.
    publish(positionOverride: target)
  }

  /// Seeks exactly to `seconds` and notes that the seek is on its way. When the latest seek
  /// has landed, the place is published and ads are looked at again, because one that was found
  /// meanwhile may hold the place (the listener's own seek into an ad is still respected).
  func movePlayhead(to seconds: Double) {
    seekCount += 1
    let count = seekCount
    seekPending = true
    seekTarget = seconds
    player.seek(
      to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if count == self.seekCount {
          self.seekPending = false
          self.adSkipping.refresh()
        }
        self.publish()
      }
    }
  }

  /// The item is being replaced: seeks on the old one no longer count.
  func forgetPendingSeek() {
    seekCount += 1
    seekPending = false
  }

  func skip(by seconds: Double) {
    seek(to: Skip.target(from: place, by: seconds, duration: currentDuration))
  }

  /// Sets the speed (clamped to 0.5x to 3x in tenths) and returns the speed now in use.
  @discardableResult
  func setRate(_ rate: Double) -> Double {
    speed = Speed.clamped(rate)
    noteListenerSpeed()
    player.defaultRate = Float(speed.value)
    if player.timeControlStatus != .paused { player.rate = Float(speed.value) }
    publish()
    return speed.value
  }

  func state() -> [String: Any] { stateObject(position: place) }

  // MARK: Reading the player

  var position: Double {
    let seconds = player.currentTime().seconds
    return seconds.isFinite ? max(0, seconds) : 0
  }

  /// Where the episode is for the listener: where a seek that is on its way is going, else the
  /// clock, and after a failure the last good place. Used for what is shown, saved and skipped
  /// from. Ads, silence, chapters, the sleep timer and the statistics decide about audio that
  /// is heard, so they read `position`.
  var place: Double {
    let clock = Playhead.place(reported: position, seekPending: seekPending, seekTarget: seekTarget)
    return recovery.place(reported: clock)
  }

  var currentDuration: Double? {
    if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
      return seconds
    }
    return knownDuration
  }

  private func stateObject(position: Double) -> [String: Any] {
    var object: [String: Any] = [
      "position": position,
      "isPlaying": player.timeControlStatus == .playing,
      "isBuffering": startHold != nil
        || (wantsToPlay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate),
      "rate": speed.value,
      "streamsPlain": playsPlainAddress,
    ]
    if let episodeId { object["episodeId"] = episodeId }
    if let duration = currentDuration { object["duration"] = duration }
    if startHold != nil { object["checkingStart"] = true }
    return object
  }

  func publish(positionOverride: Double? = nil, refreshCard: Bool = true) {
    // A failed item's clock reads 0. The failure's own notice may still be on its way, so it is
    // noted here too, and the 0 is never sent as the place.
    if player.currentItem?.status == .failed { recovery.itemFailed() }
    let place = positionOverride ?? self.place
    sink?("onPlaybackState", stateObject(position: place))
    guard refreshCard else { return }
    lockScreen.update(
      position: place, duration: currentDuration, rate: speed.value,
      isPlaying: player.timeControlStatus == .playing)
  }

  private func emitError(_ id: String?, _ message: String) {
    sink?("onPlaybackError", ["episodeId": id ?? "", "message": message])
  }

  // MARK: Watching the player

  func watch(_ item: AVPlayerItem) {
    if timeObserver == nil {
      timeObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.tick() }
      }
      playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.playStateChanged() }
      }
    }
    itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      let failure = item.status == .failed ? (item.error?.localizedDescription ?? "") : nil
      Task { @MainActor in self?.itemStatusChanged(failure) }
    }
    let center = NotificationCenter.default
    itemObservers.append(
      center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) {
        [weak self] _ in
        Task { @MainActor in self?.ended() }
      })
    itemObservers.append(
      center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) {
        [weak self] note in
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        let message = error?.localizedDescription ?? "The episode stopped playing."
        Task { @MainActor in self?.failed(message) }
      })
  }

  func removeItemObservers() {
    itemObservation = nil
    for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
    itemObservers = []
  }

  private func tick() {
    ticks += 1
    // Only an item that is ready has a clock worth remembering (a failing one reads 0).
    if player.currentItem?.status == .readyToPlay { recovery.noted(place) }
    statsTick()
    endAtOutroIfReached()
    chapterTick()
    sleepTick()
    // The lock screen card keeps its own clock, so it is rewritten only now and then.
    publish(refreshCard: ticks % 10 == 0)
  }

  private func playStateChanged() {
    if player.timeControlStatus == .playing { takeTheLockScreen() }
    if player.timeControlStatus == .paused {
      notePaused()
      StatsStore.shared.flush()
    }
    // Transcribing may run while a podcast plays, which keeps the app alive.
    PodcastTranscriber.shared.playbackChanged(isPlaying: player.timeControlStatus == .playing)
    publish()
  }

  private func itemStatusChanged(_ failure: String?) {
    if let failure {
      wantsToPlay = false
      recovery.itemFailed()
      emitError(episodeId, readableFailure(failure))
    }
    publish()
  }

  private func readableFailure(_ message: String) -> String {
    message.isEmpty ? "This episode couldn't be played." : "This episode couldn't be played: \(message)"
  }

  private func failed(_ message: String) {
    wantsToPlay = false
    recovery.itemFailed()
    emitError(episodeId, readableFailure(message))
    publish()
  }

  func ended() {
    wantsToPlay = false
    currentEnded = true
    let duration = currentDuration ?? position
    sink?(
      "onPlaybackEnded",
      ["episodeId": episodeId ?? "", "position": duration, "duration": duration, "played": true])
    // The next queued episode starts here in Swift, so it also starts with the screen locked,
    // unless the sleep timer was set for the end of this one.
    if !sleepStopsQueue(), startNextInQueue() { return }
    publish(positionOverride: duration)
  }

  /// A call or another app's audio paused the player; when it is over and the system says
  /// to carry on, carry on, if the listener had not paused.
  private func observeSession() {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] note in
      guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        AVAudioSession.InterruptionType(rawValue: raw) == .ended
      else { return }
      let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
      Task { @MainActor in
        guard let self, self.wantsToPlay, self.lockScreen.owner.current == .podcast else { return }
        if shouldResume {
          self.play()
        } else if self.player.timeControlStatus == .paused {
          // The system did not say to carry on: it is paused for good until the listener plays.
          self.wantsToPlay = false
          self.publish()
        }
      }
    }
    // Headphones or a Bluetooth speaker went away: pause instead of playing on the speaker.
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] note in
      guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
      else { return }
      Task { @MainActor in
        guard let self, self.wantsToPlay || self.player.timeControlStatus != .paused else { return }
        self.pause()
      }
    }
  }
}
