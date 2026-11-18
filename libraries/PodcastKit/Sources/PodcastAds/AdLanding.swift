// LOFI-FORK: where the player lands around an ad (see FORK.md).
//
// A skip's end lands a quarter second before the first word of the show, and its start a quarter
// second before the ad's first word, so no word of the show is clipped. An ad whose first word
// is in the first seconds of an episode begins at zero (SponsorBlock's rule for a segment at the
// start); one whose first word comes later (theme music or a cold open before it) does not.
import Foundation
import PodcastTranscripts

enum AdLanding {
  /// How far a time may lie before a line's first word and still count as at it.
  private static let tolerance = 0.01
  /// How far a word may start before an ad's end and still be the show's: Apple's word ends run
  /// on into the next word, so the ad's last word can end a little after the show's first word
  /// starts. A word that starts later than this before the end is the ad's.
  private static let endTolerance = 0.1

  /// The edges to skip for an ad that the lines say runs from `start` to `end`. With no words to
  /// go by (a transcript with only lines) the times stay as they are.
  static func edges(
    start: Double, end: Double, words: [TranscriptWord]
  ) -> (start: Double, end: Double) {
    (landingStart(start, words: words), landingEnd(end, words: words))
  }

  /// The index of the first word that starts at or after `time`. The words are in order.
  private static func firstIndex(
    startingAtOrAfter time: Double, in words: [TranscriptWord]
  ) -> Int {
    var low = 0
    var high = words.count
    while low < high {
      let mid = (low + high) / 2
      if words[mid].start < time { low = mid + 1 } else { high = mid }
    }
    return low
  }

  /// With F the first word of the ad and P the word before it: a quarter second before F, but
  /// not before P ends. Zero when F starts in the first seconds of the episode. With no P and F
  /// later (music or a cold open that has no words), a quarter second before F.
  private static func landingStart(_ time: Double, words: [TranscriptWord]) -> Double {
    let at = firstIndex(startingAtOrAfter: time - tolerance, in: words)
    guard at < words.count else { return time }
    let first = words[at]
    if first.start <= AdRules.topOfEpisode { return 0 }
    guard at > 0 else { return max(0, first.start - AdRules.landBefore) }
    return min(first.start, max(words[at - 1].end, first.start - AdRules.landBefore))
  }

  /// With L the last word that starts before the end (less `endTolerance`) and N the word after
  /// it: a quarter second before N, but not before L starts. L's own end when there is no N.
  private static func landingEnd(_ time: Double, words: [TranscriptWord]) -> Double {
    let at = firstIndex(startingAtOrAfter: time - endTolerance, in: words)
    guard at > 0 else { return time }
    let last = words[at - 1]
    guard at < words.count else { return last.end }
    return max(last.start, words[at].start - AdRules.landBefore)
  }
}
