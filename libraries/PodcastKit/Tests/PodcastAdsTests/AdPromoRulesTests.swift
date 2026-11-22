import XCTest

@testable import PodcastAds

final class AdPromoRulesTests: XCTestCase {
  /// Lines of ten seconds each, numbered from 1, from plain texts.
  private func lines(_ texts: [String]) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9, text: $0.element)
    }
  }

  func testALiveShowPromoOverThreeLinesIsOneSurePromo() {
    let found = AdPromoRules.find(
      lines: lines([
        "That was a great week of news.",
        "We are going on tour this fall.",
        "Come see us live in Chicago on October 3rd.",
        "Tickets are on sale now at example.com slash live.",
        "Anyway, the budget vote.",
        "The council met on Tuesday.",
      ]))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.startLine, 2)
    XCTAssertEqual(found.first?.endLine, 4)
    XCTAssertEqual(found.first?.confidence, .sure)
    XCTAssertEqual(found.first?.kind, .promo)
  }

  func testASubscriptionPitchIsFound() {
    let found = AdPromoRules.find(
      lines: lines([
        "If you like the show, become a subscriber.",
        "Subscribers get bonus episodes and an ad-free feed.",
        "Go to example.com slash join.",
      ]))
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [3])
    XCTAssertEqual(found.first?.confidence, .sure)
  }

  func testAnotherShowsTrailerIsFound() {
    let found = AdPromoRules.find(
      lines: lines([
        "Here's a preview of a new podcast from the team behind this show.",
        "It follows a small town for a year.",
        "Search for River Stories wherever you get your podcasts.",
      ]))
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [3])
  }

  func testOneCueLineAloneInAnInterviewIsNotAPromo() {
    let found = AdPromoRules.find(
      lines: lines([
        "How did you start out?",
        "The band went on tour in 1975 and never came back.",
        "That must have been hard.",
      ]))
    XCTAssertEqual(found, [])
  }

  func testACueWithOnlyACallNearbyIsUnsureWithoutAWebAddress() {
    let found = AdPromoRules.find(
      lines: lines([
        "Come see us live next month.",
        "Learn more on our site.",
      ]))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.confidence, .unsure)
  }

  func testACueWithACallAndAWebAddressIsSure() {
    let found = AdPromoRules.find(
      lines: lines([
        "Come see us live next month.",
        "Learn more at example.com slash live.",
      ]))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.confidence, .sure)
  }

  func testTheSpanStopsBeforeAReturnCueAndLeavesLaterLinesOut() {
    let found = AdPromoRules.find(
      lines: lines([
        "We are going on tour this fall.",
        "Come see us live in Chicago.",
        "Tickets are on sale now at example.com slash live.",
        "And we're back.",
        "Welcome back to the show.",
        "Now, the budget vote.",
      ]))
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [3])
  }

  func testASpanNeverStartsOnAReturnCueLine() {
    let found = AdPromoRules.find(
      lines: lines([
        "Welcome back to the show, we are going on tour.",
        "Plain talk goes on here.",
        "Plain talk goes on and on.",
        "Plain talk again.",
      ]))
    XCTAssertEqual(found, [])
  }

  func testTwoSpansFarApartStayTwoRanges() {
    let plain = ["Plain talk one.", "Plain talk two.", "Plain talk three.", "Plain talk four."]
    let found = AdPromoRules.find(
      lines: lines(
        ["Come see us live.", "Tickets are on sale now."] + plain
          + ["Become a subscriber.", "Subscribers get bonus episodes."]))
    XCTAssertEqual(found.map(\.startLine), [1, 7])
    XCTAssertEqual(found.map(\.endLine), [2, 8])
  }

  func testTouchingSpansJoin() {
    let found = AdPromoRules.find(
      lines: lines([
        "Come see us live.",
        "Tickets are on sale now.",
        "Become a subscriber.",
        "Subscribers get bonus episodes.",
      ]))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.startLine, 1)
    XCTAssertEqual(found.first?.endLine, 4)
    XCTAssertEqual(found.first?.confidence, .sure)  // two cue groups
  }

  func testNoLinesGiveNoRangesAndEveryRangeIsAPromoWithNoAdvertiser() {
    XCTAssertEqual(AdPromoRules.find(lines: []), [])
    let found = AdPromoRules.find(
      lines: lines(["Come see us live.", "Tickets are on sale now at example.com slash live."]))
    XCTAssertFalse(found.isEmpty)
    XCTAssertTrue(found.allSatisfy { $0.kind == .promo && $0.advertiser.isEmpty })
  }

  func testAPlainSponsorReadIsNotAPromo() {
    let found = AdPromoRules.find(
      lines: lines([
        "This episode is brought to you by Example Mattress.",
        "Go to example.com slash show and use code SHOW.",
      ]))
    XCTAssertEqual(found, [])
  }
}
