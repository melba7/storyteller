// LOFI-FORK: ads remembered by their words, so a repeat is found at once (see FORK.md).
//
// The same inserted spot or sponsor read comes back in many episodes of a show. This keeps the
// words of each ad that was found for sure and finds them again in a later transcript, with
// edges exact to the word. It is text only: no sound, no decoder. The idea of a store of repeats
// built on the fly comes from "Efficient Advertisement Discovery for Audio Podcast Content" (2010),
// and of learning only sure ads of a sensible length from MinusPod (MIT,
// github.com/ttlequals0/MinusPod). Foundation only.
import Foundation
import PodcastTranscripts

/// One remembered ad.
public struct KnownAd: Codable, Sendable, Equatable {
  public var showId: String
  public var advertiser: String
  public var kind: AdKind
  /// The ad's first words (at most `KnownAds.mostWords`): lower case, no punctuation, one space
  /// apart. One string rather than a list keeps the file small.
  public var text: String
  /// How long the ad lasted, in seconds.
  public var length: Double
  public var seen: Int
  public var lastSeen: Date

  public init(
    showId: String, advertiser: String, kind: AdKind, text: String, length: Double, seen: Int,
    lastSeen: Date
  ) {
    self.showId = showId
    self.advertiser = advertiser
    self.kind = kind
    self.text = text
    self.length = length
    self.seen = seen
    self.lastSeen = lastSeen
  }

  public var words: [String] { text.split(separator: " ").map(String.init) }
}

/// Where a remembered ad was found in a transcript, in seconds of audio.
public enum KnownAdMatch: Equatable, Sendable {
  /// The ad is there from `start` to `end`: the first and last words that matched.
  case whole(start: Double, end: Double)
  /// The transcript ends inside the ad, which begins at `start`. It should last until about
  /// `expectedEnd`.
  case opening(start: Double, expectedEnd: Double)

  public var start: Double {
    switch self {
    case .whole(let start, _), .opening(let start, _): return start
    }
  }
}

/// A remembered ad and where it was found.
public struct KnownAdHit: Equatable, Sendable {
  public var ad: KnownAd
  public var match: KnownAdMatch
}

/// Everything that is remembered, kept in one small file (`known-ads.json`).
public struct KnownAds: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "known-ads.json"

  /// An ad is learned only when it is sure, was not undone or trimmed, lasts `shortest` to
  /// `longest` seconds and has at least `fewestWords` words. Only its first `mostWords` are kept.
  public static let shortest = 15.0
  public static let longest = 120.0
  public static let fewestWords = 25
  public static let mostWords = 150
  /// At most this many ads are kept for one show and in all; one not seen for `keepDays` days goes.
  public static let mostPerShow = 40
  public static let mostInAll = 400
  public static let keepDays = 60.0

  // How a remembered ad is found: words are compared in runs of `runLength`. The ad opens where
  // `openingNeeded` of its first `openingRuns` runs appear in order within `openingReach` words,
  // and goes on while its runs keep appearing with at most `gapWords` unmatched words between.
  // With three fifths of its runs found it is whole.
  static let runLength = 3
  static let openingRuns = 10
  static let openingNeeded = 6
  static let openingReach = 16
  static let gapWords = 12

  public var version: Int
  public var ads: [KnownAd]

  public init(ads: [KnownAd] = []) {
    version = Self.currentVersion
    self.ads = ads
  }

  // MARK: Words

  /// A word as it is compared: lower case, letters and digits only. Nil when nothing is left.
  public static func normalise(_ word: String) -> String? {
    let kept = String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    return kept.isEmpty ? nil : kept
  }

  /// The first words of an ad in a transcript, normalised: those whose middle lies in the ad.
  static func words(of ad: FoundAd, in transcript: Transcript) -> [String] {
    words(from: ad.start, to: ad.end, in: transcript.words)
  }

  /// The first words between two times of some timed words, normalised: those whose middle lies
  /// between them.
  static func words(from start: Double, to end: Double, in timed: [TranscriptWord]) -> [String] {
    var result: [String] = []
    for word in timed {
      let middle = (word.start + word.end) / 2
      if middle > end { break }
      guard middle >= start, let text = normalise(word.text) else { continue }
      result.append(text)
      if result.count == mostWords { break }
    }
    return result
  }

  // MARK: Learning

  /// Remembers the ads of a final ads file that are worth finding again: sure ones the listener
  /// did not undo or trim (`trimmed` holds the starts of the ads that were trimmed). An ad that
  /// matches one already known is counted again instead.
  public mutating func learn(
    from file: AdsFile, transcript: Transcript, show: String, trimmed: [Double] = [], now: Date
  ) {
    guard file.coveredUntil == nil else { return }
    for ad in file.ads where ad.confidence == .sure && !file.isUndone(ad) {
      guard (Self.shortest...Self.longest).contains(ad.duration),
        !trimmed.contains(where: { AdTrim(adStart: $0, end: ad.end).applies(to: ad) })
      else { continue }
      let words = Self.words(of: ad, in: transcript)
      guard words.count >= Self.fewestWords else { continue }
      if let at = ads.firstIndex(where: { $0.showId == show && Self.same($0.words, words) }) {
        ads[at].seen += 1
        ads[at].lastSeen = now
        ads[at].length = ad.duration
        if ads[at].advertiser.isEmpty { ads[at].advertiser = ad.advertiser }
      } else {
        ads.append(
          KnownAd(
            showId: show, advertiser: ad.advertiser, kind: ad.kind, text: words.joined(separator: " "),
            length: ad.duration, seen: 1, lastSeen: now))
      }
    }
    prune(now: now)
  }

  /// Drops the ads not seen for `keepDays` days, then the least recently seen ones beyond
  /// `mostPerShow` for a show and `mostInAll`. The newest come first afterwards.
  public mutating func prune(now: Date) {
    let oldest = now.addingTimeInterval(-Self.keepDays * 86_400)
    var kept = ads.filter { $0.lastSeen >= oldest }
    kept.sort { ($0.lastSeen, $0.seen) > ($1.lastSeen, $1.seen) }
    var perShow: [String: Int] = [:]
    kept = kept.filter {
      perShow[$0.showId, default: 0] += 1
      return perShow[$0.showId, default: 0] <= Self.mostPerShow
    }
    ads = Array(kept.prefix(Self.mostInAll))
  }

  // MARK: Finding

  /// The remembered ads of `show` that `words` (a transcript's words, timed) contain, by start.
  public func find(in words: [TranscriptWord], show: String) -> [KnownAdHit] {
    let timed = words.compactMap { word in
      Self.normalise(word.text).map { (text: $0, start: word.start, end: word.end) }
    }
    let index = RunIndex(timed.map(\.text))
    var hits: [KnownAdHit] = []
    for ad in ads where ad.showId == show {
      let runs = Self.runs(of: ad.words)
      for chain in Self.chains(of: runs, in: index) {
        let start = timed[chain.first].start
        if Self.isWhole(chain, of: runs.count) {
          hits.append(KnownAdHit(ad: ad, match: .whole(start: start, end: timed[chain.last].end)))
        } else if timed.count - 1 - chain.last <= Self.gapWords {
          // The transcript ended before the ad did.
          hits.append(
            KnownAdHit(ad: ad, match: .opening(start: start, expectedEnd: start + ad.length)))
        }
      }
    }
    return hits.sorted { $0.match.start < $1.match.start }
  }

  /// Whether two lists of words are one ad: the runs of one are found, as a whole, in the other.
  static func same(_ a: [String], _ b: [String]) -> Bool {
    func found(_ ad: [String], in other: [String]) -> Bool {
      let runs = Self.runs(of: ad)
      return Self.chains(of: runs, in: RunIndex(other)).contains { isWhole($0, of: runs.count) }
    }
    return found(a, in: b) || found(b, in: a)
  }
}

