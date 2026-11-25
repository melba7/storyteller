// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A timeline of how fast ads are skipped on a stream, for the phone proof. Every line is
// "<what> +<seconds since the tap>s". Filter in Console.app (the phone connected) with
// subsystem `StorytellerLofi` and category `AdTimeline`, or on a Mac:
// `log stream --predicate 'subsystem == "StorytellerLofi" AND category == "AdTimeline"'`.
// The lines are kept at the "notice" level, so they stay in the log after the run.
//
// Every mark is also a line in the ad finder's diary (`ad-diary.jsonl`, see PodcastSkipLog.swift
// and `AdDiary` in PodcastAds), for any episode and with or without a tap, so "Send skip log"
// can say what the head scan and the model did. A play that starts is a line in the play diary.
import Foundation
import os

enum PodcastTimeline {
  static let logger = Logger(subsystem: "StorytellerLofi", category: "AdTimeline")
  private static let lock = NSLock()
  private static var taps: [String: Date] = [:]
  private static var skipped: Set<String> = []
  /// The episode whose play was last noted in the play diary, so a pause and a resume of it is
  /// one play.
  private static var lastPlayed: String?

  /// Play started on `episodeId`. The first start of an episode, after another one was played, is
  /// a line in the play diary on how it stood (ready, partly, or a stream; see `PlayDiary`).
  static func playStarted(_ episodeId: String, isStream: Bool, duration: Double?) {
    let isNew = lock.withLock { () -> Bool in
      if lastPlayed == episodeId { return false }
      lastPlayed = episodeId
      return true
    }
    if isNew { SkipLogFile.appendPlayStart(episodeId, isStream: isStream, duration: duration) }
  }

  /// The listener tapped Play on a stream that is fetched into a file.
  static func tap(_ episodeId: String) {
    lock.withLock {
      taps = [episodeId: Date()]
      skipped = []
    }
    SkipLogFile.appendDiary(episodeId, "play tapped on a stream")
    logger.notice("tap +0.00s \(episodeId, privacy: .public)")
  }

  /// Seconds since the tap on Play of this episode, or nil when it was not tapped here (the
  /// skip log keeps it).
  static func secondsSinceTap(_ episodeId: String) -> Double? {
    lock.withLock { taps[episodeId] }.map { Date().timeIntervalSince($0) }
  }

  /// One step of the timeline. The diary keeps every step; the system log gets nothing for an
  /// episode that was not tapped here.
  static func mark(_ episodeId: String, _ what: String) {
    SkipLogFile.appendDiary(episodeId, what)
    guard let at = lock.withLock({ taps[episodeId] }) else { return }
    logger.notice("\(what, privacy: .public) +\(String(format: "%.2f", Date().timeIntervalSince(at)), privacy: .public)s")
  }

  /// The first skip of the stream (later ones are not part of the proof).
  static func firstSkip(_ episodeId: String) {
    guard lock.withLock({ taps[episodeId] != nil && skipped.insert(episodeId).inserted }) else { return }
    mark(episodeId, "first skip")
  }
}
