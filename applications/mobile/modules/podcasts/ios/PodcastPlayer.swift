// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The one podcast player. It streams an episode with AVPlayer and tells the app what it is
// doing. The rules (where to resume, how far to skip, the speed range, who owns the lock
// screen) come from PodcastPlayback; the lock screen is PodcastLockScreen; the book is
// watched through LofiNarratorBridge so only one of the two plays at a time.

import AVFoundation
import Foundation
import MediaPlayer
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
  private var speed = Speed.normal
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
  private var ticks = 0

  private init() {
    lockScreen.onCommand = { [weak self] command in self?.handle(command) }
    observeSession()
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
    watchTheBook()
    currentEnded = false
    current = QueueItem(
      id: episode.id, url: episode.url.absoluteString, type: episode.type, title: episode.title,
      showTitle: episode.showTitle, artworkUrl: episode.artworkUrl, duration: episode.duration,
      position: episode.savedPosition)
    wantsToPlay = false
    player.pause()
    removeItemObservers()
    episodeId = episode.id
    knownDuration = episode.duration

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
    } catch {
      emitError(episode.id, "The audio session couldn't start: \(error.localizedDescription)")
    }

    // A downloaded episode plays from its file; any other streams from its address.
    let item = AVPlayerItem(url: PodcastDownloader.shared.localFile(for: episode.id) ?? episode.url)
    // Keeps voices natural at any speed.
    item.audioTimePitchAlgorithm = .timeDomain
    player.defaultRate = Float(speed.value)
    player.replaceCurrentItem(with: item)
    watch(item)
    lockScreen.setEpisode(
      title: episode.title, showTitle: episode.showTitle, artworkUrl: episode.artworkUrl)

    let start = ResumeRule.start(
      savedPosition: episode.savedPosition, duration: episode.duration, played: episode.played)
    if start > 0 {
      player.seek(
        to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero,
        toleranceAfter: .zero)
    }
    publish()
    if episode.autoplay { play() }
  }

  // MARK: Controls

  func play() {
    guard player.currentItem != nil else { return }
    wantsToPlay = true
    try? AVAudioSession.sharedInstance().setActive(true)
    // A finished episode starts over.
    if let duration = currentDuration, position >= duration - 0.5 { seek(to: 0) }
    player.defaultRate = Float(speed.value)
    player.play()
    takeTheLockScreen()
    publish()
  }

  func pause() {
    wantsToPlay = false
    player.pause()
    publish()
  }

  func togglePlayPause() {
    if wantsToPlay || player.timeControlStatus == .playing { pause() } else { play() }
  }

  func seek(to seconds: Double) {
    let target = Skip.clamp(seconds, duration: currentDuration)
    player.seek(
      to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      Task { @MainActor in self?.publish() }
    }
    // Report the new place at once, before the seek has finished.
    publish(positionOverride: target)
  }

  func skip(by seconds: Double) {
    seek(to: Skip.target(from: position, by: seconds, duration: currentDuration))
  }

  /// Sets the speed (clamped to 0.5x to 3x in tenths) and returns the speed now in use.
  @discardableResult
  func setRate(_ rate: Double) -> Double {
    speed = Speed.clamped(rate)
    player.defaultRate = Float(speed.value)
    if player.timeControlStatus != .paused { player.rate = Float(speed.value) }
    publish()
    return speed.value
  }

  func state() -> [String: Any] { stateObject(position: position) }

  // MARK: Reading the player

  var position: Double {
    let seconds = player.currentTime().seconds
    return seconds.isFinite ? max(0, seconds) : 0
  }

  private var currentDuration: Double? {
    if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
      return seconds
    }
    return knownDuration
  }

  private func stateObject(position: Double) -> [String: Any] {
    var object: [String: Any] = [
      "position": position,
      "isPlaying": player.timeControlStatus == .playing,
      "isBuffering": wantsToPlay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
      "rate": speed.value,
    ]
    if let episodeId { object["episodeId"] = episodeId }
    if let duration = currentDuration { object["duration"] = duration }
    return object
  }

  func publish(positionOverride: Double? = nil, refreshCard: Bool = true) {
    let place = positionOverride ?? position
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

  private func watch(_ item: AVPlayerItem) {
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

  private func removeItemObservers() {
    itemObservation = nil
    for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
    itemObservers = []
  }

  private func tick() {
    ticks += 1
    sleepTick()
    // The lock screen card keeps its own clock, so it is rewritten only now and then.
    publish(refreshCard: ticks % 10 == 0)
  }

  private func playStateChanged() {
    if player.timeControlStatus == .playing { takeTheLockScreen() }
    // Transcribing may run while a podcast plays, which keeps the app alive.
    PodcastTranscriber.shared.playbackChanged(isPlaying: player.timeControlStatus == .playing)
    publish()
  }

  private func itemStatusChanged(_ failure: String?) {
    if let failure {
      wantsToPlay = false
      emitError(episodeId, readableFailure(failure))
    }
    publish()
  }

  private func readableFailure(_ message: String) -> String {
    message.isEmpty ? "This episode couldn't be played." : "This episode couldn't be played: \(message)"
  }

  private func failed(_ message: String) {
    wantsToPlay = false
    emitError(episodeId, readableFailure(message))
    publish()
  }

  private func ended() {
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
        guard let self, shouldResume, self.wantsToPlay, self.lockScreen.owner.current == .podcast
        else { return }
        self.play()
      }
    }
  }
}
