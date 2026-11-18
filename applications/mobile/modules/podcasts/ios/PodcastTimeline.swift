// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A timeline of how fast ads are skipped on a stream, for the phone proof. Every line is
// "<what> +<seconds since the tap>s". Filter in Console.app (the phone connected) with
// subsystem `StorytellerLofi` and category `AdTimeline`, or on a Mac:
// `log stream --predicate 'subsystem == "StorytellerLofi" AND category == "AdTimeline"'`.
// The lines are kept at the "notice" level, so they stay in the log after the run.
import Foundation
import os

enum PodcastTimeline {
  static let logger = Logger(subsystem: "StorytellerLofi", category: "AdTimeline")
  private static let lock = NSLock()
  private static var taps: [String: Date] = [:]
  private static var skipped: Set<String> = []

  /// The listener tapped Play on a stream that is fetched into a file.
  static func tap(_ episodeId: String) {
    lock.withLock {
      taps = [episodeId: Date()]
      skipped = []
    }
    logger.notice("tap +0.00s \(episodeId, privacy: .public)")
  }

  /// One step of the timeline. Nothing is logged for an episode that was not tapped here.
  static func mark(_ episodeId: String, _ what: String) {
    guard let at = lock.withLock({ taps[episodeId] }) else { return }
    logger.notice("\(what, privacy: .public) +\(String(format: "%.2f", Date().timeIntervalSince(at)), privacy: .public)s")
  }

  /// The first skip of the stream (later ones are not part of the proof).
  static func firstSkip(_ episodeId: String) {
    guard lock.withLock({ taps[episodeId] != nil && skipped.insert(episodeId).inserted }) else { return }
    mark(episodeId, "first skip")
  }
}
