// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The sleep timer in Swift, so it also works with the screen locked. The rules (time left,
// extending, the fade, stopping before the next episode) are PodcastPlayback's SleepTimer.
// Here it is only wired to the player: the last 10 seconds turn the volume down, then the
// player pauses and the volume is put back for the next play.

import Foundation
import PodcastPlayback

/// The timer that is set, if any. Kept here so PodcastPlayer.swift needs no new property.
@MainActor
final class SleepState {
  static let shared = SleepState()
  var timer: SleepTimer?
  /// Wakes at the end of a countdown, also when nothing is playing to tick.
  var alarm: Task<Void, Never>?
}

@MainActor
extension PodcastPlayer {
  private static var clock: Double { Date().timeIntervalSince1970 }

  /// What JavaScript is told: `kind` is "none", "countdown" or "endOfEpisode"; `endsAt` is
  /// milliseconds since 1970 for a countdown.
  func sleepObject() -> [String: Any] {
    guard let timer = SleepState.shared.timer else { return ["kind": "none"] }
    switch timer.kind {
    case .countdown: return ["kind": "countdown", "endsAt": timer.endsAt * 1000]
    case .endOfEpisode: return ["kind": "endOfEpisode"]
    case .endOfChapter: return ["kind": "endOfChapter", "chapterEnd": timer.endsAt]
    }
  }

  /// Starts a countdown of this many minutes (replacing any timer). Returns false for a time
  /// that is not usable.
  @discardableResult
  func startSleep(minutes: Double) -> Bool {
    guard let timer = SleepTimer.countdown(minutes: minutes, from: Self.clock) else {
      return false
    }
    setSleep(timer)
    return true
  }

  func sleepUntilEndOfEpisode() { setSleep(.endOfEpisode) }

  /// Stops where the chapter playing now ends. False when the episode has no chapter here.
  @discardableResult
  func sleepUntilEndOfChapter() -> Bool {
    guard let end = currentChapterEnd(), let timer = SleepTimer.endOfChapter(endingAt: end)
    else { return false }
    setSleep(timer)
    return true
  }

  /// Adds 5 minutes while a countdown runs.
  func extendSleep() {
    guard let timer = SleepState.shared.timer, timer.kind == .countdown else { return }
    setSleep(timer.extended(at: Self.clock))
  }

  func cancelSleep() {
    SleepState.shared.alarm?.cancel()
    SleepState.shared.timer = nil
    player.volume = 1
    sink?("onSleepTimerChange", sleepObject())
  }

  /// Called with every tick of the clock: turns the volume down in the last 10 seconds.
  func sleepTick() {
    guard let timer = SleepState.shared.timer else { return }
    if timer.kind == .endOfChapter {
      chapterSleepTick(timer)
      return
    }
    guard timer.kind == .countdown else { return }
    if timer.isFinished(at: Self.clock) {
      sleepRanOut()
    } else {
      player.volume = Float(timer.volume(at: Self.clock))
    }
  }

  /// An episode ended. A timer set for its end stops here and the queue is not started;
  /// returns whether that happened.
  func sleepStopsQueue() -> Bool {
    guard SleepState.shared.timer?.stopsBeforeNextEpisode == true else { return false }
    cancelSleep()
    return true
  }

  /// The end-of-chapter timer, checked with every tick: pause at the chapter's end, and let the
  /// timer go when the listener has moved well past it.
  private func chapterSleepTick(_ timer: SleepTimer) {
    guard wantsToPlay else { return }
    switch timer.chapterStatus(at: position) {
    case .waiting: break
    case .reached:
      SleepState.shared.timer = nil
      pause()
      sink?("onSleepTimerChange", sleepObject())
    case .passed: cancelSleep()
    }
  }

  private func setSleep(_ timer: SleepTimer) {
    SleepState.shared.alarm?.cancel()
    SleepState.shared.timer = timer
    // An extension during the fade brings the volume back.
    player.volume = Float(timer.volume(at: Self.clock))
    if timer.kind == .countdown { scheduleAlarm(timer) }
    sink?("onSleepTimerChange", sleepObject())
  }

  private func scheduleAlarm(_ timer: SleepTimer) {
    let wait = max(0, timer.endsAt - Self.clock)
    SleepState.shared.alarm = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.sleepRanOut()
    }
  }

  /// The countdown is over: pause, then bring the volume back for the next play.
  private func sleepRanOut() {
    guard let timer = SleepState.shared.timer, timer.isFinished(at: Self.clock) else { return }
    SleepState.shared.alarm?.cancel()
    SleepState.shared.timer = nil
    pause()
    player.volume = 1
    sink?("onSleepTimerChange", sleepObject())
  }
}
