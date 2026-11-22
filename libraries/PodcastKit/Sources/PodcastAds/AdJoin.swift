// LOFI-FORK: joins ads from several finders into one list (see FORK.md).
import Foundation

/// Joins the ads that several finders gave for one episode.
public enum AdJoin {
  /// The ads as one list in order of their start.
  public static func join(_ ads: [FoundAd], touching: Double = 0.5) -> [FoundAd] {
    AdHeadRules.merge(ads, touching: touching)
  }
}
