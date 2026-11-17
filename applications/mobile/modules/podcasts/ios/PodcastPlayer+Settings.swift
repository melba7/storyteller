// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The listener's playback settings in the player. They are kept in UserDefaults because the
// player reads them with the screen locked and JavaScript not running. The rules (the choices,
// what next does, how far to rewind) are PodcastPlayback's PlaybackSettings and RewindRule.

import Foundation
import PodcastPlayback

enum PlaybackSettingsStore {
  private static let key = "podcasts.playbackSettings"

  /// The saved settings, or the defaults.
  static var current: PlaybackSettings {
    PlaybackSettings(values: UserDefaults.standard.dictionary(forKey: key) ?? [:])
  }

  /// Saves the settings (values that are not a choice fall back to their defaults) and
  /// returns what was kept.
  @discardableResult
  static func save(_ values: [String: Any]) -> PlaybackSettings {
    let settings = PlaybackSettings(values: values)
    UserDefaults.standard.set(settings.values, forKey: key)
    return settings
  }
}

/// When and where the player last paused, for the rewind after a long pause.
@MainActor
final class PauseNote {
  static let shared = PauseNote()
  var at: Date?
  var episodeId: String?
}

@MainActor
extension PodcastPlayer {
  /// The player went quiet (paused by the listener, a call or the sleep timer).
  func notePaused() {
    PauseNote.shared.at = Date()
    PauseNote.shared.episodeId = current?.id
  }

  /// Called just before playing: after a long pause, goes back a few seconds. Only for the
  /// same episode, so loading another one never starts before its saved place.
  func rewindAfterLongPause() {
    let note = PauseNote.shared
    defer { note.at = nil }
    guard let paused = note.at, note.episodeId == current?.id else { return }
    let back = RewindRule.seconds(
      pausedFor: Date().timeIntervalSince(paused),
      enabled: PlaybackSettingsStore.current.rewindAfterPause)
    if back > 0 { seek(to: position - back) }
  }

  /// The next button on the headphones or lock screen.
  func headphoneNext() {
    let settings = PlaybackSettingsStore.current
    switch settings.nextAction(queueHasNext: !queue.items.isEmpty) {
    case .skip(let seconds):
      skip(by: seconds)
    case .nextEpisode:
      // Nothing playable queued: skip instead.
      if !startNextInQueue() { skip(by: Double(settings.skipForward)) }
    }
  }

  /// The listener changed the settings: the lock screen's skip buttons follow.
  func settingsChanged() {
    lockScreen.refreshSkipIntervals()
  }
}
