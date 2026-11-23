// LOFI-FORK: the owner's strict bar for the scorecard: how many ad breaks the phone skips by
// itself, cleanly enough that nobody has to tap (see FORK.md). In seconds. Foundation only.
import Foundation

/// Why a break fails the bar. Only the first cause that applies is counted, in this order:
/// missed, starts late (more than 5 s heard before the first skip), stops early (more than 5 s
/// heard after the last), gap inside (too much heard in total, with part of it heard between the
/// skips; with none, the bigger edge is named instead), starts early, lands too far.
public enum BarCause: String, Codable, Sendable, CaseIterable {
  /// No skip reaches the break.
  case missed
  /// The first skip that reaches it starts more than `AdBar.heardSeconds` after it begins.
  case startsLate
  /// The last skip that reaches it ends more than `AdBar.heardSeconds` before it ends.
  case stopsEarly
  /// Too much of the break is heard between its first and last skip: a gap inside. When nothing
  /// is heard between them, too much heard in total is blamed on the bigger edge, as `startsLate`
  /// or `stopsEarly`.
  case gapInside
  /// The skips cut more than `AdBar.cutSeconds` of show before the break.
  case startsEarly
  /// The skips cut more than `AdBar.cutSeconds` of show after the break.
  case landsTooFar

  /// The cause in plain words, for the report.
  public var label: String {
    switch self {
    case .missed: return "missed"
    case .startsLate: return "starts late"
    case .stopsEarly: return "stops early"
    case .gapInside: return "gap inside"
    case .startsEarly: return "starts early"
    case .landsTooFar: return "lands too far"
    }
  }
}

/// The bar of one episode or of many episodes added up.
public struct BarTotals: Codable, Sendable, Equatable {
  /// The breaks of 10 seconds or longer.
  public var breaks = 0
  public var passed = 0
  /// How many breaks failed for each cause, by `BarCause.rawValue`. A cause that never happened
  /// may be missing.
  public var causes: [String: Int] = [:]
  /// The breaks that start in the first `AdBar.earlySeconds`, and how many of them passed.
  public var earlyBreaks = 0
  public var earlyPassed = 0
  /// The skips that overlap no marked ad and cut more than `AdBar.noAdSeconds` of show.
  public var noAdSkips = 0
  /// The seconds of show those skips cut.
  public var noAdSeconds = 0.0
  /// The seconds of the episodes, so a total can say skips per hour.
  public var episodeSeconds = 0.0

  public init() {}

  public func count(_ cause: BarCause) -> Int { causes[cause.rawValue] ?? 0 }

  /// Skips with no ad for each hour of episode, 0 when there is no episode time.
  public var noAdPerHour: Double { episodeSeconds > 0 ? Double(noAdSkips) / (episodeSeconds / 3600) : 0 }

  /// The share of breaks that pass, 0 to 1; 0 when there are none.
  public var rate: Double { breaks == 0 ? 0 : Double(passed) / Double(breaks) }

  public static func += (total: inout BarTotals, other: BarTotals) {
    total.breaks += other.breaks
    total.passed += other.passed
    for (cause, number) in other.causes { total.causes[cause, default: 0] += number }
    total.earlyBreaks += other.earlyBreaks
    total.earlyPassed += other.earlyPassed
    total.noAdSkips += other.noAdSkips
    total.noAdSeconds += other.noAdSeconds
    total.episodeSeconds += other.episodeSeconds
  }
}

public enum AdBar {
  /// A break passes when at most this many seconds of it are heard.
  public static let heardSeconds = 5.0
  /// A break passes when the skips cut at most this many seconds of show before it, and at most
  /// this many after it.
  public static let cutSeconds = 5.0
  /// Counted marked stretches that touch or lie within this many seconds of each other are one
  /// break.
  public static let joinSeconds = 1.0
  /// Only breaks of at least this many seconds are scored.
  public static let shortestBreak = 10.0
  /// A skip that overlaps no marked ad is a skip with no ad when it cuts more than this many
  /// seconds of show.
  public static let noAdSeconds = 0.5
  /// A break is an early one when it starts before this many seconds.
  public static let earlySeconds = 180.0
  /// Slack for rounding.
  static let slack = 1e-9

  private typealias Span = (start: Double, end: Double)

