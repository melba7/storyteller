import XCTest

@testable import PodcastAds

final class AdSpotCueTests: XCTestCase {
  /// Lines of ten seconds each, numbered from 1, from plain texts.
  private func lines(_ texts: [String]) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(
        number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9,
        text: $0.element)
    }
  }

  // MARK: The quick rules for a stream's head

  func testTwoClosingPhrasesOfASpotAreAnAdThatTheRulesAreUnsureOf() {
    let head = lines(["Download the Quokka app today", "Terms and conditions apply"])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [2])
    XCTAssertEqual(found.map(\.confidence), [.unsure], "two phrases and no address or offer")
  }

  func testOneClosingPhraseAloneIsNotAnAd() {
    XCTAssertEqual(AdHeadRules.find(lines: lines(["Download the Quokka app today"])), [])
    XCTAssertEqual(AdHeadRules.find(lines: lines(["Terms and conditions apply"])), [])
    let far = lines([
      "Download the Quokka app today", "Plain talk one.", "Plain talk two.",
      "Terms and conditions apply",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: far), [])
  }

  func testAClosingPhraseWithAWebAddressNearbyIsASureAd() {
    let head = lines([
      "Welcome to the show.", "Download the Quokka app today.", "Find out more at quokka.com.",
      "Now back to the story.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [2])
    XCTAssertEqual(found.map(\.endLine), [3])
    XCTAssertEqual(found.map(\.confidence), [.sure])
  }

  func testAClosingPhraseIsTheSecondSignalOfAnOfferLine() {
    let head = lines([
      "Welcome to the show.", "That is twenty percent off the usual price.",
      "Their formula is great.", "Available now wherever you get your podcasts.",
    ])
    // The offer line is a sure ad; the closing phrase two lines on is an unsure ad of its own.
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [2, 4])
    XCTAssertEqual(found.map(\.confidence), [.sure, .unsure])
    let alone = lines([
      "We got it for a good price.", "That is twenty percent off the usual price.",
      "Their formula is great.", "They also make a second one.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: alone), [])
  }

  // MARK: The end of a produced spot

  private func texts(line5: String, line6: String) -> [String] {
    var texts = talk(30)
    texts[3] = "go to acme dot com today"
    texts[4] = line5
    texts[5] = line6
    return texts
  }

  func testALineAfterALineThatEndsWithTermsIsNotCarriedWithoutAHardSignal() throws {
    let transcript = makeTranscript(
      texts(line5: "Offer valid in select states, restrictions apply.", line6: "Thanks again to Quokka"))
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  func testTheSameLineIsCarriedWhenTheAdDoesNotEndWithTerms() throws {
    let transcript = makeTranscript(
      texts(line5: "Quokka is the best mattress", line6: "Thanks again to Quokka"))
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: transcript).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testAnAddressAfterATermsLineIsStillCarried() throws {
    let transcript = makeTranscript(
      texts(line5: "Terms and conditions apply.", line6: "that is acme dot com slash show"))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }
}
