// LOFI-FORK: finding a remembered ad whose opening was not heard as it was remembered (see FORK.md).
//
// The opening-based search in `KnownAds` needs six of an ad's first ten runs of words close
// together. When the opening is read differently, or the marked ad began a line early or late, the
// whole ad is missed although most of its words match. This looks at all the runs of an ad at
// once: where equal runs of the ad and of the transcript keep the same distance, the ad is there.
// Text only. Foundation only.
import Foundation
import PodcastTranscripts

extension KnownAds {
  /// A stretch of the ad is there when its matching runs lie in a band this many words wide (a
  /// band and its two neighbours are looked at together) and at least `wholeFewest` different runs
  /// of the ad were found, and at least three fifths of the ad's runs (`isWhole`).
  static let bandWidth = 10
  static let wholeFewest = 8
  /// The match is moved outwards by the ad's words that lie before its first matched run (after
  /// its last), by at most this many words.
  static let mostReach = 5

  /// The words of a transcript, prepared once for all the ads that are looked for in them.
  struct Heard {
    /// The normalised words with their times.
    let timed: [(text: String, start: Double, end: Double)]
    /// The runs as text, for the opening-based search.
    let index: RunIndex
    /// Each different word as a number, and where each run of three numbers is.
    let vocabulary: [String: Int32]
    let runsAt: [UInt64: [Int32]]

    init(_ words: [TranscriptWord]) {
      timed = words.compactMap { word in
        KnownAds.normalise(word.text).map { (text: $0, start: word.start, end: word.end) }
      }
      index = RunIndex(timed.map(\.text))
      var numbers: [String: Int32] = [:]
      var ids: [Int32] = []
      ids.reserveCapacity(timed.count)
      for word in timed {
        if let known = numbers[word.text] {
          ids.append(known)
        } else {
          let next = Int32(numbers.count)
          numbers[word.text] = next
          ids.append(next)
        }
      }
      vocabulary = numbers
      var found: [UInt64: [Int32]] = [:]
      if ids.count >= KnownAds.runLength {
        for at in 0...(ids.count - KnownAds.runLength) {
          found[KnownAds.key(ids[at], ids[at + 1], ids[at + 2]), default: []].append(Int32(at))
        }
      }
      runsAt = found
    }
  }

  /// A run of three word numbers as one number (a transcript has far fewer than 2^21 words).
  static func key(_ a: Int32, _ b: Int32, _ c: Int32) -> UInt64 {
    UInt64(a) << 42 | UInt64(b) << 21 | UInt64(c)
  }

  /// Whether two stretches of a transcript (by word index) share a word.
  static func sharesWords(_ a: Chain, _ b: Chain) -> Bool { a.first <= b.last && b.first <= a.last }

  /// Every place the words of an ad are in the transcript as a whole, by position. The ad's runs
  /// that equal a run of the transcript are grouped by how far the two are apart; one place gives
  /// one match, and an ad that is read again later is found again.
  static func sturdy(_ adWords: [String], in heard: Heard) -> [Chain] {
    let total = adWords.count - runLength + 1
    guard total > 0, heard.vocabulary.count < 1 << 21 else { return [] }
    let needed = max(wholeFewest, (total * 3 + 4) / 5)
    let ids = adWords.map { heard.vocabulary[$0] ?? -1 }
    // Which runs of the ad are in the transcript at all. Most ads fail here and cost no more.
    var present: [(at: Int, places: [Int32])] = []
    for at in 0..<total where ids[at] >= 0 && ids[at + 1] >= 0 && ids[at + 2] >= 0 {
      if let places = heard.runsAt[key(ids[at], ids[at + 1], ids[at + 2])] {
        present.append((at, places))
      }
    }
    guard present.count >= needed else { return [] }

    var bands: [Int: [(q: Int, i: Int)]] = [:]
    for (at, places) in present {
      for place in places {
        let gap = Int(place) - at
        let band = gap >= 0 ? gap / bandWidth : (gap - bandWidth + 1) / bandWidth
        bands[band, default: []].append((Int(place), at))
      }
    }
    var result: [Chain] = []
    var done: Set<Int> = []
    for band in bands.keys.sorted(by: { (bands[$0]!.count, $1) > (bands[$1]!.count, $0) }) {
      guard !done.contains(band) else { continue }
      let group = [band - 1, band, band + 1].flatMap { bands[$0] ?? [] }
      let found = Set(group.map(\.i)).count
      guard found >= needed, let first = group.min(by: { ($0.q, $0.i) < ($1.q, $1.i) }),
        let last = group.max(by: { ($0.q, $0.i) < ($1.q, $1.i) })
      else { continue }
      done.formUnion([band - 1, band, band + 1])
      let start = max(0, first.q - min(first.i, mostReach))
      let end = min(
        heard.timed.count - 1,
        last.q + runLength - 1 + min(total - 1 - last.i, mostReach))
      let chain = Chain(first: start, last: end, found: found)
      if !result.contains(where: { sharesWords($0, chain) }) { result.append(chain) }
    }
    return result.sorted { $0.first < $1.first }
  }
}
