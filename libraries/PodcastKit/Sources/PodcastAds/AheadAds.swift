// LOFI-FORK: the finder "ahead": the ads the Mac marked in an episode the night before, found again
// in the phone's own transcript of it (see FORK.md and AheadFile.swift). Foundation only.
import Foundation
import PodcastTranscripts

// HOW AN AD IS FOUND. The Mac's copy of an episode can differ from the phone's (dynamic ad
// insertion), so a mark is not used by its times but by its words: the ad's first words and its last
// words are looked for in the words of the phone's transcript, with the matching that finds a
// remembered ad again (`KnownAds`: runs of three words, three fifths of them must be found, so a
// few words heard differently do not matter). The ad starts where its first words start and ends
// where its last words end, landed as the clean-up lands every ad (`AdLanding`). It is accepted
// only when both edges are found and the length between them is half to one and a half times the
// length the Mac marked. Where only one edge is found, or the two do not fit, the finder offers an
// unsure stretch of the marked length from the edge it found, as a question (`asks`): a half match
// never skips. A mark Claude was not sure of ("low", the doubtful stretches) never skips either,
// whatever is found of it: it is a question, and so it is not in the head scan of a stream, which
// takes only the skips. It runs on a whole transcript and on the words so far of a stream's head; in
// the head an ad is there once its end words have arrived.
//
// THE PHONE'S WIRING. The settings (`ShowTuning.apply`) and the guard run on this finder's own
// ads BEFORE any join, as for every new finder. `ads` are skips; `asks` only ever ask, whatever
// level the settings give. Like every new finder its ads are made `unsure` at most when they are
// collected, so the listener can undo them.

/// What one look for an episode's marks found.
public struct AheadFound: Sendable, Equatable {
  /// Both edges were found, the length fits and Claude was sure of the mark ("high" or "medium"):
  /// skips.
  public var ads: [FoundAd]
  /// Only one edge was found, or the two do not fit, or Claude marked the stretch as "low": unsure
  /// stretches that may be asked about, never skipped.
  public var asks: [FoundAd]

  public init(ads: [FoundAd] = [], asks: [FoundAd] = []) {
    self.ads = ads
    self.asks = asks
  }
}

public enum AheadAds {
  /// The `source` of the ads it makes, and its name in the settings and the guard.
  public static let source = ShowTuning.ahead
  /// A mark with fewer words than this at an edge cannot be told from talk, so it is not looked for.
  public static let fewestWords = 8
  /// The length of an ad found, against the length the Mac marked.
  public static let lengthBand = 0.5...1.5
  /// And the copy may hold at most this many seconds more than the marked length: on a long ad the
  /// band alone would let a stretch of other talk between two copies of an edge pass as the ad.
  public static let mostExtraSeconds = 15.0

  /// The ads of `entry` in the words of one transcript (the whole of it or the head so far), by
  /// start. Nothing that overlaps a stretch in `judged` (the ones the listener undid, said no to or
  /// was asked about) is given.
  public static func find(
    _ entry: AheadEntry, words: [TranscriptWord],
    judged: [(start: Double, end: Double)] = []
  ) -> AheadFound {
    let heard = KnownAds.Heard(words)
    guard let last = heard.timed.last else { return AheadFound() }
    var whole: [FoundAd] = []
    var half: [FoundAd] = []
    for mark in entry.ads {
      let length = mark.end - mark.start
      guard length.isFinite, length > 0 else { continue }
      let starts = places(of: mark.startWords, in: heard)
      let ends = places(of: mark.endWords, in: heard)
      let pairs = fitting(starts, ends, heard: heard, length: length)
      for (from, to) in pairs {
        let begin = heard.timed[starts[from].first].start
        let finish = heard.timed[ends[to].last].end
        if mark.confidence == .low {
          half.append(ask(mark, from: begin, to: finish, words: words))
        } else {
          whole.append(ad(mark, from: begin, to: finish, words: words))
        }
      }
      let startsUsed = Set(pairs.map(\.0)), endsUsed = Set(pairs.map(\.1))
      for (at, place) in starts.enumerated() where !startsUsed.contains(at) {
        let begin = heard.timed[place.first].start
        half.append(ask(mark, from: begin, to: min(begin + length, last.end), words: words))
      }
      for (at, place) in ends.enumerated() where !endsUsed.contains(at) {
        let finish = heard.timed[place.last].end
        half.append(ask(mark, from: max(0, finish - length), to: finish, words: words))
      }
    }
    func clear(_ ad: FoundAd) -> Bool {
      !judged.contains { ad.start < $0.end && $0.start < ad.end }
    }
    let skips = whole.filter(clear).sorted { $0.start < $1.start }
    let asks = half.filter { ask in
      clear(ask) && ask.duration >= AdRules.minLength
        && !skips.contains { $0.start < ask.end && ask.start < $0.end }
    }.sorted { $0.start < $1.start }
    return AheadFound(ads: skips, asks: asks)
  }