  /// The bar for one episode and the ads found in it, with the settings' counted stretches,
  /// the settings' skipped ads and the neutral stretches as the scorecard has them.
  public static func score(
    episode: TeachingEpisode, found: [FoundAd], settings: AdSkipSettings = AdSkipSettings()
  ) -> BarTotals {
    let counted = AdScore.counted(episode, settings).map { (start: $0.start, end: $0.end) }
    let neutral = AdScore.neutral(episode, settings).map { (start: $0.start, end: $0.end) }
    let skips = AdScore.skipped(found, settings).map { (start: $0.start, end: $0.end) }
    return score(
      counted: counted, neutral: neutral, skips: skips, duration: episode.transcript.duration)
  }

  static func score(
    counted: [(start: Double, end: Double)], neutral: [(start: Double, end: Double)],
    skips rawSkips: [(start: Double, end: Double)], duration: Double
  ) -> BarTotals {
    var total = BarTotals()
    total.episodeSeconds = duration
    // Everything is cut to the episode first, the way the existing scorer does it.
    func clipped(_ raw: [Span]) -> [Span] {
      Spans(raw, limit: duration).items
    }
    let counted = clipped(counted)
    let neutral = clipped(neutral)
    let skips = join(clipped(rawSkips), within: 0)
    let breaks = join(counted, within: joinSeconds)
    let marked = join(counted + neutral, within: 0)
    for span in breaks where span.end - span.start >= shortestBreak - slack {
      let reaching = skips.filter { overlap($0, span) > 0 }
      let heard = (span.end - span.start) - reaching.reduce(0) { $0 + overlap($1, span) }
      var late = 0.0
      var stopsEarly = 0.0
      var before = 0.0
      var after = 0.0
      if let first = reaching.first, let last = reaching.last {
        late = max(0, first.start - span.start)
        stopsEarly = max(0, span.end - last.end)
        for skip in reaching {
          for part in outside(skip, of: marked) {
            if part.end <= span.start + slack {
              before += part.end - part.start
            } else if part.start >= span.end - slack {
              after += part.end - part.start
            }
          }
        }
      }
      var cause: BarCause?
      if reaching.isEmpty {
        cause = .missed
      } else if late > heardSeconds + slack {
        cause = .startsLate
      } else if stopsEarly > heardSeconds + slack {
        cause = .stopsEarly
      } else if heard > heardSeconds + slack {
        // Part of the break heard between the first and the last skip is a gap; otherwise the
        // bigger of the two heard edges is the cause.
        let between = heard - late - stopsEarly
        cause = between > slack ? .gapInside : (late >= stopsEarly ? .startsLate : .stopsEarly)
      } else if before > cutSeconds + slack {
        cause = .startsEarly
      } else if after > cutSeconds + slack {
        cause = .landsTooFar
      }
      let early = span.start < earlySeconds
      total.breaks += 1
      if early { total.earlyBreaks += 1 }
      if let cause {
        total.causes[cause.rawValue, default: 0] += 1
      } else {
        total.passed += 1
        if early { total.earlyPassed += 1 }
      }
    }
    for skip in skips where !counted.contains(where: { overlap($0, skip) > 0 }) {
      let cut = outside(skip, of: marked).reduce(0) { $0 + ($1.end - $1.start) }
      if cut > noAdSeconds {
        total.noAdSkips += 1
        total.noAdSeconds += cut
      }
    }
    return total
  }

  private static func overlap(_ a: Span, _ b: Span) -> Double {
    max(0, min(a.end, b.end) - max(a.start, b.start))
  }

  /// Sorted stretches, those that overlap or lie within `gap` seconds of each other joined.
  private static func join(_ raw: [Span], within gap: Double) -> [Span] {
    var joined: [Span] = []
    for item in raw.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
      if let last = joined.last, item.start <= last.end + gap {
        joined[joined.count - 1].end = max(last.end, item.end)
      } else {
        joined.append(item)
      }
    }
    return joined
  }

  /// The parts of `span` that no stretch of `others` (sorted, apart) covers.
  private static func outside(_ span: Span, of others: [Span]) -> [Span] {
    var parts: [Span] = []
    var start = span.start
    for other in others where other.end > start && other.start < span.end {
      if other.start > start { parts.append((start: start, end: other.start)) }
      start = max(start, other.end)
    }
    if start < span.end { parts.append((start: start, end: span.end)) }
    return parts
  }
}
