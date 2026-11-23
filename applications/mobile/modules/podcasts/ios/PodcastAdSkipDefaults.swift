// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Where the player keeps the listener's four ad switches (moved here from PodcastPlayer+Ads.swift
// unchanged, to keep that file short).

import Foundation
import PodcastAds

/// The listener's four switches, kept in the app's defaults so the player reads them with no
/// JavaScript running.
enum AdSkipDefaults {
  private static let adsKey = "podcasts.ads.skipAds"
  private static let plugsKey = "podcasts.ads.skipOwnPlugs"
  private static let promosKey = "podcasts.ads.skipPromos"
  private static let creditsKey = "podcasts.ads.skipCredits"

  /// Ads, the hosts' plugs and promos are on until the listener turns them off; credits are off
  /// until they turn them on. Promos were counted as ads in older builds, so while the promo
  /// switch was never stored it follows the stored Skip ads switch.
  static var settings: AdSkipSettings {
    get {
      let defaults = UserDefaults.standard
      return AdSkipSettings(
        storedAds: defaults.object(forKey: adsKey) as? Bool,
        plugs: defaults.object(forKey: plugsKey) as? Bool,
        promos: defaults.object(forKey: promosKey) as? Bool,
        credits: defaults.object(forKey: creditsKey) as? Bool)
    }
    set {
      UserDefaults.standard.set(newValue.skipAds, forKey: adsKey)
      UserDefaults.standard.set(newValue.skipOwnPlugs, forKey: plugsKey)
      UserDefaults.standard.set(newValue.skipPromos, forKey: promosKey)
      UserDefaults.standard.set(newValue.skipCredits, forKey: creditsKey)
    }
  }
}
