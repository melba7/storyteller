import XCTest

@testable import PodcastAds

final class AdKindSwitchTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, kind: AdKind) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func skipper(_ ads: [FoundAd], settings: AdSkipSettings = AdSkipSettings()) -> AdSkipper {
    let file = AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads, undone: [])
    return AdSkipper(file: file, settings: settings)
  }

  func testTheFourSwitchesAndTheirDefaults() {
    let settings = AdSkipSettings()
    XCTAssertTrue(settings.skipAds)
    XCTAssertTrue(settings.skipOwnPlugs)
    XCTAssertTrue(settings.skipPromos)
    XCTAssertFalse(settings.skipCredits)
    XCTAssertEqual(
      settings,
      AdSkipSettings(skipAds: true, skipOwnPlugs: true, skipPromos: true, skipCredits: false))
  }

  func testEachKindFollowsItsOwnSwitch() {
    let off = AdSkipSettings(
      skipAds: false, skipOwnPlugs: false, skipPromos: false, skipCredits: false)
    XCTAssertFalse(off.allows(.ad))
    XCTAssertFalse(off.allows(.ownPlug))
    XCTAssertFalse(off.allows(.promo))
    XCTAssertFalse(off.allows(.credits))
    XCTAssertTrue(AdSkipSettings(skipAds: true, skipOwnPlugs: false).allows(.ad))
    XCTAssertTrue(AdSkipSettings(skipAds: false, skipOwnPlugs: true).allows(.ownPlug))
    XCTAssertTrue(AdSkipSettings(skipPromos: true).allows(.promo))
    XCTAssertTrue(AdSkipSettings(skipCredits: true).allows(.credits))
    XCTAssertFalse(AdSkipSettings(skipAds: false).allows(.ad))
    XCTAssertFalse(AdSkipSettings(skipPromos: false).allows(.promo))
  }

  func testOverriddenKeepsPromosAndCredits() {
    let listener = AdSkipSettings(
      skipAds: true, skipOwnPlugs: true, skipPromos: false, skipCredits: true)
    let shown = listener.overridden(skipAds: false, skipOwnPlugs: false)
    XCTAssertEqual(
      shown,
      AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: false, skipCredits: true))
    XCTAssertEqual(listener.overridden(skipAds: nil, skipOwnPlugs: nil), listener)
  }

  func testPromosAreSkippedByDefaultAndCreditsAreNot() {
    let both = skipper([ad(100, 160, kind: .promo), ad(900, 960, kind: .credits)])
    XCTAssertEqual(both.ads.map(\.start), [100])
    let withCredits = skipper(
      [ad(900, 960, kind: .credits)], settings: AdSkipSettings(skipCredits: true))
    XCTAssertEqual(withCredits.ads.map(\.start), [900])
  }

  func testTurningPromosOffKeepsSponsorAdsSkipped() {
    let ads = [ad(100, 160, kind: .promo), ad(300, 360, kind: .ad)]
    let skipper = skipper(ads, settings: AdSkipSettings(skipPromos: false))
    XCTAssertEqual(skipper.ads.map(\.start), [300])
  }

  func testAChainNeverPullsInAKindThatIsSwitchedOff() {
    let ads = [ad(100, 160, kind: .ad), ad(160, 200, kind: .promo), ad(200, 240, kind: .credits)]
    var noPromos = skipper(ads, settings: AdSkipSettings(skipPromos: false))
    let first = noPromos.reached(position: 100, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(first?.chained, [])
    XCTAssertEqual(first?.target, 160)
    var everything = skipper(ads, settings: AdSkipSettings(skipCredits: true))
    let all = everything.reached(position: 100, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(all?.chained.map(\.kind), [.promo, .credits])
    var defaults = skipper(ads)
    let stops = defaults.reached(position: 100, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(stops?.chained.map(\.kind), [.promo])
    XCTAssertEqual(stops?.target, 200)
  }

  func testLabels() {
    XCTAssertEqual(AdKind.ad.label, "ad")
    XCTAssertEqual(AdKind.ownPlug.label, "own plug")
    XCTAssertEqual(AdKind.promo.label, "promo")
    XCTAssertEqual(AdKind.credits.label, "credits")
  }

  func testEveryKindRoundTripsThroughJSON() throws {
    let raw: [(AdKind, String)] = [
      (.ad, "ad"), (.ownPlug, "ownPlug"), (.promo, "promo"), (.credits, "credits"),
    ]
    for (kind, name) in raw {
      let data = try JSONEncoder().encode([kind])
      XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(name)\"]")
      XCTAssertEqual(try JSONDecoder().decode([AdKind].self, from: data), [kind])
    }
  }
}
