// LOFI-FORK: finds the stretches of a new episode that an older episode of the same show already
// said (see RepeatedWords.swift for what it keeps and how the phone must use it). Foundation only.
import Foundation
import PodcastTranscripts

extension RepeatedWords {
  /// Nothing is looked for in the first minute: `ShowOpenings` owns it.
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
  /// A piece stays this many seconds away from an ad that is already named.
  static let apart = 1.0
  /// A piece is not offered when this share of its runs, or of the runs of a stretch denied
  /// earlier, are in the other.
  static let deniedShare = 0.5

  /// The stretches of this episode that an older episode of `show` also said, as unsure ads from
  /// the finder "repeat-words", by start. Nothing is found when the show has no older episode (an
  /// episode is never compared with itself), in the first minute, or in an episode that mostly
  /// repeats (`AdRules.shareLimit`). Nothing returned overlaps an ad in `already`. `duration` is
  /// the episode's length in seconds; 0 or anything that is not a length means it is not known.
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
    let stretches = Self.stretches(in: spoken, known: known)
    guard !stretches.isEmpty else { return [] }

    let usable = duration.isFinite && duration > 0
    let length = usable ? duration : (spoken.ends.last ?? 0)
    let repeated = stretches.reduce(0.0) {
      $0 + spoken.ends[$1.upperBound - 1] - spoken.starts[$1.lowerBound]
    }
    if length >= AdRules.shareFrom, repeated >= AdRules.shareLimit * length { return [] }

    let named = Self.merged(already)
    let denied = entry.denied.filter { !Self.isOld($0, now: now) }.map {
      Set(SpokenRuns.unpack($0.hashes))
    }
    var found: [FoundAd] = []
    let limit: Double? = usable ? duration : nil
    for stretch in stretches {
      for piece in Self.pieces(of: stretch, in: spoken, around: named, before: limit)
      where !Self.isDenied(piece, in: spoken, by: denied) {
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

  /// The words (by index) of each stretch of the episode that is in `known`, for stretches of at
  /// least 15 seconds and 25 words and at most 300 seconds. Runs that start in the first minute
  /// are not looked at.
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

    func close() {
      guard count >= fewestHits else { return }
      let words = from..<(to + SpokenRuns.runLength)
      let seconds = spoken.ends[words.upperBound - 1] - spoken.starts[words.lowerBound]
      guard words.count >= fewestWords, seconds >= shortest, seconds <= longest else { return }
      result.append(words)
    }

    for hit in solid.dropFirst() {
      if hit - to - 1 <= maxGap {
        to = hit
        count += 1
      } else {
        close()
        from = hit
        to = hit
        count = 1
      }
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
  static func merged(_ ads: [FoundAd]) -> [(start: Double, end: Double)] {
    let spans = ads.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
      .map { (start: $0.start - apart, end: $0.end + apart) }
      .sorted { $0.start < $1.start }
    var result: [(start: Double, end: Double)] = []
    for span in spans {
      if let last = result.last, span.start <= last.end {
        result[result.count - 1].end = max(last.end, span.end)
      } else {
        result.append(span)
      }
    }
    return result
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
    of stretch: Range<Int>, in spoken: SpokenRuns, around named: [(start: Double, end: Double)],
    before limit: Double?
  ) -> [Piece] {
    let last = min(spoken.ends[stretch.upperBound - 1], limit ?? .infinity)
    var times: [(start: Double, end: Double)] = []
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

  /// Whether the piece is one the listener said is not an ad: half of the hashes kept for a denied
  /// stretch are in the piece, or half of the piece's runs are in the denied stretches.
  static func isDenied(_ piece: Piece, in spoken: SpokenRuns, by denied: [Set<UInt32>]) -> Bool {
    let lastRun = min(piece.words.upperBound - SpokenRuns.runLength, spoken.hashes.count - 1)
    guard !denied.isEmpty, piece.words.lowerBound <= lastRun else { return false }
    let runs = spoken.hashes[piece.words.lowerBound...lastRun]
    let inPiece = Set(runs)
    var all = Set<UInt32>()
    for stretch in denied where !stretch.isEmpty {
      let shared = stretch.reduce(0) { inPiece.contains($1) ? $0 + 1 : $0 }
      if Double(shared) >= deniedShare * Double(stretch.count) { return true }
      all.formUnion(stretch)
    }
    return Double(runs.filter { all.contains($0) }.count) >= deniedShare * Double(runs.count)
  }
}
