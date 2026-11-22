import XCTest

@testable import PodcastAds

/// The switches as the app keeps them, and what an older build left behind.
final class AdSkipStoredTests: XCTestCase {
  func testNothingStoredGivesTheDefaults() {
    XCTAssertEqual(
      AdSkipSettings(storedAds: nil, plugs: nil, promos: nil, credits: nil), AdSkipSettings())
  }

  func testPromosFollowAStoredSkipAdsWhenTheyWereNeverStored() {
    // An older build counted promos as ads, so its Skip ads switch said what to do with them.
    let off = AdSkipSettings(storedAds: false, plugs: nil, promos: nil, credits: nil)
    XCTAssertFalse(off.skipPromos)
    XCTAssertTrue(off.skipOwnPlugs)
    let on = AdSkipSettings(storedAds: true, plugs: nil, promos: nil, credits: nil)
    XCTAssertTrue(on.skipPromos)
  }

  func testAStoredPromoSwitchWins() {
    let settings = AdSkipSettings(storedAds: false, plugs: false, promos: true, credits: true)
    XCTAssertEqual(
      settings,
      AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: true, skipCredits: true))
  }

  func testAnySortIsSkippedWhenOneSwitchIsOn() {
    XCTAssertTrue(AdSkipSettings().skipsAnySort)
    XCTAssertTrue(
      AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: false, skipCredits: true)
        .skipsAnySort)
    XCTAssertTrue(
      AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: true).skipsAnySort)
    XCTAssertFalse(
      AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: false, skipCredits: false)
        .skipsAnySort)
  }
}
