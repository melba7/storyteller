// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A show's own playback settings (PodcastPlayback's ShowRules), which have to work with the
// screen locked and no JavaScript running. The app writes `Podcasts/show-settings.json`, a
// map from show id to settings, whenever a setting changes and in full at startup; the
// player reads it when an episode begins. It applies the show's speed and skips the intro
// then, and ends the episode early at the outro as if it had played to its end, so Up Next
// goes on.

import Foundation
import PodcastPlayback

enum ShowSettingsStore {
  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("show-settings.json")
  }

  /// Saves the whole map the app sends (a JSON object keyed by show id). False when the text
  /// is not that.
  static func write(json: String) -> Bool {
    guard let settings = ShowSettingsFile.decode(json) else { return false }
    do {
      try ShowSettingsFile.save(settings, to: url)
      return true
    } catch {
      NSLog("Podcasts: the show settings could not be saved: \(error)")
      return false
    }
  }
}

/// What the loaded episode's show asks for.
struct ShowPlaybackState {
  var settings = ShowPlaybackSettings()
  /// The speed the listener chose in the player; a show's own speed does not replace it.
  var listenerSpeed = Speed.normal
  var showSpeedActive = false
  /// Where the outro begins for the loaded episode, if it has one.
  var outroStart: Double?
  var outroHandled = false
}

@MainActor
extension PodcastPlayer {
  /// Reads the show's settings and applies its speed. Called as an episode is loaded.
  func applyShowSettings(forShow showId: String?) {
    let settings = showId.flatMap { ShowSettingsFile.load(from: ShowSettingsStore.url)[$0] }
      ?? ShowPlaybackSettings()
    showState.settings = settings
    showState.outroHandled = false
    showState.showSpeedActive = settings.speed != nil
    speed = ShowRules.speed(show: settings.speed, player: showState.listenerSpeed)
    refreshOutro()
  }

  /// The listener changed the speed in the player. That is their speed from now on, unless
  /// this show has its own, which only lasts for this episode.
  func noteListenerSpeed() {
    if !showState.showSpeedActive { showState.listenerSpeed = speed }
  }

  /// Works out where the outro begins, once the length is known.
  private func refreshOutro() {
    showState.outroStart = ShowRules.outroStart(
      duration: currentDuration, outro: showState.settings.outroSeconds,
      intro: showState.settings.introSeconds)
  }

  /// Called every half second: ends the episode when playing reaches the outro.
  func endAtOutroIfReached() {
    guard !showState.outroHandled, showState.settings.outroSeconds > 0, wantsToPlay else { return }
    if showState.outroStart == nil { refreshOutro() }
    guard ShowRules.shouldEnd(position: position, outroStart: showState.outroStart) else { return }
    showState.outroHandled = true
    if let duration = currentDuration { noteSaved(.skipping, audioSeconds: duration - position) }
    player.pause()
    ended()
  }
}
