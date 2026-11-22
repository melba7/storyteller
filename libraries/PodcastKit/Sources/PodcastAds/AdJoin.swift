// LOFI-FORK: joins ads from several finders into one list (see FORK.md).
import Foundation

/// Joins the ads that several finders gave for one episode.
public enum AdJoin {
  /// Which kind wins where two overlap: ad, then promo, then own plug, then credits.
  static func rank(_ kind: AdKind) -> Int {
    switch kind {
    case .ad: return 0
    case .promo: return 1
    case .ownPlug: return 2
    case .credits: return 3
    }
  }

  /// The ads as one list in order of their start, with no two overlapping. Ads of one kind that
  /// overlap or lie within `touching` seconds of each other become one. Ads of different kinds are
  /// never joined: where they overlap, the higher-ranking kind keeps its whole stretch and the
  /// other is cut back to what lies outside it (a left-over part shorter than
  /// `AdRules.minLength` is dropped).
  public static func join(_ ads: [FoundAd], touching: Double = 0.5) -> [FoundAd] {
    let kinds = Set(ads.map(\.kind)).sorted { rank($0) < rank($1) }
    var higher: [FoundAd] = []  // the whole stretches of the kinds ranked above
    var result: [FoundAd] = []
    for kind in kinds {
      let one = union(ads.filter { $0.kind == kind }, touching: touching)
      for ad in one { result += cut(ad, around: higher) }
      higher += one
    }
    return result.sorted { $0.start < $1.start }
  }

  /// Ads of one kind joined where they overlap or touch.
  private static func union(_ ads: [FoundAd], touching: Double) -> [FoundAd] {
    var result: [FoundAd] = []
    for ad in ads.sorted(by: { $0.start < $1.start }) {
      guard var last = result.popLast() else {
        result.append(ad)
        continue
      }
      if ad.start <= last.end + touching {
        let longer = ad.duration > last.duration ? ad : last
        let other = ad.duration > last.duration ? last : ad
        last.advertiser = longer.advertiser.isEmpty ? other.advertiser : longer.advertiser
        last.confidence = max(last.confidence, ad.confidence)
        last.end = max(last.end, ad.end)
        result.append(last)
      } else {
        result.append(last)
        result.append(ad)
      }
    }
    return result
  }

  /// What is left of `ad` outside the `covering` stretches. An ad nothing covers is returned as
  /// it is; the parts of one that was cut are dropped when shorter than `AdRules.minLength`.
  private static func cut(_ ad: FoundAd, around covering: [FoundAd]) -> [FoundAd] {
    let over = covering.filter { $0.start < ad.end && ad.start < $0.end }
      .sorted { $0.start < $1.start }
    guard !over.isEmpty else { return [ad] }
    var parts: [FoundAd] = []
    var from = ad.start
    for hole in over {
      if hole.start > from { parts.append(piece(of: ad, from, hole.start)) }
      from = max(from, hole.end)
    }
    if from < ad.end { parts.append(piece(of: ad, from, ad.end)) }
    return parts.filter { $0.duration >= AdRules.minLength }
  }

  private static func piece(of ad: FoundAd, _ start: Double, _ end: Double) -> FoundAd {
    var part = ad
    part.start = start
    part.end = end
    return part
  }
}
