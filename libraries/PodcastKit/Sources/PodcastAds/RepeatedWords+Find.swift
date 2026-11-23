// LOFI-FORK: finds the stretches of a new episode that an older episode of the same show already
// said (see RepeatedWords.swift for what it keeps and how the phone must use it). Foundation only.
import Foundation
import PodcastTranscripts

extension RepeatedWords {
  /// Nothing is looked for in the first minute: `ShowOpenings` learns the show's opening there
  /// (only 8 to 40 words in the first five minutes), so a repeat that follows a pre-roll or a
  /// cold open can still be the show's own intro or credits, which is why this finder only asks.
  public static let firstMinute = 60.0
  /// A stretch is at least this long in seconds and in words, and at most `longest` seconds.
  public static let shortest = KnownAds.shortest
  public static let fewestWords = KnownAds.fewestWords
  public static let longest = AdRules.maxLength

  // How a stretch is found. A run of the new episode is a HIT when an older episode has the same
  // run. A hit is SOLID when at least `neighbours` other hits lie within `reach` runs of it, which
  // keeps a lone run of a common phrase from starting a stretch. Solid hits that are at most
  // `maxGap` runs apart (a changed word leaves five runs without a hit, three in a row leave
  // seven) are one stretch, which needs `fewestHits` solid hits.
  static let reach = 4
  static let neighbours = 3
  static let maxGap = 7
  static let fewestHits = 10
  /// Stretches less than this many seconds apart are one replay, which is dropped when it is
  /// longer than `longest` in all (a replay that the recogniser heard differently in places
  /// comes in pieces).
  static let joinGap = 10.0
  /// A piece stays this many seconds away from an ad that is already named.
  static let apart = 1.0
  /// Where at least this many runs kept for a stretch denied earlier are found, a stretch of
  /// the new episode is cut there: the runs found, and the ones between them that are at most
  /// `maxGap` apart, are the denied part.
  static let fewestRunsToCut = 3

  typealias Span = (start: Double, end: Double)

  /// The stretches of this episode that an older episode of `show` also said, as unsure ads from
  /// the finder "repeat-words", by start. Nothing is found when the show has no older episode (an
  /// episode is never compared with itself), in the first minute, or in an episode that mostly
  /// repeats (`AdRules.shareLimit` of it, counting a replay however long and not counting the
  /// time that `already` names). A replay of more than 300 seconds is not offered. Nothing
  /// returned overlaps an ad in `already`, and the words of a stretch the listener denied are cut
  /// out. `duration` is the episode's length in seconds; 0 or anything that is not a length
  /// means it is not known.
  public func find(
    show: String, episode: String, lines: [TranscriptLine], duration: Double, now: Date,
    already: [FoundAd] = []
  ) -> [FoundAd] {
    let showId = FinderGuard.name(show)
    let episodeId = FinderGuard.name(episode)
    guard let entry = shows.first(where: { $0.id == showId }) else { return [] }
    let older = entry.episodes.filter { $0.id != episodeId }
    guard !older.isEmpty else { return [] }
    let spoken = SpokenRuns(lines: lines)
    guard spoken.hashes.count >= Self.fewestRuns else { return [] }
    var known = Set<UInt32>()
    for other in older { known.formUnion(SpokenRuns.unpack(other.hashes)) }
    let replayed = Self.stretches(in: spoken, known: known)
    guard !replayed.isEmpty else { return [] }

    let usable = duration.isFinite && duration > 0
    let length = usable ? duration : (spoken.ends.last ?? 0)
    let named = Self.merged(already)
    let repeated = replayed.reduce(0.0) {
      $0 + Self.uncovered($1, in: spoken, by: named)
    }
    if length >= AdRules.shareFrom, repeated >= AdRules.shareLimit * length { return [] }

    var denied = Set<UInt32>()
    for stretch in entry.denied where !Self.isOld(stretch, now: now) {
      denied.formUnion(SpokenRuns.unpack(stretch.hashes))
    }
    var found: [FoundAd] = []
    let limit: Double? = usable ? duration : nil
    for stretch in Self.withoutLongReplays(replayed, in: spoken) {
      let cut = Self.joined(named + Self.deniedTimes(in: stretch, of: spoken, by: denied))
      for piece in Self.pieces(of: stretch, in: spoken, around: cut, before: limit) {
        found.append(
          FoundAd(
            start: piece.start, end: piece.end, kind: .ad, advertiser: "", confidence: .unsure,
            firstWords: spoken.texts[piece.words].prefix(AdRules.firstWords).joined(separator: " "),
            source: Self.source))
      }
    }
    return found.sorted { $0.start < $1.start }
  }

  // MARK: Stretches

  /// The words (by index) of each stretch of the episode that is in `known`: a run of solid hits
  /// with at least `fewestHits` of them, in order. Runs that start in the first minute are not
  /// looked at. No length limit is applied here: a long stretch counts as repeated.
  static func stretches(in spoken: SpokenRuns, known: Set<UInt32>) -> [Range<Int>] {
    var hits: [Int] = []
    for run in spoken.hashes.indices
    where spoken.starts[run] >= firstMinute && known.contains(spoken.hashes[run]) {
      hits.append(run)
    }
    guard hits.count >= fewestHits else { return [] }
    let solid = solidHits(hits)
    guard var from = solid.first else { return [] }
    var to = from
    var count = 1
    var result: [Range<Int>] = []

    for hit in solid.dropFirst() {
      if hit - to - 1 <= maxGap {
        to = hit
        count += 1
      } else {
        if count >= fewestHits { result.append(from..<(to + SpokenRuns.runLength)) }
        from = hit
        to = hit
        count = 1
      }
    }
    if count >= fewestHits { result.append(from..<(to + SpokenRuns.runLength)) }
    return result
  }

