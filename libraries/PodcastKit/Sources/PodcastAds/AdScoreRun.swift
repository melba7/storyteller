// LOFI-FORK: runs an ad finder over the teaching folder's episodes and adds the scores up (see
// FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// The scores of a set of episodes added up.
///
/// In the words of the scorecard: the right seconds are `adSeconds - heardSeconds`, the wrong
/// seconds `cutSeconds` and the missed seconds `heardSeconds`. `heardBeforeSeconds` and
/// `heardAfterSeconds` are how much of the caught ads plays before the skip and after it
/// (`AdScore.heardAround`).
public struct ScoreTotals: Codable, Sendable, Equatable {
  public var episodes = 0
  public var shows = 0
  public var ads = 0
  public var caught = 0
  public var adSeconds = 0.0
  public var heardSeconds = 0.0
  public var heardBeforeSeconds = 0.0
  public var heardAfterSeconds = 0.0
  public var cutSeconds = 0.0
  /// Seconds of the episodes that are show: not a counted ad and not neutral.
  public var showSeconds = 0.0
  public var wrongSkips = 0
  public var bySort: [String: SortScore] = [:]
  public var openingAds = 0
  public var openingKnown = 0

  public init() {}

  /// The two "heard" numbers are new: a total saved without them reads with zero for both.
  public init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    episodes = try box.decode(Int.self, forKey: .episodes)
    shows = try box.decode(Int.self, forKey: .shows)
    ads = try box.decode(Int.self, forKey: .ads)
    caught = try box.decode(Int.self, forKey: .caught)
    adSeconds = try box.decode(Double.self, forKey: .adSeconds)
    heardSeconds = try box.decode(Double.self, forKey: .heardSeconds)
    heardBeforeSeconds = try box.decodeIfPresent(Double.self, forKey: .heardBeforeSeconds) ?? 0
    heardAfterSeconds = try box.decodeIfPresent(Double.self, forKey: .heardAfterSeconds) ?? 0
    cutSeconds = try box.decode(Double.self, forKey: .cutSeconds)
    showSeconds = try box.decode(Double.self, forKey: .showSeconds)
    wrongSkips = try box.decode(Int.self, forKey: .wrongSkips)
    bySort = try box.decode([String: SortScore].self, forKey: .bySort)
    openingAds = try box.decode(Int.self, forKey: .openingAds)
    openingKnown = try box.decode(Int.self, forKey: .openingKnown)
  }
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
  /// The owner's bar for these episodes (`AdBar`); nil when it was not worked out.
  public var bar: BarTotals?
}

/// One row of the scorecard as `scorecard.json` keeps it: a name, the row's totals and the same
/// totals for each show (`shows[].total`, which add up to `total`). Every row has its own, so the
/// Mac can tell which finder is right or wrong on which show.
public struct ScorecardRow: Codable, Sendable, Equatable {
  public var name: String
  public var total: ScoreTotals
  public var shows: [ShowScore]
  /// The owner's bar for the same found ads. Nil in a file saved before the bar existed.
  public var bar: BarTotals?
  /// The same row played as a stream (`podcast-teach score --stream`). Nil without it.
  public var stream: StreamNumbers?

  public init(name: String, total: ScoreTotals, shows: [ShowScore], bar: BarTotals? = nil) {
    self.name = name
    self.total = total
    self.shows = shows
    self.bar = bar
  }

  public init(name: String, card: Scorecard) {
    self.init(name: name, total: card.total, shows: card.shows, bar: card.bar)
  }
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
    runRows(episodes: episodes, habits: habits, settings: settings, rows: 1) { episode, transcript in
      [detect(episode, transcript)]
    }[0]
  }

  /// The same for several rows at once: `detect` returns the ads of each of the `rows` rows
  /// (fewer lists than rows means no ads for the last ones), and one scorecard comes back for
  /// each row. The episodes, the shows and the first look are worked out once for all rows.
  static func runRows(
    episodes: [TeachingEpisode], habits: ShowHabits, settings: AdSkipSettings, rows: Int,
    detect: (TeachingEpisode, Transcript) -> [[FoundAd]]
  ) -> [Scorecard] {
    let each = Array(0..<max(0, rows))
    func ads(_ lists: [[FoundAd]], _ row: Int) -> [FoundAd] {
      lists.indices.contains(row) ? lists[row] : []
    }
    var scores = [[EpisodeScore]](repeating: [], count: each.count)
    var seconds: [String: Double] = [:]  // the show seconds of each episode, by id
    var bars = [BarTotals](repeating: BarTotals(), count: each.count)
    for episode in episodes {
      let whole = detect(episode, episode.transcript)
      var made = each.map {
        AdScore.score(episode: episode, found: ads(whole, $0), settings: settings)
      }
      for row in each {
        bars[row] += AdBar.score(episode: episode, found: ads(whole, row), settings: settings)
      }
      let openings = AdScore.openings(episode, settings)
      if !openings.isEmpty {
        let look = firstLook(habits, show: episode.feed)
        let head = head(of: episode.transcript, seconds: look)
        let found = detect(episode, head)
        for row in each {
          let spans = AdScore.skipped(ads(found, row), settings)
          made[row].openingKnown = openings.filter { opening in
            spans.contains { $0.start < opening.end && opening.start < $0.end }
          }.count
        }
      }
      for row in each { scores[row].append(made[row]) }
      seconds[episode.id] = AdScore.showSeconds(episode, settings)
    }
    return each.map { row in
      var made = card(scores[row], seconds: seconds)
      made.bar = bars[row]
      return made
    }
  }

  /// The scorecard of one row: the totals and the totals of each show, worst first.
  private static func card(_ scores: [EpisodeScore], seconds: [String: Double]) -> Scorecard {
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
      total.heardBeforeSeconds += score.heardBeforeSeconds
      total.heardAfterSeconds += score.heardAfterSeconds
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
