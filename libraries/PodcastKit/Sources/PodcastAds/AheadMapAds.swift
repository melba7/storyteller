// LOFI-FORK: the ads the Mac's episode map gives on the phone's own copy of an episode (see
// FORK.md, AheadAds.swift and EpisodeMap.swift in PodcastAudioMatch). Foundation only.
import Foundation

// WHERE THEY COME FROM. The Mac's map of its copy is lined up with the audio the phone has
// (`EpisodeMapAligner`). That gives the Mac's marks in the phone's seconds, exact to the frame, and
// the stretches only the phone's copy has, which are ads that differ between downloads. This file
// turns both into ads of the finder "ahead", so they are skipped, undone and named as the Mac's
// marks always were. PodcastAds does not know the audio matching, so the stretches come in as
// plain values.

/// A stretch the map gives in the phone's seconds. `kind` and `from` (where the mark starts in the
/// Mac's copy) are those of the Mac's mark; both are nil for a stretch only the phone's copy has.
public struct MapStretchAd: Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var kind: String?
  public var from: Double?

  public init(start: Double, end: Double, kind: String? = nil, from: Double? = nil) {
    self.start = start
    self.end = end
    self.kind = kind
    self.from = from
  }
}

extension AheadAds {
  /// The ads of the map's stretches, by start: sure, named after the finder, joined where they
  /// touch. A carried mark keeps its kind and the first words of the Mac's mark that starts where
  /// it did; a stretch only the phone has is a plain ad. A stretch of an unknown kind, of the
  /// credits or with no real length is left out.
  public static func carried(_ stretches: [MapStretchAd], entry: AheadEntry) -> [FoundAd] {
    let ads = stretches.compactMap { stretch -> FoundAd? in
      guard stretch.start.isFinite, stretch.end.isFinite, stretch.end > stretch.start else {
        return nil
      }
      var kind = AdKind.ad
      if let name = stretch.kind {
        guard let known = AdKind(rawValue: name), known != .credits else { return nil }
        kind = known
      }
      let mark = stretch.from.flatMap { from in
        entry.ads.first { $0.kind == kind && abs($0.start - from) < 0.01 }
      }
      guard let mark else {
        return FoundAd(
          start: max(0, stretch.start), end: stretch.end, kind: kind, advertiser: "",
          confidence: .sure, firstWords: "", source: source)
      }
      return found(mark, start: max(0, stretch.start), end: stretch.end)
    }
    return AdJoin.join(ads, touching: 0)
  }

  /// `ads` without the ones that lie over a stretch of `gone` (what the map gave before and
  /// gives no more). An ad the map gave may have been joined with a neighbour or shortened since
  /// it was written (`AdJoin`), so it is known by where it lies and not by being equal.
  public static func without(_ gone: [FoundAd], from ads: [FoundAd]) -> [FoundAd] {
    ads.filter { ad in !gone.contains { $0.start < ad.end && ad.start < $0.end } }
  }

  /// `found` (what the words gave) with the map's ads: the map's ads skip, outside the stretches
  /// in `judged`. An ad the words found stays only where it overlaps none of the map's, since the
  /// map's borders are exact, and a question stays only outside every skip.
  public static func withMap(
    _ found: AheadFound, carried: [FoundAd], judged: [(start: Double, end: Double)] = []
  ) -> AheadFound {
    let exact = carried.filter { ad in !judged.contains { ad.start < $0.end && $0.start < ad.end } }
    func apart(_ ad: FoundAd, from others: [FoundAd]) -> Bool {
      !others.contains { $0.start < ad.end && ad.start < $0.end }
    }
    let skips = (exact + found.ads.filter { apart($0, from: exact) }).sorted { $0.start < $1.start }
    return AheadFound(ads: skips, asks: found.asks.filter { apart($0, from: skips) })
  }
}
