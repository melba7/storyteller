// LOFI-FORK: the words a show opens with, and what they say about an ad at 0:00 (see FORK.md).
//
// Many shows begin every episode with the same few words ("from the example network, this is the
// daily example, I'm Sam"), after whatever pre-roll was put in front. Where those words start in a
// stream's first minutes, the show has begun and a pre-roll that holds 0:00 has ended. This is
// the pure part: finding the words in a head, what that does to the ads, and reading the first
// minutes of an episode for learning (`ShowOpenings` keeps what was learned). The words are found
// with the run matcher of `KnownAds`. Foundation only.
//
// The opening may only shorten an ad or drop an unsure one. A wrong opening (a phrase the host
// also says inside an ad) must never cut a real ad short, so it counts only when it is found in
// the first five minutes and only for an ad that holds 0:00.
import Foundation
import PodcastTranscripts

public enum ShowOpening {
  /// An opening is a run of this many words (`fewestWords` to `mostWords`). Fewer are a phrase
  /// any host says; more are more likely a repeated ad or segment than an opening.
  public static let fewestWords = 8
  public static let mostWords = 40
  /// Only the first five minutes of an episode are read, for learning and for use.
  public static let within = 300.0
  /// So an opening that starts just before `within` can still be heard to its end.
  static let completion = 60.0
  /// An episode's words outside ads are kept up to this many, to compare with the next episode.
  public static let keptWords = 300
  /// A cut never leaves less than this many seconds of the ad.
  static let keptAtLeast = 1.0
  /// An ad ends this long before the first word of the show (as every landing does).
  static let landBefore = AdRules.landBefore

  // MARK: Finding

  /// Where the opening starts in `words` (a transcript's words, timed, from the start of the
  /// episode): the time of its first word, when all of it is there (the run matcher's rule of
  /// three fifths of its runs) and it starts within the first five minutes. Nil otherwise.
  public static func find(_ opening: String, in words: [TranscriptWord]) -> Double? {
    let wanted = opening.split(separator: " ").compactMap { KnownAds.normalise(String($0)) }
    guard wanted.count >= fewestWords else { return nil }
    let timed = words.prefix { $0.start <= within + completion }.compactMap { word in
      KnownAds.normalise(word.text).map { (text: $0, start: word.start) }
    }
    let runs = KnownAds.runs(of: wanted)
    let index = KnownAds.RunIndex(timed.map(\.text))
    for chain in KnownAds.chains(of: runs, in: index) {
      // The time is that of the opening's first word, not of the first run that matched.
      guard KnownAds.isWhole(chain, of: runs.count), timed[chain.first].text == wanted[0],
        timed[chain.first].start <= within
      else { continue }
      return timed[chain.first].start
    }
    return nil
  }

  // MARK: Using

  /// The ads after the opening was found at `opening` seconds. An ad that holds 0:00 and runs past
  /// the opening ends a quarter second before it, when that leaves at least a second of it; an
  /// unsure one is dropped instead. Every other ad is as it was, and no ad is ever longer.
  public static func shorten(_ ads: [FoundAd], openingAt opening: Double) -> [FoundAd] {
    guard opening <= within else { return ads }
    let landing = opening - landBefore
    return ads.compactMap { ad in
      guard ad.start <= 0, ad.end > landing else { return ad }
      if ad.confidence < .sure, ad.end > opening { return nil }
      guard landing >= ad.start + keptAtLeast else { return ad }
      var shorter = ad
      shorter.end = landing
      return shorter
    }
  }

  // MARK: Learning

  /// The words of an episode's first five minutes outside every ad, normalised, as runs of
  /// consecutive words: an ad splits the words around it, so two stretches that were apart are
  /// never read as one. At most `keptWords` words in all. Every ad of the file counts, also an
  /// unsure one and one the listener undid, so the words of a possible ad are never learned.
  static func early(_ words: [TranscriptWord], outside ads: [FoundAd]) -> [[String]] {
    var segments: [[String]] = []
    var current: [String] = []
    var total = 0
    for word in words {
      if word.start > within || total >= keptWords { break }
      let middle = (word.start + word.end) / 2
      if ads.contains(where: { middle >= $0.start && middle <= $0.end }) {
        if !current.isEmpty { segments.append(current) }
        current = []
        continue
      }
      guard let text = KnownAds.normalise(word.text) else { continue }
      current.append(text)
      total += 1
    }
    if !current.isEmpty { segments.append(current) }
    return segments
  }

  /// The run of `fewestWords` to `mostWords` words that two lists of segments share, the one that
  /// starts first in `new`. Nil when they share none. A shared run longer than `mostWords` is
  /// not an opening and is passed over.
  static func sharedRun(_ old: [[String]], _ new: [[String]]) -> [String]? {
    for segment in new {
      for at in segment.indices {
        var best = 0
        for other in old {
          for there in other.indices where other[there] == segment[at] {
            // Only the start of a run counts, so a run is measured once, whole.
            if at > 0, there > 0, segment[at - 1] == other[there - 1] { continue }
            var length = 1
            while at + length < segment.count, there + length < other.count,
              segment[at + length] == other[there + length]
            {
              length += 1
            }
            if length <= mostWords { best = max(best, length) }
          }
        }
        if best >= fewestWords { return Array(segment[at..<(at + best)]) }
      }
    }
    return nil
  }
}
