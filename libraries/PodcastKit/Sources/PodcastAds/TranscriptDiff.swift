// LOFI-FORK: words the publisher's transcript does not have are inserted audio (see FORK.md).
//
// A feed's `podcast:transcript` is made from the show before a host stitches ads into the audio
// (RSS.com says its transcripts do not move when it inserts ads), so the words of our own
// transcript that it lacks, between stretches that match, are inserted audio. The idea of
// comparing two versions of an episode by their words, "matched runs are content, mismatched runs
// are ads", is from US patent 12190871; nothing else of it is used. Foundation only.
//
// This is the pure part. Nothing fetches the feed's file or calls `inserted` yet.
import Foundation
import PodcastTranscripts

public enum TranscriptDiff {
  /// Our words that the publisher's transcript does not have: the indexes of our words, and the
  /// seconds from the first one's start to the last one's end.
  public struct Stretch: Sendable, Equatable {
    public var words: Range<Int>
    public var start: Double
    public var end: Double

    public init(words: Range<Int>, start: Double, end: Double) {
      self.words = words
      self.start = start
      self.end = end
    }
  }

  /// How many equal words in a row make a place where the two transcripts agree.
  static let anchorLength = 5
  /// A stretch is at least this many words and this many seconds long.
  public static let minWords = 20
  public static let minSeconds = 8.0
  /// With fewer of our words than this share found in theirs, the transcripts are not of the same
  /// show (another language, a summary) or theirs was made from the stitched file and has the ads.
  static let minShared = 0.5
  /// A run of words that occurs more often than this in theirs ("you know what I mean") says
  /// nothing about where we are.
  private static let mostRepeats = 8

  /// Our unmatched stretches, in order. Words match when they stand in runs of `anchorLength` equal
  /// words that come in the same order in both transcripts; a lone changed word does not make a
  /// stretch. A stretch counts when it is long enough and has a match after it (one that runs to
  /// the end of our words may be a head that is still downloading), and, unless it is at the
  /// start, a match before it. Nil when under half of our words match at all.
  public static func inserted(ours: [TranscriptWord], theirs: [String]) -> [Stretch]? {
    var tokens: [String] = []
    var origin: [Int] = []
    for (index, word) in ours.enumerated() {
      if let token = KnownAds.normalise(word.text) {
        tokens.append(token)
        origin.append(index)
      }
    }
    guard !tokens.isEmpty else { return nil }
    let matched = matchedTokens(tokens, theirs)
    guard Double(matched.filter { $0 }.count) >= minShared * Double(tokens.count) else { return nil }

    var found: [Stretch] = []
    var at = 0
    while at < tokens.count {
      guard !matched[at] else {
        at += 1
        continue
      }
      var stop = at
      while stop < tokens.count, !matched[stop] { stop += 1 }
      let first = ours[origin[at]]
      let last = ours[origin[stop - 1]]
      if stop - at >= minWords, stop < tokens.count, last.end - first.start >= minSeconds {
        found.append(Stretch(words: origin[at]..<(origin[stop - 1] + 1), start: first.start, end: last.end))
      }
      at = stop
    }
    return found
  }

  /// Which of our tokens lie in a run of `anchorLength` that theirs has in the same order. Of all
  /// the places a run could be matched, the longest chain that keeps the order is taken, so a
  /// phrase that occurs twice cannot pull the alignment away.
  private static func matchedTokens(_ ours: [String], _ theirs: [String]) -> [Bool] {
    var matched = [Bool](repeating: false, count: ours.count)
    guard ours.count >= anchorLength, theirs.count >= anchorLength else { return matched }
    var index: [String: [Int]] = [:]
    for at in 0...(theirs.count - anchorLength) {
      index[theirs[at..<(at + anchorLength)].joined(separator: " "), default: []].append(at)
    }
    // Every place a run of ours is in theirs, by our place and then theirs, the latest first, so
    // one run of ours is never used twice in a chain.
    var pairs: [(ours: Int, theirs: Int)] = []
    for at in 0...(ours.count - anchorLength) {
      guard let places = index[ours[at..<(at + anchorLength)].joined(separator: " ")],
        places.count <= mostRepeats
      else { continue }
      for place in places.reversed() { pairs.append((at, place)) }
    }
    // The longest chain whose places in theirs keep rising (patience sorting).
    var tails: [Int] = []
    var before = [Int](repeating: -1, count: pairs.count)
    for (number, pair) in pairs.enumerated() {
      var low = 0
      var high = tails.count
      while low < high {
        let mid = (low + high) / 2
        if pairs[tails[mid]].theirs < pair.theirs { low = mid + 1 } else { high = mid }
      }
      if low > 0 { before[number] = tails[low - 1] }
      if low == tails.count { tails.append(number) } else { tails[low] = number }
    }
    var number = tails.last ?? -1
    while number >= 0 {
      for at in pairs[number].ours..<(pairs[number].ours + anchorLength) { matched[at] = true }
      number = before[number]
    }
    return matched
  }
}