  /// The stretches that are not part of a replay of more than 300 seconds. A replay is the
  /// stretches that are less than `joinGap` seconds apart, one after the other. (Whether what is
  /// left is long enough, 15 seconds and 25 words, is decided when it is cut: see `pieces`.)
  static func withoutLongReplays(_ stretches: [Range<Int>], in spoken: SpokenRuns) -> [Range<Int>] {
    func start(_ stretch: Range<Int>) -> Double { spoken.starts[stretch.lowerBound] }
    func end(_ stretch: Range<Int>) -> Double { spoken.ends[stretch.upperBound - 1] }
    var result: [Range<Int>] = []
    var replay: [Range<Int>] = []

    func close() {
      if let first = replay.first, let last = replay.last, end(last) - start(first) <= longest {
        result += replay
      }
      replay = []
    }

    for stretch in stretches {
      if let last = replay.last, start(stretch) - end(last) >= joinGap { close() }
      replay.append(stretch)
    }
    close()
    return result
  }

  /// The hits that have at least `neighbours` other hits within `reach` runs. `hits` is in order.
  static func solidHits(_ hits: [Int]) -> [Int] {
    var result: [Int] = []
    var low = 0
    var high = 0
    for (at, hit) in hits.enumerated() {
      while hits[low] < hit - reach { low += 1 }
      high = max(high, at)
      while high + 1 < hits.count, hits[high + 1] <= hit + reach { high += 1 }
      if high - low >= neighbours { result.append(hit) }
    }
    return result
  }

  // MARK: Ads that are named already

  /// The stretches of time the ads cover, each `apart` wider on both sides, in order and with no
  /// two overlapping. An ad whose times are not numbers, or that ends before it starts, is ignored.
  static func merged(_ ads: [FoundAd]) -> [Span] {
    joined(
      ads.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
        .map { (start: $0.start - apart, end: $0.end + apart) })
  }

  /// The spans in order of their start, the ones that overlap made one.
  static func joined(_ spans: [Span]) -> [Span] {
    var result: [Span] = []
    for span in spans.sorted(by: { $0.start < $1.start }) {
      if let last = result.last, span.start <= last.end {
        result[result.count - 1].end = max(last.end, span.end)
      } else {
        result.append(span)
      }
    }
    return result
  }

  /// The seconds of the stretch that lie outside the `named` times.
  static func uncovered(_ stretch: Range<Int>, in spoken: SpokenRuns, by named: [Span]) -> Double {
    let start = spoken.starts[stretch.lowerBound]
    let end = spoken.ends[stretch.upperBound - 1]
    var covered = 0.0
    for span in named where span.start < end {
      covered += max(0, min(end, span.end) - max(start, span.start))
    }
    return max(0, end - start - covered)
  }

  /// Part of a stretch that is left to offer: its words and its times.
  struct Piece {
    var words: Range<Int>
    var start: Double
    var end: Double
  }

  /// What is left of a stretch outside the `named` times and before the end of the episode
  /// (`limit`, when it is known): the pieces that are still at least 15 seconds and 25 words.
  static func pieces(
    of stretch: Range<Int>, in spoken: SpokenRuns, around named: [Span], before limit: Double?
  ) -> [Piece] {
    let last = min(spoken.ends[stretch.upperBound - 1], limit ?? .infinity)
    var times: [Span] = []
    var cursor = spoken.starts[stretch.lowerBound]
    for span in named where span.end > cursor {
      if span.start >= last { break }
      if span.start > cursor { times.append((cursor, span.start)) }
      cursor = max(cursor, span.end)
    }
    if cursor < last { times.append((cursor, last)) }

    var result: [Piece] = []
    for time in times where time.end - time.start >= shortest {
      let inside = stretch.filter {
        spoken.middle(of: $0) >= time.start && spoken.middle(of: $0) <= time.end
      }
      guard inside.count >= fewestWords, let first = inside.first, let final = inside.last else {
        continue
      }
      result.append(Piece(words: first..<(final + 1), start: time.start, end: time.end))
    }
    return result
  }

  // MARK: Stretches the listener denied

  /// The times of the stretch where it says what a stretch denied earlier said: where the runs
  /// kept for a denied stretch (`denied`) are found, at least `fewestRunsToCut` of them with at
  /// most `maxGap` runs between. Each is a second wider on both sides, like a named ad, and is
  /// cut out of the stretch, so a denied passage next to an ad read does not hide the ad read.
  static func deniedTimes(in stretch: Range<Int>, of spoken: SpokenRuns, by denied: Set<UInt32>)
    -> [Span]
  {
    guard !denied.isEmpty else { return [] }
    let lastRun = min(stretch.upperBound - SpokenRuns.runLength, spoken.hashes.count - 1)
    guard stretch.lowerBound <= lastRun else { return [] }
    var parts: [(first: Int, last: Int, count: Int)] = []
    for run in stretch.lowerBound...lastRun where denied.contains(spoken.hashes[run]) {
      if let at = parts.indices.last, run - parts[at].last - 1 <= maxGap {
        parts[at].last = run
        parts[at].count += 1
      } else {
        parts.append((run, run, 1))
      }
    }
    return parts.filter { $0.count >= fewestRunsToCut }.map {
      (
        start: spoken.starts[$0.first] - apart,
        end: spoken.ends[$0.last + SpokenRuns.runLength - 1] + apart
      )
    }
  }
}
