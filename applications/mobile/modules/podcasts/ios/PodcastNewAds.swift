// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The plain rules for the ads the new finders give, with no file, clock or lock: what a sound or
// a repeat turns into, which parts lie outside the ads that are known already, and the snap of
// borders onto the joints of the file. The finders' wiring is PodcastAdFinder+New.swift and
// PodcastStreamHead+Local.swift.
import Foundation
import PodcastAds
import PodcastAudioMatch

/// The plain rules for the ads of the new finders, with no file, clock or lock.
enum NewAds {
  /// A new finder's ad stays this far from every other ad. `AdJoin` joins ads that lie within
  /// half a second, and it takes the higher confidence and drops the name, so no new ad may come
  /// that near.
  static let apart = 0.6
  /// How far from an ad's start a trim of it may lie before the ad is left alone by the snap: a
  /// trim is found by where its ad started, and the snap moves that start up to 3 seconds, or up to
  /// the pull distance for an ad the pull may apply to (`JointSnap.trimReach`).
  static func trimReach(for ad: FoundAd) -> Double {
    JointSnap.trimReach(pulled: JointPull.allows(source: ad.source))
  }

  /// An ad's borders before and after the snap moved them.
  struct Moved: Equatable {
    var wasStart: Double
    var wasEnd: Double
    var start: Double
    var end: Double
  }

  static func overlap(_ a: FoundAd, _ b: FoundAd) -> Bool { a.start < b.end && b.start < a.end }

  /// Whether a stretch the listener undid or said "no" to lies over `ad`.
  static func overlap(_ a: UndoneAd, _ b: FoundAd) -> Bool { a.start < b.end && b.start < a.end }

  /// The ads of sounds that were heard (sure, as `LocalAdsFile.soundAd` makes them). A hit of a
  /// sort the Mac does not know is left out.
  static func ads(ofSounds hits: [AdSoundHit]) -> [FoundAd] {
    hits.compactMap {
      LocalAdsFile.soundAd(sort: $0.sort, who: $0.who, start: $0.start, end: $0.end)
    }
  }

  /// The ads of repeated sounds: plain ads, unsure, of 10 to 300 seconds (the ads' own rules).
  static func ads(ofRepeats stretches: [RepeatStretch]) -> [FoundAd] {
    stretches.compactMap { stretch in
      guard stretch.start.isFinite, stretch.end.isFinite, stretch.start >= 0,
        (AdRules.minLength...AdRules.maxLength).contains(stretch.end - stretch.start)
      else { return nil }
      return FoundAd(
        start: stretch.start, end: stretch.end, kind: .ad, advertiser: "", confidence: .unsure,
        firstWords: "")
    }
  }

  /// The parts of `ads` that lie outside every blocker (each widened by `apart`), at least
  /// `AdRules.minLength` seconds long and at most `AdRules.maxLength`. An ad nothing touches comes
  /// back whole. Ads and blockers that are not real stretches are ignored.
  static func outside(_ ads: [FoundAd], of blockers: [FoundAd]) -> [FoundAd] {
    var spans: [(start: Double, end: Double)] = []
    for blocker in blockers.sorted(by: { $0.start < $1.start })
    where blocker.start.isFinite && blocker.end.isFinite && blocker.end > blocker.start {
      let wide = (start: blocker.start - apart, end: blocker.end + apart)
      if let last = spans.last, wide.start <= last.end {
        spans[spans.count - 1].end = max(last.end, wide.end)
      } else {
        spans.append(wide)
      }
    }
    var result: [FoundAd] = []
    for ad in ads where ad.start.isFinite && ad.end.isFinite && ad.end > ad.start {
      var from = ad.start
      var parts: [(start: Double, end: Double)] = []
      for span in spans where span.end > from {
        if span.start >= ad.end { break }
        if span.start > from { parts.append((from, span.start)) }
        from = max(from, span.end)
      }
      if from < ad.end { parts.append((from, ad.end)) }
      for part in parts
      where (AdRules.minLength...AdRules.maxLength).contains(part.end - part.start) {
        var piece = ad
        piece.start = part.start
        piece.end = part.end
        result.append(piece)
      }
    }
    return result
  }

  /// What the head scan saves after a step: the ads of the memory, the old local layers, the
  /// model and the own sounds, joined. The own sounds were cut against the model's ads of the step
  /// before; the model's new answer may lie over them, so they are cut again here, or `AdJoin`
  /// would make one longer ad of an own ad over a model ad, with the finder's name lost.
  static func headAds(
    _ remembered: [FoundAd], _ local: (old: [FoundAd], own: [FoundAd]), model: [FoundAd]
  ) -> [FoundAd] {
    let own = outside(local.own, of: remembered + local.old + model)
    return AdHeadRules.merge(remembered + local.old + own + model)
  }

  /// The ads (in order of start) with each border put on a joint of the file, when `JointSnap`
  /// finds one near. An ad that `fixed` names is left as it is. An ad's start never goes before
  /// the end of the ad before it (after that one's own snap), and its end never after the start of
  /// the next as it was found. Between two ads of different finders (`source`) the snap keeps
  /// `apart` seconds, so it never leaves them close enough for `AdJoin` to join them. The pull of
  /// a late start is only for the ads `JointPull` names, and it keeps out of the stretches in
  /// `judged` (the listener's "no" answers, open questions and undone skips); the start's floor is
  /// the latest end of ALL the ads before it.
  static func snap(
    _ found: [FoundAd], joints: Joints, steadyToo: Bool,
    judged: [(start: Double, end: Double)] = [],
    leaving fixed: (FoundAd) -> Bool = { _ in false }
  ) -> (ads: [FoundAd], moved: [Moved]) {
    var ads = found
    var moved: [Moved] = []
    func room(_ ad: FoundAd, _ neighbour: FoundAd) -> Double {
      ad.source == neighbour.source ? 0 : apart
    }
    for (index, ad) in found.enumerated() where !fixed(ad) {
      let earlierEnd = ads[..<index].map { $0.end + room(ad, $0) }.max()
      let after = index + 1 < found.count ? found[index + 1] : nil
      let to = JointSnap.snap(
        start: ad.start, end: ad.end, joints: joints,
        previousEnd: earlierEnd, nextStart: after.map { $0.start - room(ad, $0) }, steadyToo: steadyToo,
        mayPull: JointPull.allows(source: ad.source), judged: judged)
      guard to.start != ad.start || to.end != ad.end else { continue }
      ads[index].start = to.start
      ads[index].end = to.end
      moved.append(Moved(wasStart: ad.start, wasEnd: ad.end, start: to.start, end: to.end))
    }
    return (ads, moved)
  }

  /// The ad with the borders it was found with: the ones the snap moved are put back. An ad the
  /// snap did not move is given back as it is.
  static func restored(_ ad: FoundAd, from moved: [Moved]) -> FoundAd {
    guard let was = moved.first(where: { $0.start == ad.start && $0.end == ad.end }) else {
      return ad
    }
    var original = ad
    original.start = was.wasStart
    original.end = was.wasEnd
    return original
  }

  /// An ad that the listener confirmed (source "tap"), undid or trimmed keeps its borders.
  static func isFixed(_ ad: FoundAd, in file: AdsFile) -> Bool {
    ad.source == AdAsking.source || file.isUndone(ad)
      || (file.trims ?? []).contains { $0.adStart >= ad.start - trimReach(for: ad) && $0.adStart < ad.end }
  }
}
