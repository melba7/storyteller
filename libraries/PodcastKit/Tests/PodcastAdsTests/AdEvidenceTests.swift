import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdEvidenceTests: XCTestCase {
  /// Plain talk of `count` lines with some lines (counted from 1) replaced.
  private func texts(_ count: Int, _ replaced: [Int: String] = [:]) -> [String] {
    var texts = talk(count)
    for (line, text) in replaced { texts[line - 1] = text }
    return texts
  }

  private func run(_ ranges: [AdRange], _ texts: [String]) -> [FoundAd] {
    AdCleanup.run(ranges: ranges, transcript: makeTranscript(texts))
  }

  func testALineIsEvidenceWhenItHoldsASignalACueOrTheAdvertisersName() {
    XCTAssertTrue(AdEvidence.isEvidence("go to acme dot com", advertiser: ""))
    XCTAssertTrue(AdEvidence.isEvidence("use code SHOW today", advertiser: ""))
    XCTAssertTrue(AdEvidence.isEvidence("thanks again to our friends", advertiser: ""))
    XCTAssertTrue(AdEvidence.isEvidence("we love Quokka", advertiser: "Quokka"))
    XCTAssertTrue(AdEvidence.isEvidence("Terms and conditions apply", advertiser: ""))
    XCTAssertTrue(AdEvidence.isEvidence("Download the Quokka app today", advertiser: ""))
    XCTAssertFalse(AdEvidence.isEvidence("we love Quokka", advertiser: ""))
    XCTAssertFalse(AdEvidence.isEvidence("we love Quokka", advertiser: "sponsor"))
    XCTAssertFalse(AdEvidence.isEvidence("plain talk number 3 here", advertiser: "Acme"))
  }

  func testTheEvidenceOfAStretchIsTheNumberOfLinesThatHaveSome() {
    let lines = makeTranscript(["go to acme.com", "plain", "Quokka is great", "visit us", "plain"]).lines
    XCTAssertEqual(AdEvidence.count(lines: lines, advertiser: "Quokka"), 3)
    XCTAssertEqual(AdEvidence.count(lines: lines[1...1], advertiser: "Quokka"), 0)
  }

  // MARK: One ad

  func testASureAdOverPlainTalkWithNoNameIsOnlyUnsure() {
    let ads = run([range(3, 5, advertiser: "")], talk(30))
    XCTAssertEqual(ads.map(\.confidence), [.unsure])
  }

  func testAWebAddressInTheAdKeepsItSure() {
    let ads = run([range(3, 5, advertiser: "")], texts(30, [4: "go to acme.com today"]))
    XCTAssertEqual(ads.map(\.confidence), [.sure])
  }

  func testAClosingPhraseOfAProducedSpotKeepsItSure() {
    let closer = "Offer valid in select states, restrictions apply."
    let ads = run([range(3, 5, advertiser: "")], texts(30, [5: closer]))
    XCTAssertEqual(ads.map(\.confidence), [.sure])
  }

  func testTheAdvertisersNameInTheAdKeepsItSure() {
    let ads = run([range(3, 5, advertiser: "Quokka")], texts(30, [4: "Quokka is the best"]))
    XCTAssertEqual(ads.map(\.confidence), [.sure])
  }

  func testAnAdThatTheModelIsUnsureOfStaysUnsure() {
    let ads = run([range(3, 5, .unsure)], texts(30, [4: "go to acme.com today"]))
    XCTAssertEqual(ads.map(\.confidence), [.unsure])
  }

  func testAnAdWithNoEvidenceIsNeverCarriedOn() throws {
    // The model is sure, but nothing in its lines sells; the line after it has an address.
    let ads = run([range(3, 5, advertiser: "")], texts(30, [6: "that is acme dot com slash show"]))
    XCTAssertEqual(try XCTUnwrap(ads.first).end, 49.75, accuracy: 0.01)
    let proved = run(
      [range(3, 5, advertiser: "")],
      texts(30, [4: "go to acme.com today", 6: "that is acme dot com slash show"]))
    XCTAssertEqual(try XCTUnwrap(proved.first).end, 59.75, accuracy: 0.01)
  }

  func testAnAdWithNoEvidenceIsNeverMergedWithANeighbour() {
    // Both are sure, with a filler line between them; the second has nothing that sells.
    let breakLine = "We'll be right back after one more word from our sponsor"
    let both = texts(30, [4: "go to acme.com today", 6: breakLine])
    XCTAssertEqual(run([range(3, 5), range(7, 9)], both).map(\.confidence), [.sure, .unsure])
    let proved = texts(30, [4: "go to acme.com today", 6: breakLine, 8: "go to zebra.com today"])
    XCTAssertEqual(run([range(3, 5), range(7, 9)], proved).count, 1)
  }

  // MARK: Too much of the episode

  /// Three ads of four lines in 30 lines (about 39% of the episode); the first has two lines that
  /// sell, the second one, the third none.
  private var crowded: [String] {
    texts(
      30, [
        4: "go to acme.com today", 5: "use code SHOW at checkout", 12: "go to zebra.com today",
      ])
  }

  func testWhenAdsCoverOverAThirdOfTheEpisodeEachAdWithUnderTwoSignalsIsUnsure() {
    let ads = run([range(3, 6), range(11, 14), range(21, 24)], crowded)
    XCTAssertEqual(ads.map(\.confidence), [.sure, .unsure, .unsure])
  }

  func testUnderAThirdOfTheEpisodeOneSignalIsEnough() {
    let ads = run([range(3, 6), range(11, 14)], crowded)
    XCTAssertEqual(ads.map(\.confidence), [.sure, .sure])
  }

  func testOneAdOverThreeMinutesNeedsTwoSignalsButItsNeighboursDoNot() {
    // Lines 3 to 21 are a 189 s ad in an episode of 1,000 s: well under a third of it.
    var replaced = [4: "go to acme.com today", 42: "go to zebra.com today"]
    let one = run([range(3, 21), range(41, 43)], texts(100, replaced))
    XCTAssertEqual(one.map(\.confidence), [.unsure, .sure])
    replaced[10] = "use code SHOW at checkout"
    let two = run([range(3, 21), range(41, 43)], texts(100, replaced))
    XCTAssertEqual(two.map(\.confidence), [.sure, .sure])
  }

  func testAShortTranscriptIsNotJudgedByTheShareOfItsAds() {
    // A stream's head: 100 s of audio with a 39 s ad in it.
    let head = run([range(3, 6)], texts(10, [4: "go to acme.com today"]))
    XCTAssertEqual(head.map(\.confidence), [.sure])
  }
}
