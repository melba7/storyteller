// LOFI-FORK: the arithmetic of the scorecard: how well found ads match the marked ones (see
// FORK.md). All in seconds. Foundation only.
import Foundation

/// How one sort of marked stretch fared.
public struct SortScore: Codable, Sendable, Equatable {
  public var ads: Int
  public var caught: Int
  public var seconds: Double
  public var heardSeconds: Double

  public init(ads: Int = 0, caught: Int = 0, seconds: Double = 0, heardSeconds: Double = 0) {
    self.ads = ads
    self.caught = caught
    self.seconds = seconds
    self.heardSeconds = heardSeconds
  }
}

/// How one episode fared.
public struct EpisodeScore: Codable, Sendable, Equatable {
  public var id: String
  public var feed: String
  public var show: String
  public var duration: Double
  /// The marked stretches the settings skip, and how many of them are caught.
  public var ads: Int
  public var caught: Int
  public var adSeconds: Double
  /// The seconds of those marked stretches that no skip covers (the missed ones included).
  public var heardSeconds: Double
  /// Of the caught ads, the seconds that play before the skip starts and after it ends. Defined
  /// at `AdScore.heardAround`.
  public var heardBeforeSeconds: Double
  public var heardAfterSeconds: Double
  public var cutSeconds: Double
  public var wrongSkips: Int
  /// All four sorts, whatever the settings.
  public var bySort: [String: SortScore]
  public var openingAds: Int
  /// Filled by `AdScoreRun`, not by `AdScore.score`.
  public var openingKnown: Int
}

/// Sorted, separate stretches of time.
struct Spans {
  var items: [(start: Double, end: Double)]

  /// The stretches cut to `0...limit`, empty ones dropped, overlapping ones joined.
  init(_ raw: [(start: Double, end: Double)], limit: Double) {
    let cut = raw.map { (start: max($0.start, 0), end: min($0.end, limit)) }.filter { $0.end > $0.start }
    var joined: [(start: Double, end: Double)] = []
    for item in cut.sorted(by: { $0.start < $1.start }) {
      if let last = joined.last, item.start <= last.end {
        joined[joined.count - 1].end = max(last.end, item.end)
      } else {
        joined.append(item)
      }
    }
    items = joined
  }

  var length: Double { items.reduce(0) { $0 + ($1.end - $1.start) } }

  /// How many seconds this and the other have in common.
  func overlap(_ other: Spans) -> Double { Spans.overlap(items, other.items) }

  static func overlap(_ a: [(start: Double, end: Double)], _ b: [(start: Double, end: Double)]) -> Double {
    var total = 0.0
    for x in a {
      for y in b { total += max(0, min(x.end, y.end) - max(x.start, y.start)) }
    }
    return total
  }
}

public enum AdScore {
  /// A marked stretch is caught when at least this share of it is skipped.
  public static let caughtShare = 0.5
  /// An opening ad is one that starts within this many seconds.
  static let openingSeconds = 30.0
  /// The four sorts of the Mac's labels.
  static let sorts = ["sponsor", "network_promo", "host_ask", "intro_credits"]

  /// The ads the player skips: sure or unsure, of a kind the settings allow.
  static func skipped(_ found: [FoundAd], _ settings: AdSkipSettings) -> [FoundAd] {
    found.filter { $0.confidence >= .unsure && settings.allows($0.kind) && $0.end > $0.start }
  }

  /// The marked stretches the settings skip.
  static func counted(_ episode: TeachingEpisode, _ settings: AdSkipSettings) -> [TeachingTruth] {
    episode.truth.filter { AdKind(sort: $0.sort).map(settings.allows) ?? false }
  }

  /// The stretches that count neither as ad nor as show: only the ones marked with low
  /// confidence. A stretch of a sort the settings do not skip is show to the listener, so a skip
  /// over it is a mistake.
  static func neutral(_ episode: TeachingEpisode, _ settings: AdSkipSettings) -> [TeachingTruth] {
    episode.maybe
  }

  private static func pairs(_ truth: [TeachingTruth]) -> [(start: Double, end: Double)] {
    truth.map { (start: $0.start, end: $0.end) }
  }

  /// Seconds of the episode that are show: not a counted ad and not neutral.
  static func showSeconds(_ episode: TeachingEpisode, _ settings: AdSkipSettings) -> Double {
    let duration = episode.transcript.duration
    let marked = Spans(
      pairs(counted(episode, settings)) + pairs(neutral(episode, settings)), limit: duration)
    return max(0, duration - marked.length)
  }

  /// The counted stretches that start in the first 30 seconds.
  static func openings(_ episode: TeachingEpisode, _ settings: AdSkipSettings) -> [TeachingTruth] {
    counted(episode, settings).filter { $0.start <= openingSeconds && $0.end > $0.start }
  }

