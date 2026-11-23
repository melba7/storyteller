// LOFI-FORK: scores the stream replay over the teaching episodes (see FORK.md, StreamReplay.swift
// and AdBar.swift). Foundation only.
import Foundation
import PodcastTranscripts

/// The bar of a row when its episodes are played from the start as streams, at two paces. Kept
/// in `scorecard.json` beside the row, so a file saved before it existed still reads.
public struct StreamNumbers: Codable, Sendable, Equatable {
  public var standard: BarTotals
  public var slow: BarTotals

  public init(standard: BarTotals = BarTotals(), slow: BarTotals = BarTotals()) {
    self.standard = standard
    self.slow = slow
  }
}

public enum StreamScore {
  /// The ads known at each wall second of a stream of `episode`. `local(reach)` gives what the
  /// finders find in the first `reach` seconds of the transcript. `model` is the model's answer
  /// for the whole transcript, or nil when the row has none for this episode.
  static func snapshots(
    events: [StreamEvent], plan: HeadPlan, model: [FoundAd]?, local: (Double) -> [FoundAd]
  ) -> [StreamSnapshot] {
    var known: [FoundAd] = []
    var out: [StreamSnapshot] = []
    for event in events {
      var more = local(event.reach)
      if event.modelAnswers, let model {
        more += counted(model, event: event, opensWithAd: plan.opensWithAd)
      }
      known = AdJoin.join(known + more)
      out.append(StreamSnapshot(at: event.at, ads: known))
    }
    return out
  }

  /// The model's ads that count at this moment: those that end within its reach and, at the
  /// first model steps of a show that does not usually open with an ad, only the sure ones.
  static func counted(_ model: [FoundAd], event: StreamEvent, opensWithAd: Bool) -> [FoundAd] {
    let sureOnly =
      event.headStep.map { $0 <= AdHeadRules.sureOnlyStep && !opensWithAd } ?? false
    return model.filter { $0.end <= event.reach + 1e-9 && (!sureOnly || $0.confidence == .sure) }
  }

  /// The jumps of one stream replay of one episode.
  static func jumps(
    episode: TeachingEpisode, habits: ShowHabits, settings: AdSkipSettings, pace: StreamPace,
    model: [FoundAd]?, local: (Double) -> [FoundAd]
  ) -> [StreamJump] {
    let plan = HeadPlan(habits: habits, show: episode.feed)
    let duration = episode.transcript.duration
    let events = StreamTimeline.events(
      duration: duration, plan: plan, pace: pace, withModel: model != nil)
    let moments = snapshots(events: events, plan: plan, model: model, local: local)
    let starts = StreamTimeline.playStart(
      habits: habits, show: episode.feed, firstLookDone: events.first?.at, pace: pace,
      settings: settings)
    return StreamReplay.play(
      snapshots: moments, startsAt: starts, duration: duration, settings: settings,
      seek: pace.seek)
  }

  /// The bar of one stream replay of one episode.
  static func bar(
    episode: TeachingEpisode, habits: ShowHabits, settings: AdSkipSettings, pace: StreamPace,
    model: [FoundAd]?, local: (Double) -> [FoundAd]
  ) -> BarTotals {
    let found = jumps(
      episode: episode, habits: habits, settings: settings, pace: pace, model: model, local: local)
    return AdBar.score(episode: episode, found: StreamReplay.asAds(found), settings: settings)
  }

  /// The stream numbers of the finders' row, and of the row that adds the model's answers when
  /// `models` (the answers by episode id) has any. Each reach's finders run once for an episode.
  /// `whole` is the row's ads for the whole transcript; `detect` runs its finders on a cut one.
  public static func run(
    episodes: [TeachingEpisode], habits: ShowHabits, settings: AdSkipSettings,
    models: [String: [FoundAd]]?, whole: (TeachingEpisode) -> [FoundAd],
    detect: (TeachingEpisode, Transcript) -> [FoundAd]
  ) -> (finders: StreamNumbers, withModel: StreamNumbers?) {
    var finders = StreamNumbers()
    var withModel = models == nil ? nil : StreamNumbers()
    for episode in episodes {
      var cache: [Double: [FoundAd]] = [:]
      let duration = episode.transcript.duration
      func local(_ reach: Double) -> [FoundAd] {
        if let kept = cache[reach] { return kept }
        let ads =
          reach >= duration - 0.01
          ? whole(episode)
          : detect(episode, AdScoreRun.head(of: episode.transcript, seconds: reach))
        cache[reach] = ads
        return ads
      }
      func both(_ model: [FoundAd]?) -> StreamNumbers {
        StreamNumbers(
          standard: bar(
            episode: episode, habits: habits, settings: settings, pace: .standard, model: model,
            local: local),
          slow: bar(
            episode: episode, habits: habits, settings: settings, pace: .slow, model: model,
            local: local))
      }
      let plain = both(nil)
      finders.standard += plain.standard
      finders.slow += plain.slow
      guard withModel != nil else { continue }
      let mine = models?[episode.id].map { both($0) } ?? plain
      withModel?.standard += mine.standard
      withModel?.slow += mine.slow
    }
    return (finders, withModel)
  }
}
