// LOFI-FORK: the switches as the app stores them (see FORK.md). Foundation only.
import Foundation

extension AdSkipSettings {
  /// The switches from what the app stored (nil where nothing was). The promo switch is newer
  /// than the others: older builds counted promos as ads, so while it was never stored, promos
  /// follow a stored Skip ads switch. With nothing stored, the defaults apply.
  public init(storedAds: Bool?, plugs: Bool?, promos: Bool?, credits: Bool?) {
    self.init(
      skipAds: storedAds ?? true, skipOwnPlugs: plugs ?? true,
      skipPromos: promos ?? storedAds ?? true, skipCredits: credits ?? false)
  }

  /// Whether a stretch of any sort is skipped under these switches.
  public var skipsAnySort: Bool { skipAds || skipOwnPlugs || skipPromos || skipCredits }
}
