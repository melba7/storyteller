// LOFI-FORK: a taught sound found in a file, as an ad (see FORK.md).
import Foundation

extension LocalAdsFile {
  /// The ad for a sound the phone heard: a sure one, as the sound is the very recording the Mac
  /// marked. This module cannot see the sound scanner, so the hit comes as its parts. Nil when the
  /// sort is not one of the Mac's four or the stretch is not a stretch of the file.
  public static func soundAd(sort: String, who: String, start: Double, end: Double) -> FoundAd? {
    guard let kind = AdKind(sort: sort), start.isFinite, end.isFinite, start >= 0, end > start
    else { return nil }
    return FoundAd(
      start: start, end: end, kind: kind, advertiser: who, confidence: .sure, firstWords: "")
  }
}
