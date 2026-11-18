// LOFI-FORK: how much in an ad's lines says it really is an ad (see FORK.md).
//
// The model calls an ad "sure" on its own word. Lines that hold a web address, a promo code, an
// offer, a closing phrase of an ad or the advertiser's name are proof it has something to sell;
// an ad with none of them is only unsure. The ads of the quick head rules always hold a web
// address or an offer, so they pass the first check, and a head is too short for the second
// (`AdRules.shareFrom`). Foundation only.
import Foundation
import PodcastTranscripts

enum AdEvidence {
  /// Whether the line holds something an ad says: a hard signal (a web address, a promo code,
  /// an offer, "brought to you by"), a soft cue ("go to", "visit", "thanks to") or the
  /// advertiser's name.
  static func isEvidence(_ text: String, advertiser: String) -> Bool {
    AdSignals.hardSignal(text) || AdSignals.softCue(text)
      || AdSignals.namesAdvertiser(text, advertiser: advertiser)
  }

  /// How many of the lines are evidence.
  static func count<Lines: Sequence>(lines: Lines, advertiser: String) -> Int
  where Lines.Element == TranscriptLine {
    lines.filter { isEvidence($0.text, advertiser: advertiser) }.count
  }
}
