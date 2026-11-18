import XCTest

@testable import PodcastAds

final class AdTruthTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  func testTimesAreMinutesAndSecondsOrHours() {
    XCTAssertEqual(AdTruth.seconds("12:30"), 750)
    XCTAssertEqual(AdTruth.seconds("0:05"), 5)
    XCTAssertEqual(AdTruth.seconds("1:02:03"), 3723)
    XCTAssertEqual(AdTruth.seconds("12:30.5"), 750.5)
    XCTAssertEqual(AdTruth.seconds("75:00"), 4500)
    for bad in ["", "12", "12:", ":30", "12:60", "1:60:00", "a:30", "1:2:3:4", "12.5:30", "-1:30"] {
      XCTAssertNil(AdTruth.seconds(bad), bad)
    }
  }

  func testAFileOfMarkedAdsIsRead() throws {
    let text = """
      # Episode 12, marked by hand
      00:30 01:45

      12:30 - 13:45
      1:02:03 to 1:03:00
      """
    XCTAssertEqual(
      try AdTruth.parse(text),
      [
        TruthAd(start: 30, end: 105), TruthAd(start: 750, end: 825),
        TruthAd(start: 3723, end: 3780),
      ])
    XCTAssertEqual(try AdTruth.parse(""), [])
  }

  func testABadLineNamesItsNumber() {
    XCTAssertThrowsError(try AdTruth.parse("00:30 01:45\nsoon after\n")) {
      XCTAssertEqual($0 as? AdTruthError, .badLine(number: 2, text: "soon after"))
    }
    XCTAssertThrowsError(try AdTruth.parse("01:45 00:30"), "the end must come after the start")
    XCTAssertThrowsError(try AdTruth.parse("00:30 01:45 02:00"))
  }

  func testEachAdIsComparedWithTheMarkedAdItOverlapsMost() {
    let truth = [TruthAd(start: 100, end: 160), TruthAd(start: 500, end: 560)]
    let found = [ad(99.5, 163.5), ad(505, 556)]
    let result = AdTruth.compare(found: found, truth: truth)
    XCTAssertEqual(result.matches.count, 2)
    XCTAssertEqual(result.matches[0].startError, -0.5, accuracy: 0.001)
    XCTAssertEqual(result.matches[0].endError, 3.5, accuracy: 0.001)
    XCTAssertEqual(result.matches[1].startError, 5, accuracy: 0.001)
    XCTAssertEqual(result.matches[1].endError, -4, accuracy: 0.001)
    XCTAssertTrue(result.missed.isEmpty)
    XCTAssertTrue(result.falseAds.isEmpty)
    // Only an end after the real end is an overshoot: 3.5 and 0.
    XCTAssertEqual(result.meanOvershoot, 1.75, accuracy: 0.001)
    XCTAssertEqual(result.worstOvershoot, 3.5, accuracy: 0.001)
  }

  func testMissedAndFalseAdsAreCounted() {
    let truth = [TruthAd(start: 100, end: 160), TruthAd(start: 900, end: 960)]
    let found = [ad(98, 161), ad(400, 450)]
    let result = AdTruth.compare(found: found, truth: truth)
    XCTAssertEqual(result.missed, [TruthAd(start: 900, end: 960)])
    XCTAssertEqual(result.falseAds, [ad(400, 450)])
    XCTAssertEqual(result.matches.count, 1)
  }

  func testTheLargerOverlapIsTheMatch() {
    let truth = [TruthAd(start: 100, end: 160)]
    let found = [ad(95, 110), ad(112, 165)]
    let result = AdTruth.compare(found: found, truth: truth)
    XCTAssertEqual(result.matches.first?.found, ad(112, 165))
    XCTAssertTrue(result.falseAds.isEmpty, "a piece that overlaps a marked ad is not a false ad")
  }

  func testNothingMarkedAndNothingFoundIsAnEmptyComparison() {
    let result = AdTruth.compare(found: [], truth: [])
    XCTAssertTrue(result.matches.isEmpty)
    XCTAssertEqual(result.meanOvershoot, 0)
    XCTAssertEqual(result.worstOvershoot, 0)
  }

  func testTheMillisecondTimesOfATruthFileMadeFromTwoCopiesAreRead() throws {
    // `podcast-ads --truth-from-copies` writes times like these, with "#" notes above them.
    let text = """
      # Marked from two downloads of one episode.
      0:00.000 0:03.918
      12:34.500 12:59.250
      1:02:03.500 1:02:09.025
      """
    XCTAssertEqual(
      try AdTruth.parse(text),
      [
        TruthAd(start: 0, end: 3.918), TruthAd(start: 754.5, end: 779.25),
        TruthAd(start: 3723.5, end: 3729.025),
      ])
  }
}