  // MARK: Finding the words

  /// Where the words of `text` are in the transcript (the matching of a remembered ad), by place.
  static func places(of text: String, in heard: KnownAds.Heard) -> [KnownAds.Chain] {
    let words = text.split(whereSeparator: \.isWhitespace).compactMap { KnownAds.normalise(String($0)) }
    guard words.count >= fewestWords else { return [] }
    let runs = KnownAds.runs(of: words)
    let direct = KnownAds.chains(of: runs, in: heard.index).filter {
      KnownAds.isWhole($0, of: runs.count)
    }
    let sturdy = KnownAds.sturdy(words, in: heard).filter { found in
      !direct.contains { KnownAds.sharesWords($0, found) }
    }
    return (direct + sturdy).sorted { $0.first < $1.first }
  }

  /// The pairs (a start place, an end place) that make an ad: the end comes after the start and the
  /// length is within `lengthBand` of the marked one. The pairs closest to the marked length come
  /// first, and a place is in one pair only.
  private static func fitting(
    _ starts: [KnownAds.Chain], _ ends: [KnownAds.Chain], heard: KnownAds.Heard, length: Double
  ) -> [(Int, Int)] {
    var candidates: [(from: Int, to: Int, off: Double)] = []
    for (from, start) in starts.enumerated() {
      for (to, end) in ends.enumerated() {
        let seconds = heard.timed[end.last].end - heard.timed[start.first].start
        guard seconds > 0, lengthBand.contains(seconds / length), seconds <= length + mostExtraSeconds else { continue }
        candidates.append((from, to, abs(seconds - length)))
      }
    }
    var usedStarts = Set<Int>(), usedEnds = Set<Int>()
    var pairs: [(Int, Int)] = []
    for one in candidates.sorted(by: { $0.off < $1.off })
    where !usedStarts.contains(one.from) && !usedEnds.contains(one.to) {
      usedStarts.insert(one.from)
      usedEnds.insert(one.to)
      pairs.append((one.from, one.to))
    }
    return pairs
  }

  // MARK: The ads

  private static func ad(
    _ mark: AheadMark, from: Double, to: Double, words: [TranscriptWord]
  ) -> FoundAd {
    let edges = AdLanding.edges(start: from, end: to, words: words)
    return found(mark, start: edges.start, end: edges.end)
  }

  /// The ad of `mark` between two given times, sure and named after the finder. `PreparedAds`
  /// makes its ads the same way, with the times of the Mac's own copy.
  static func found(_ mark: AheadMark, start: Double, end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: mark.kind, advertiser: "",
      confidence: .sure, firstWords: firstWords(mark), source: source)
  }

  private static func ask(
    _ mark: AheadMark, from: Double, to: Double, words: [TranscriptWord]
  ) -> FoundAd {
    asking(ad(mark, from: from, to: to, words: words))
  }

  /// The stretch as a question: unsure, so it never skips.
  static func asking(_ ad: FoundAd) -> FoundAd {
    var found = ad
    found.confidence = .unsure
    return found
  }

  private static func firstWords(_ mark: AheadMark) -> String {
    mark.startWords.split(whereSeparator: \.isWhitespace).prefix(AdRules.firstWords)
      .joined(separator: " ")
  }
}