  public static func score(
    episode: TeachingEpisode, found: [FoundAd], settings: AdSkipSettings = AdSkipSettings()
  ) -> EpisodeScore {
    let duration = episode.transcript.duration
    let skippedAds = skipped(found, settings)
    let skippedSpans = Spans(skippedAds.map { (start: $0.start, end: $0.end) }, limit: duration)
    let truth = counted(episode, settings)
    let truthSpans = Spans(pairs(truth), limit: duration)
    let marked = Spans(pairs(truth) + pairs(neutral(episode, settings)), limit: duration)

    let whole = caughtCount(truth, by: skippedSpans, limit: duration)
    let adSeconds = truthSpans.length
    let heard = adSeconds - truthSpans.overlap(skippedSpans)
    let around = heardAround(truthSpans, by: skippedSpans)
    let cut = skippedSpans.length - skippedSpans.overlap(marked)
    let wrong = skippedAds.filter { ad in
      let own = Spans([(start: ad.start, end: ad.end)], limit: duration)
      return own.length > 0 && own.overlap(marked) < 0.5 * own.length
    }.count

    // Per sort: any found ad that is sure or unsure counts, whatever its kind or the settings.
    let anyFound = Spans(
      found.filter { $0.confidence >= .unsure }.map { (start: $0.start, end: $0.end) }, limit: duration)
    var bySort: [String: SortScore] = [:]
    for sort in sorts {
      let own = episode.truth.filter { $0.sort == sort }
      let spans = Spans(pairs(own), limit: duration)
      bySort[sort] = SortScore(
        ads: own.count, caught: caughtCount(own, by: anyFound, limit: duration),
        seconds: spans.length, heardSeconds: spans.length - spans.overlap(anyFound))
    }

    return EpisodeScore(
      id: episode.id, feed: episode.feed, show: episode.show, duration: duration, ads: truth.count,
      caught: whole, adSeconds: adSeconds, heardSeconds: heard, heardBeforeSeconds: around.before,
      heardAfterSeconds: around.after, cutSeconds: cut, wrongSkips: wrong, bySort: bySort,
      openingAds: openings(episode, settings).count, openingKnown: 0)
  }

  /// The seconds of a caught ad that play before the skip and after it, which is how late a skip
  /// starts and how early it ends. The ads are the counted marked stretches (the ones the
  /// settings skip, cut to the episode), with the ones that overlap or touch joined into one, as
  /// `heardSeconds` has them, so these two numbers never add up to more than `heardSeconds`. An
  /// ad counts only when it is caught: at least `caughtShare` of it is skipped (the rule of
  /// `caught`). For each such ad:
  ///
  ///     early = max(0, skipStart - adStart)
  ///     late  = max(0, adEnd - skipEnd)
  ///
  /// Skips are the player's (`skipped`), overlapping ones joined. A skip reaches an ad when it
  /// overlaps it by more than zero seconds (one that only touches an edge does not). When several
  /// separate skips reach one ad, `skipStart` is the start of the first and `skipEnd` the end of
  /// the last; what plays between two skips inside an ad is in neither number (it is in
  /// `heardSeconds`). One skip over two ads is counted for each ad on its own. An ad that is not
  /// caught, a missed one or one that a skip only clips, is in `heardSeconds` and not counted
  /// here, so these numbers say how late or early the skips are on the ads they catch, not how
  /// many ads were missed.
  static func heardAround(_ ads: Spans, by skips: Spans) -> (before: Double, after: Double) {
    var before = 0.0
    var after = 0.0
    for ad in ads.items {
      let length = ad.end - ad.start
      guard Spans.overlap([ad], skips.items) >= caughtShare * length - 1e-9 else { continue }
      // `skips.items` are sorted and apart, so the first and the last one reaching the ad hold
      // its earliest start and its latest end.
      let reaching = skips.items.filter { min($0.end, ad.end) - max($0.start, ad.start) > 0 }
      guard let first = reaching.first, let last = reaching.last else { continue }
      before += max(0, first.start - ad.start)
      after += max(0, ad.end - last.end)
    }
    return (before, after)
  }

  /// How many of the stretches have at least `caughtShare` of their length inside `spans`.
  private static func caughtCount(
    _ stretches: [TeachingTruth], by spans: Spans, limit: Double
  ) -> Int {
    stretches.filter { stretch in
      let own = Spans([(start: stretch.start, end: stretch.end)], limit: limit)
      return own.length > 0 && own.overlap(spans) >= caughtShare * own.length - 1e-9
    }.count
  }
}
