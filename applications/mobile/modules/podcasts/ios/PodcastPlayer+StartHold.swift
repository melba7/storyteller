// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A short wait before a never-checked stream starts (PodcastAds' StartHold). When Skip ads is on
// and an episode plays through its own download from 0:00, with nothing saved for it and a show
// that is not known to start clean, Play waits for the first of: the head scan's first look
// (the 15 second step's rules and the memory of ads; also reported when the show's own opening
// words were heard), the scan ending, 3 seconds from the tap, or a second tap on Play. An ad
// that holds 0:00 is then left (the player reads the ads before the wait ends), and the audio
// starts after it. The 3 second timer is the player's own, so nothing the scan does, or fails
// to do, can keep the audio from starting.
import AVFoundation
import Foundation
import PodcastAds
import UIKit

/// One wait: the rules of StartHold and the timer that always ends it.
@MainActor
final class PodcastStartHold {
  let episodeId: String
  private var hold = StartHold()
  private var timer: Task<Void, Never>?
  private let onRelease: @MainActor (StartHold.Release) -> Void

  init(episodeId: String, onRelease: @escaping @MainActor (StartHold.Release) -> Void) {
    self.episodeId = episodeId
    self.onRelease = onRelease
  }

  /// Starts the timer that ends the wait after `StartHold.longest` seconds, whatever happens.
  func begin() {
    timer = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(StartHold.longest * 1_000_000_000))
      } catch {
        return  // cancelled: the wait ended another way
      }
      guard let self else { return }
      finish(hold.tick(elapsed: StartHold.longest))
    }
  }

  func verdict() { finish(hold.verdict()) }
  func showBegan() { finish(hold.showBegan()) }
  func scanEnded() { finish(hold.scanEnded()) }
  func tappedAgain() { finish(hold.tappedAgain()) }

  /// Ends the wait without playing (the listener paused, or another episode was loaded).
  func cancel() {
    timer?.cancel()
    timer = nil
  }

  private func finish(_ reason: StartHold.Release?) {
    guard let reason else { return }
    cancel()
    onRelease(reason)
  }
}

extension PodcastPlayer {
  /// Play was pressed. True when the player takes over: it either starts a wait, or (a second
  /// tap) ends the one that is on. False when playing should go on as usual.
  func holdTheStart() -> Bool {
    if let hold = startHold {
      hold.tappedAgain()
      return true
    }
    guard let loader = streamDownload, let id = current?.id, loader.episodeId == id else {
      return false
    }
    let show = current?.showId
    let startsClean = show.map { PodcastShowStarts.shared.startsClean(show: $0) } ?? false
    let wanted = StartHold.wanted(
      skipAds: adSkipping.skipsAds, playsOwnDownload: !playsPlainAddress,
      startsAt: seekPending ? itemStart : position,
      // A stream whose first look is done, or whose scan is over, has said what it has: the same
      // wait would never be answered, also when the look found no ad and so saved no file.
      hasSavedAds: adSkipping.hasSavedAds || loader.head.hasChecked, showStartsClean: startsClean,
      // With the screen locked or the app away, iOS may suspend the app before the 3 second timer
      // fires, and an episode that never starts is worse than one that plays its first ad. That
      // is the case when the next episode of Up Next starts by itself and for Play on the lock
      // screen.
      appActive: UIApplication.shared.applicationState == .active)
    guard wanted else { return false }
    let hold = PodcastStartHold(episodeId: id) { [weak self] reason in self?.startHoldOver(reason) }
    startHold = hold
    // The listener wants to play: an ad found now, with the playhead inside it, is left at once.
    wantsToPlay = true
    try? AVAudioSession.sharedInstance().setActive(true)
    PodcastTimeline.mark(id, "start held")
    hold.begin()
    publish()
    return true
  }

  /// The wait is over: the audio starts, unless the episode was changed or paused meanwhile.
  func startHoldOver(_ reason: StartHold.Release) {
    guard let hold = startHold else { return }
    startHold = nil
    PodcastTimeline.mark(hold.episodeId, "start released: \(reason)")
    guard wantsToPlay, current?.id == hold.episodeId else { return publish() }
    startPlaying()
  }

  /// The first look at the stream's start is done. The ads it found are read first, so an ad that
  /// holds 0:00 is left before the audio starts.
  func startHoldVerdict(_ episodeId: String) {
    guard let hold = startHold, hold.episodeId == episodeId else { return }
    adSkipping.refresh()
    hold.verdict()
  }

  /// The first look at the stream's start is done and it heard the words the show opens with: the
  /// show has begun. The ads it found are read first, as for a verdict.
  func startHoldShowBegan(_ episodeId: String) {
    guard let hold = startHold, hold.episodeId == episodeId else { return }
    adSkipping.refresh()
    hold.showBegan()
  }

  /// The head scan of the stream is over.
  func startHoldScanEnded(_ episodeId: String) {
    if let hold = startHold, hold.episodeId == episodeId { hold.scanEnded() }
  }

  /// The listener paused or another episode was loaded: no wait goes on, and none starts audio.
  func cancelStartHold() {
    startHold?.cancel()
    startHold = nil
  }
}
