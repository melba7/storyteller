// LOFI-FORK: runs an ad finder over the teaching folder's episodes and adds the scores up (see
// FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// The scores of a set of episodes added up.
public struct ScoreTotals: Codable, Sendable, Equatable {
  public var episodes = 0
  public var shows = 0
  public var ads = 0
  public var caught = 0
  public var adSeconds = 0.0
  public var heardSeconds = 0.0
  public var cutSeconds = 0.0
  /// Seconds of the episodes that are show: not a counted ad and not neutral.
  public var showSeconds = 0.0
  public var wrongSkips = 0
  public var bySort: [String: SortScore] = [:]
  public var openingAds = 0
  public var openingKnown = 0

  public init() {}
}

/// One show's totals.
public struct ShowScore: Codable, Sendable, Equatable {
  public var feed: String
  public var show: String
  public var total: ScoreTotals
}

public struct Scorecard: Codable, Sendable, Equatable {
  public var episodes: [EpisodeScore]
  public var total: ScoreTotals
  /// One per feed, the worst (most ad seconds heard) first.
  public var shows: [ShowScore]
}

public enum AdScoreRun {
  /// How far into the episode the first look goes when the show's habits say nothing.
  static let defaultLook = 15.0

  /// `detect` gets an episode and a transcript (the episode's own, or its first seconds only)
  /// and returns the ads found in it.
  public static func run(
    episodes: [TeachingEpisode], habits: ShowHabits, settings: AdSkipSettings = AdSkipSettings(),
    detect: (TeachingEpisode, Transcript) -> [FoundAd]
  ) -> Scorecard {
    var scores: [EpisodeScore] = []
    var seconds: [String: Double] = [:]  // the show seconds of each episode, by id
    for episode in episodes {
      var score = AdScore.score(
        episode: episode, found: detect(episode, episode.transcript), settings: settings)
      let openings = AdScore.openings(episode, settings)
      if !openings.isEmpty {
        let look = firstLook(habits, show: episode.feed)
        let head = head(of: episode.transcript, seconds: look)
        let spans = AdScore.skipped(detect(episode, head), settings)
        score.openingKnown = openings.filter { opening in
          spans.contains { $0.start < opening.end && opening.start < $0.end }
        }.count
      }
      scores.append(score)
      seconds[episode.id] = AdScore.showSeconds(episode, settings)
    }

    var byFeed: [String: [(EpisodeScore, Double)]] = [:]
    var feeds: [String] = []
    for score in scores {
      if byFeed[score.feed] == nil { feeds.append(score.feed) }
      byFeed[score.feed, default: []].append((score, seconds[score.id] ?? 0))
    }
    let shows = feeds.map { feed -> ShowScore in
      let own = byFeed[feed] ?? []
      return ShowScore(feed: feed, show: own.first?.0.show ?? "", total: totals(own))
    }.sorted {
      $0.total.heardSeconds != $1.total.heardSeconds
        ? $0.total.heardSeconds > $1.total.heardSeconds : $0.feed < $1.feed
    }
    return Scorecard(
      episodes: scores, total: totals(scores.map { ($0, seconds[$0.id] ?? 0) }), shows: shows)
  }

  /// The first `seconds` of a transcript: the lines that end by then and the words that end by
  /// then, with its duration set to `seconds`.
  public static func head(of transcript: Transcript, seconds: Double) -> Transcript {
    var cut = transcript
    cut.lines = transcript.lines.filter { $0.end <= seconds }
    cut.words = transcript.words.filter { $0.end <= seconds }
    cut.duration = seconds
    return cut
  }

  private static func totals(_ items: [(EpisodeScore, Double)]) -> ScoreTotals {
    var total = ScoreTotals()
    total.episodes = items.count
    total.shows = Set(items.map { $0.0.feed }).count
    for sort in AdScore.sorts { total.bySort[sort] = SortScore() }
    for (score, showSeconds) in items {
      total.ads += score.ads
      total.caught += score.caught
      total.adSeconds += score.adSeconds
      total.heardSeconds += score.heardSeconds
      total.cutSeconds += score.cutSeconds
      total.showSeconds += showSeconds
      total.wrongSkips += score.wrongSkips
      total.openingAds += score.openingAds
      total.openingKnown += score.openingKnown
      for (sort, own) in score.bySort {
        var sum = total.bySort[sort] ?? SortScore()
        sum.ads += own.ads
        sum.caught += own.caught
        sum.seconds += own.seconds
        sum.heardSeconds += own.heardSeconds
        total.bySort[sort] = sum
      }
    }
    return total
  }

  /// How far into the episode the phone's first look goes: the first step of its head scan for
  /// this show (`AdHeadRules.steps(firstLook:)`), so the scorecard looks where the phone looks.
  static func firstLook(_ habits: ShowHabits, show: String) -> Double {
    AdHeadRules.steps(firstLook: habits.firstLook(show: show)).first ?? defaultLook
  }
}
