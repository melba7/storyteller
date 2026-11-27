// LOFI-FORK: the ads file of a copy the Mac prepared (see FORK.md, AheadFile.swift and docs/PLAN.md,
// milestone Y4). Foundation only.
import Foundation

// WHY THESE ADS ARE DIFFERENT. The phone plays the very file the Mac marked, so the times of the
// marks hold to the frame and the marks are not looked for again by their words. The ads file made
// here is final: it is marked `prepared`, no finder of the phone adds to it (each writer of found
// ads leaves such a file alone, and `AdsRules.status` calls it finished whatever the detector's
// version), and only the listener changes it: the Undo, a "no", a trim and the Skip ad button.
//
// THE NAME. "prepared" is the `source` of its ads, which the notes carry and the tally can count.
// It is not a finder: it is not in `ShowTuning.finderNames`, the Mac's settings cannot set it, and
// `FinderGuard` keeps no answers about it, so an Undo of a prepared ad blames no finder.

public enum PreparedAds {
  /// The `source` of the ads of a prepared file.
  public static let source = "prepared"
  /// The name of the detector a prepared file is saved under, so that every reader of an episode's
  /// ads finds it. This must equal the phone's `PodcastAdFinder.detectorName`; the wiring passes
  /// that name to `file(for:duration:detector:)`.
  public static let detector = "apple-on-device"
  /// The `detectorVersion` of a prepared file. It is not the local finders' empty version, so
  /// nothing that looks for local-only files finds it.
  public static let detectorVersion = "prepared"

  /// The finder name a note of a skip or an Undo carries for an ad of this source: "prepared" for a
  /// prepared ad, nil for any other or for none (a note of a skip names no finder, as before).
  public static func noteName(forSource source: String?) -> String? {
    source == Self.source ? Self.source : nil
  }

  /// The ads file of the copy `entry` names, or nil when the entry has no copy or `duration` (the
  /// copy's length in seconds) is not a real length. Its SHA-256 is the copy's.
  ///
  /// High and medium marks become ads at the marks' own times, skipped by default; they are
  /// `unsure` at most, as every new finder's ads are, so that the listener can undo them. A low
  /// mark becomes a question as an ahead mark that is only half found does (`AheadAds.asking` and
  /// `AdAsking.adding`). The marks are cut to the copy's length, ones with no stretch left are
  /// dropped, and marks that overlap are joined (`AdJoin`) so the skipper never sees two ads over
  /// one stretch.
  public static func file(
    for entry: AheadEntry, duration: Double, detector: String = PreparedAds.detector
  ) -> AdsFile? {
    guard let copy = entry.copy, duration.isFinite, duration > 0 else { return nil }
    var skips: [FoundAd] = []
    var asks: [FoundAd] = []
    for mark in entry.ads {
      guard mark.start.isFinite, mark.end.isFinite else { continue }
      let start = max(0, mark.start)
      let end = min(duration, mark.end)
      guard end > start else { continue }
      var ad = AheadAds.found(mark, start: start, end: end)
      ad.source = source
      ad.confidence = .unsure
      if mark.confidence == .low { asks.append(AheadAds.asking(ad)) } else { skips.append(ad) }
    }
    var file = AdsFile(
      sha256: copy.sha256, detector: detector, detectorVersion: detectorVersion, osVersion: "",
      duration: duration, ads: AdJoin.join(skips, touching: 0))
    file = AdAsking.adding(asks.sorted { $0.start < $1.start }, to: file)
    file.prepared = true
    return file
  }
}
