// LOFI-FORK: when a stream's head scan and whole-file pass know what, for the scorecard's stream
// replay (see FORK.md and StreamReplay.swift). Foundation only.
import Foundation
import PodcastTranscripts

/// One moment at which the phone's list of ads for a stream may change.
public struct StreamEvent: Equatable, Sendable {
  /// Wall seconds since the tap.
  public var at: Double
  /// Seconds of the transcript the local finders have seen.
  public var reach: Double
  /// For a head step: its length, which decides how much of the model's answer counts.
  public var headStep: Double?
  /// Whether the model's answers (within `reach`) are part of this moment.
  public var modelAnswers: Bool
}

public enum StreamTimeline {
  /// The seconds of audio each step of the head scan covers for this show, none past the end.
  static func headSteps(_ plan: HeadPlan, duration: Double) -> [Double] {
    var seen: [Double] = []
    for step in plan.steps {
      let reach = min(step, duration)
      if reach > 0, !seen.contains(reach) { seen.append(reach) }
    }
    return seen
  }

  /// The moments of one episode: the head steps, then the whole-file pass's pieces from 0.
  /// `withModel` adds the model's own time and moments.
  public static func events(
    duration: Double, plan: HeadPlan, pace: StreamPace, withModel: Bool
  ) -> [StreamEvent] {
    guard duration > 0 else { return [] }
    var out: [StreamEvent] = []
    var previousReach = 0.0
    var free = 0.0  // when the scan is ready for its next step
    for (index, reach) in headSteps(plan, duration: duration).enumerated() {
      let ready = pace.connect + reach / pace.download
      let done = max(ready, free) + (reach - previousReach) / pace.speech + pace.stepOverhead
      out.append(StreamEvent(at: done, reach: reach, headStep: reach, modelAnswers: false))
      free = done
      let original = plan.steps.indices.contains(index) ? plan.steps[index] : reach
      if withModel, plan.modelSteps.contains(original) {
        free = done + pace.modelSeconds(forAudio: reach - previousReach)
        out.append(StreamEvent(at: free, reach: reach, headStep: reach, modelAnswers: true))
      }
      previousReach = reach
    }
    var reached = 0.0
    free = max(free, pace.connect + duration / pace.download)
    while reached < duration - 0.01 {
      let end = min(duration, reached + Pieces.length(after: reached))
      free += (end - reached) / pace.speech + pace.stepOverhead
      if withModel { free += pace.modelSeconds(forAudio: end - reached) }
      out.append(StreamEvent(at: free, reach: end, headStep: nil, modelAnswers: withModel))
      reached = end
    }
    return out
  }

  /// The wall second at which playback starts: at the first byte for a show that is not waited
  /// for, else when the first look is done or the hold ends, whichever comes first.
  public static func playStart(
    habits: ShowHabits, show: String, firstLookDone: Double?, pace: StreamPace,
    settings: AdSkipSettings = AdSkipSettings()
  ) -> Double {
    let clean = StartHold.startsClean(habits: habits, show: show, own: false)
    let waits = StartHold.wanted(
      skipAds: settings.skipAds, playsOwnDownload: true, startsAt: 0, hasSavedAds: false,
      showStartsClean: clean, appActive: true)
    guard waits else { return pace.connect }
    let hold = StartHold.longest(habits: habits, show: show)
    return max(pace.connect, min(firstLookDone ?? hold, hold))
  }
}
