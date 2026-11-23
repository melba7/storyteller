// LOFI-FORK: what the head scan does with the ads it remembers, and forgetting one (see FORK.md).
//
// KnownAds finds a remembered ad in the words of a stream's first minutes. This turns what it
// found into ads to save and says where the scan should look next. Foundation only.
import Foundation
import PodcastTranscripts

extension KnownAds {
  /// Forgets the remembered ads of `show` that are the ad between `start` and `end` in `words`:
  /// the listener undid its skip, so it must not be found again. Returns how many were forgotten.
  @discardableResult
  public mutating func forget(
    start: Double, end: Double, in words: [TranscriptWord], show: String
  ) -> Int {
    let range = Self.words(from: start, to: end, in: words)
    guard range.count >= Self.runLength else { return 0 }
    let before = ads.count
    ads.removeAll { $0.showId == show && Self.same($0.words, range) }
    return before - ads.count
  }
}

/// The ads to save for what the memory found in a stream's head so far, and where the next step
/// of the scan should end.
public struct KnownAdUse: Equatable, Sendable {
  /// A match that is exact to the word is saved as a sure ad. The ad that opens at the end of the
  /// transcript is saved at once only when it was seen at least this many times.
  public static let seenForOpening = 2
  /// An opening is saved ending this long before the time the remembered ad should end, and the
  /// next step of the scan ends this long after it.
  public static let openingMargin = 1.0
  public static let jumpMargin = 10.0
  /// An opening is saved ending at most this far past the end of the words heard so far. The rest
  /// of the remembered read is not heard yet, and a different, shorter read this week must not be
  /// skipped as far as the old one was long.
  public static let guessReach = 5.0
  /// The clean-up's landing numbers (`AdRules.landBefore`, `AdRules.topOfEpisode`): the end lands
  /// a quarter second before the next word, and an ad that begins in the first six seconds begins
  /// at 0:00.
  static let landBefore = AdRules.landBefore
  static let topOfEpisode = AdRules.topOfEpisode
  /// How many of the ad's words are kept to recognise it in a list (the clean-up keeps 14 too).
  static let listedWords = 14

  /// The ads to save, by start. Includes the `provisional` ones.
  public var ads: [FoundAd] = []
  /// The ads whose end is a guess (the ad had not ended in the transcript yet), so they are not
  /// kept when the next step finds a better answer.
  public var provisional: [FoundAd] = []
  /// Seconds of audio the next step should reach, when an ad opens at the end of the transcript.
  public var jumpTo: Double?

  public init() {}

  /// The use of `hits` found in `words`.
  public static func from(_ hits: [KnownAdHit], words: [TranscriptWord]) -> KnownAdUse {
    var use = KnownAdUse()
    for hit in hits {
      switch hit.match {
      case .whole(let start, let end):
        use.ads.append(
          found(hit.ad, start: start, end: landing(of: end, in: words), .sure, source: KnownAds.source))
      case .opening(let start, let expectedEnd):
        use.jumpTo = max(use.jumpTo ?? 0, expectedEnd + jumpMargin)
        let heard = words.last?.end ?? start
        let end = min(expectedEnd - openingMargin, heard + guessReach)
        guard hit.ad.seen >= seenForOpening, end > start + 1 else { continue }
        let ad = found(hit.ad, start: start, end: end, .unsure)
        use.ads.append(ad)
        use.provisional.append(ad)
      }
    }
    use.ads.sort { $0.start < $1.start }
    return use
  }

  /// The ads of a file on disk without the guessed ads that were saved once (`everGuessed`) and
  /// are not guessed any more (`current`): a guessed end must not stay once the whole ad was
  /// found, because the longer of two ads wins when they are joined.
  public static func withoutOutdated(
    _ ads: [FoundAd], everGuessed: [FoundAd], current: [FoundAd]
  ) -> [FoundAd] {
    ads.filter { !everGuessed.contains($0) || current.contains($0) }
  }

  private static func found(
    _ ad: KnownAd, start: Double, end: Double, _ confidence: AdConfidence, source: String? = nil
  ) -> FoundAd {
    FoundAd(
      start: start <= topOfEpisode ? 0 : start, end: end, kind: ad.kind,
      advertiser: ad.advertiser, confidence: confidence,
      firstWords: ad.words.prefix(listedWords).joined(separator: " "), source: source)
  }

  /// The end of a match, a quarter second before the next word when that is earlier: Apple's
  /// word ends can run into the next word, and the first sound of the show must not be clipped.
  private static func landing(of end: Double, in words: [TranscriptWord]) -> Double {
    guard let next = words.first(where: { $0.start >= end - 0.001 }) else { return end }
    return min(end, next.start - landBefore)
  }
}