// MARK: Matching runs of words

extension KnownAds {
  /// The runs of `runLength` words in a list of words, each as its words joined by a space.
  static func runs(of words: [String]) -> [String] {
    guard words.count >= runLength else { return [] }
    return (0...(words.count - runLength)).map {
      words[$0..<($0 + runLength)].joined(separator: " ")
    }
  }

  /// Where each run occurs in a list of words (the index of its first word), in order.
  struct RunIndex {
    let positions: [String: [Int]]

    init(_ words: [String]) {
      var found: [String: [Int]] = [:]
      for (at, run) in KnownAds.runs(of: words).enumerated() { found[run, default: []].append(at) }
      positions = found
    }
  }

  /// One place where a remembered ad was found: the indexes of the first and of the last word
  /// that matched, and how many of the ad's runs were found.
  struct Chain {
    var first: Int
    var last: Int
    var found: Int
  }

  /// Whether at least three fifths of the ad's `total` runs were found.
  static func isWhole(_ chain: Chain, of total: Int) -> Bool { chain.found * 5 >= total * 3 }

  /// Every place the runs of an ad occur in order in `index`'s words. An ad opens where enough of
  /// its first runs come close together, then goes on run by run while the next one is found
  /// within `gapWords` words of the last match. A run that is not found is passed over.
  static func chains(of runs: [String], in index: RunIndex) -> [Chain] {
    let head = runs.prefix(openingRuns).map { index.positions[$0] ?? [] }
    var result: [Chain] = []
    var from = 0
    for q in Set(head.flatMap { $0 }).sorted() {
      guard q >= from else { continue }
      var cursor = q
      var first: Int?
      var last = q
      var found = 0
      for hits in head {
        guard let hit = hits.first(where: { $0 >= cursor && $0 + runLength <= q + openingReach })
        else { continue }
        first = first ?? hit
        found += 1
        cursor = hit + 1
        last = hit + runLength - 1
      }
      guard found >= openingNeeded, let start = first else { continue }
      for run in runs.dropFirst(openingRuns) {
        guard
          let hit = (index.positions[run] ?? []).first(where: {
            $0 >= cursor && $0 <= last + 1 + gapWords
          })
        else { continue }
        found += 1
        cursor = hit + 1
        last = hit + runLength - 1
      }
      result.append(Chain(first: start, last: last, found: found))
      from = last + 1
    }
    return result
  }
}

// MARK: The file

extension KnownAds {
  /// What was saved at `url`, or nothing when there is no file, it cannot be read or it is of
  /// another version.
  public static func load(from url: URL) -> KnownAds {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: url),
      let saved = try? decoder.decode(KnownAds.self, from: data), saved.version == currentVersion
    else { return KnownAds() }
    return saved
  }

  /// Saves everything at `url`, making its folder first.
  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
