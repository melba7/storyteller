// LOFI-FORK: scores the stream replay over the teaching episodes (see FORK.md, StreamReplay.swift
// and AdBar.swift). Foundation only.
import Foundation
import PodcastTranscripts

/// The bar of a row when its episodes are played from the start as streams, at two paces, with
/// everything known at the start, and at other speech speeds. Kept
/// in `scorecard.json` beside the row, so a file saved before it existed still reads.
public struct StreamNumbers: Codable, Sendable, Equatable {
  /// The bar at one speech speed, standard otherwise.
  public struct Speed: Codable, Sendable, Equatable {
    public var speech: Double
    public var bar: BarTotals
  }

  public var standard: BarTotals
  public var slow: BarTotals
  /// The same player with the finished file known before play (nil in a file saved before it
  /// existed).
  public var ready: BarTotals?
  /// How the standard pace does at other speech speeds (nil in an older file).
  public var speeds: [Speed]?
  /// The speech speed that the `standard` numbers were replayed at when `--speech` gave one (the
  /// pace the phone measured). Nil when they are at the assumed standard pace.
  public var speech: Double?

  public init(
    standard: BarTotals = BarTotals(), slow: BarTotals = BarTotals(), ready: BarTotals? = nil,
    speeds: [Speed]? = nil, speech: Double? = nil
  ) {
    self.standard = standard
    self.slow = slow
    self.ready = ready
    self.speeds = speeds
    self.speech = speech
  }
}

extension StreamNumbers {
  /// Adds the numbers of one more episode.
  mutating func add(_ other: StreamNumbers) {
    standard += other.standard
    slow += other.slow
    if let more = other.ready {
      var total = ready ?? BarTotals()
      total += more
      ready = total
    }
    var sum = speeds ?? []
    for (index, more) in (other.speeds ?? []).enumerated() {
      if sum.indices.contains(index) {
        sum[index].bar += more.bar
      } else {
        sum.append(more)
      }
    }
    speeds = sum.isEmpty ? nil : sum
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

  /// The speech speeds the sensitivity lines try, in times real time.
  static let sensitivitySpeeds = [6.0, 25.0]

  /// The moments of one episode. The model's wait is part of the head scan unless the pace says
  /// not, and always when the row has the model's answers.
  static func timeline(
    duration: Double, plan: HeadPlan, pace: StreamPace, model: [FoundAd]?
  ) -> [StreamEvent] {
    StreamTimeline.events(
      duration: duration, plan: plan, pace: pace, withModel: pace.waitsForModel || model != nil)
  }

  /// The jumps of one stream replay of one episode.
  static func jumps(
    episode: TeachingEpisode, habits: ShowHabits, settings: AdSkipSettings, pace: StreamPace,
    model: [FoundAd]?, local: (Double) -> [FoundAd]
  ) -> [StreamJump] {
    let plan = HeadPlan(habits: habits, show: episode.feed)
    let duration = episode.transcript.duration
    if pace.isInstant {
      // A ready episode holds the finished file: the finders on the whole transcript and the
      // model's answers. What a head step saw on a cut transcript is not in it.
      let known = StreamSnapshot(at: 0, ads: AdJoin.join(local(duration) + (model ?? [])))
      return StreamReplay.play(
        snapshots: [known], startsAt: 0, duration: duration, settings: settings, seek: pace.seek)
    }
    let events = timeline(duration: duration, plan: plan, pace: pace, model: model)
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
  /// `speech` is the speech speed the phone measured: the `standard` numbers are then replayed at
  /// it (`StreamPace.measured`) and not at the assumed one.
  public static func run(
    episodes: [TeachingEpisode], habits: ShowHabits, settings: AdSkipSettings,
    models: [String: [FoundAd]]?, speech: Double? = nil, whole: (TeachingEpisode) -> [FoundAd],
    detect: (TeachingEpisode, Transcript) -> [FoundAd]
  ) -> (finders: StreamNumbers, withModel: StreamNumbers?) {
    let standard = speech.map { StreamPace.measured(speech: $0) } ?? .standard
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
      func at(_ pace: StreamPace, _ model: [FoundAd]?) -> BarTotals {
        bar(
          episode: episode, habits: habits, settings: settings, pace: pace, model: model,
          local: local)
      }
      func both(_ model: [FoundAd]?) -> StreamNumbers {
        StreamNumbers(
          standard: at(standard, model), slow: at(.slow, model), ready: at(.instant, model),
          speeds: sensitivitySpeeds.map {
            .init(speech: $0, bar: at(StreamPace.standard.withSpeech($0), model))
          })
      }
      let plain = both(nil)
      finders.add(plain)
      guard withModel != nil else { continue }
      withModel?.add(models?[episode.id].map { both($0) } ?? plain)
    }
    finders.speech = speech
    withModel?.speech = speech
    return (finders, withModel)
  }
}
