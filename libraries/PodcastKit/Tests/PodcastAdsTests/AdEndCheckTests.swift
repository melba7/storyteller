import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The ad-end check: a skip's end moves on while the next lines still sell. Made-up lines only.
final class AdEndCheckTests: XCTestCase {
  private func line(_ start: Double, _ text: String, end: Double? = nil) -> TranscriptLine {
    TranscriptLine(start: start, end: end ?? start + 4, text: text)
  }

  private func skip(
    _ start: Double, _ end: Double, _ kind: AdKind = .ad, source: String? = nil
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "x",
      source: source)
  }

  private func moved(_ lines: [TranscriptLine], _ skips: [FoundAd]) -> [[Double]] {
    AdEndCheck.stretches(lines: lines, skips: skips).map { [$0.start, $0.end] }
  }

  private let talk = "so the tomatoes grew well this year"
  private let code = "use code GARDEN at checkout"
  private let address = "that is at zorbex dot com"

  // MARK: The cues

  func testTheCuesAreAPromoCodeAWebAddressASlashAndTheTerms() {
    for text in [
      "Use code GARDEN today", "enter the promo code now", "with code garden", "code GARDEN at checkout",
      "code garden for a discount", "code garden to get more", "go to zorbex.com", "zorbex dot com",
      "Zorbex dot org", "quillmat.io", "dot com slash garden", "zorbex.com/garden", "Terms apply.",
      "terms and conditions apply", "restrictions apply", "see site for details", "that's qm dot com",
    ] {
      XCTAssertTrue(AdEndCheck.sells(text), text)
    }
    for text in [
      talk, "", "her code was hard to read", "we wrote code all night", "visit our friends",
      "ten percent off", "free shipping today", "the terms were clear", "a dot on the map",
    ] {
      XCTAssertFalse(AdEndCheck.sells(text), text)
    }
  }

  // MARK: Moving an end

  func testAnEndFollowedByAPromoCodeLineMovesToTheEndOfThatLine() {
    let found = AdEndCheck.stretches(
      lines: [line(120, "buy the zorbex thing"), line(131, code), line(136, talk), line(140, talk)],
      skips: [skip(100, 130, .promo)])
    XCTAssertEqual(found.map { [$0.start, $0.end] }, [[130, 136]])
    guard let first = found.first else { return }
    XCTAssertEqual(first.kind, .promo, "the kind of the skip it carries on")
    XCTAssertEqual(first.confidence, .unsure)
    XCTAssertEqual(first.source, "filled-holes")
    XCTAssertEqual(first.advertiser, "")
  }

  func testTheLineThatHoldsTheEndCountsToo() {
    // The line started before the end and is still spoken a second after it.
    XCTAssertEqual(moved([line(125, address), line(134, talk)], [skip(100, 130)]), [[130, 134]])
  }

  func testOneLineWithoutACueIsBridgedBetweenTwoCueLines() {
    let lines = [line(131, code), line(135, talk), line(139, address), line(143, talk), line(147, talk)]
    XCTAssertEqual(moved(lines, [skip(100, 130)]), [[130, 143]])
    // The first line after the end may be the one without a cue.
    XCTAssertEqual(moved([line(131, talk), line(135, code), line(139, talk)], [skip(100, 130)]), [[130, 139]])
  }

  func testTwoLinesWithoutACueStopIt() {
    let lines = [line(131, code), line(135, talk), line(139, talk), line(143, address), line(147, talk)]
    XCTAssertEqual(moved(lines, [skip(100, 130)]), [[130, 135]])
    XCTAssertTrue(moved([line(131, talk), line(135, talk), line(139, code)], [skip(100, 130)]).isEmpty)
  }

  func testWithNoCueNothingChanges() {
    XCTAssertTrue(moved([line(120, code), line(131, talk), line(135, talk)], [skip(100, 130)]).isEmpty)
    XCTAssertTrue(moved([line(131, talk)], [skip(100, 130)]).isEmpty)
  }

  // MARK: The limits

  func testTheEndMovesAtMostFifteenSeconds() {
    XCTAssertEqual(AdEndCheck.reach, 15)
    // Only lines that start within 15 s after the end are read.
    let lines = [line(131, code), line(136, code), line(141, code), line(146, code), line(151, talk)]
    XCTAssertEqual(moved(lines, [skip(100, 130)]), [[130, 145]])
    XCTAssertEqual(moved([line(144.9, code), line(148, talk)], [skip(100, 130)]), [[130, 145]])
    XCTAssertTrue(moved([line(145, code), line(148, talk)], [skip(100, 130)]).isEmpty)
    // A cue line that runs long is cut at 15 s too.
    XCTAssertEqual(moved([line(131, code), line(170, talk)], [skip(100, 130)]), [[130, 145]])
  }

  func testItNeverGoesIntoTheNextSkip() {
    let lines = [line(131, code), line(136, address), line(141, code), line(146, talk), line(161, talk)]
    XCTAssertEqual(moved(lines, [skip(100, 130), skip(134, 160)]), [[130, 134]])
    // Skips that touch or overlap are one stretch: only its last end moves.
    let after = [line(161, code), line(166, talk), line(170, talk)]
    XCTAssertEqual(moved(after, [skip(100, 130), skip(130, 160)]), [[160, 166]])
    XCTAssertEqual(moved(after, [skip(100, 160), skip(120, 140)]), [[160, 166]])
  }

  func testItNeverGoesPastTheEndOfTheTranscript() {
    XCTAssertEqual(moved([line(100, talk), line(131, code, end: 137.5)], [skip(100, 130)]), [[130, 137.5]])
    // A skip that ends where the transcript ends stays.
    XCTAssertTrue(moved([line(100, talk), line(125, code, end: 130)], [skip(100, 130)]).isEmpty)
    XCTAssertTrue(moved([line(100, talk), line(125, code, end: 130)], [skip(100, 140)]).isEmpty)
  }

  // MARK: Whose skips

  func testAMarkOfTheMacIsNotMoved() {
    let lines = [line(131, code), line(136, talk), line(140, talk), line(231, code), line(236, talk)]
    XCTAssertTrue(moved(lines, [skip(100, 130, source: ShowTuning.ahead)]).isEmpty)
    XCTAssertEqual(
      moved(lines, [skip(100, 130, source: ShowTuning.ahead), skip(200, 230, source: "meaning")]),
      [[230, 236]])
    // Where a mark and a skip of the phone end together, the mark decides.
    XCTAssertTrue(moved(lines, [skip(100, 130, source: ShowTuning.ahead), skip(110, 130)]).isEmpty)
    XCTAssertEqual(moved(lines, [skip(100, 120, source: ShowTuning.ahead), skip(110, 130)]), [[130, 136]])
  }

  func testLinesInAnyOrderAndBadInput() {
    let lines = [line(139, address), line(131, code), line(143, talk), line(135, talk), line(147, talk)]
    XCTAssertEqual(moved(lines, [skip(100, 130)]), [[130, 143]])
    XCTAssertEqual(moved(lines + [line(.nan, code)], [skip(.nan, 200), skip(100, 130)]), [[130, 143]])
    XCTAssertTrue(moved([], [skip(100, 130)]).isEmpty)
    XCTAssertTrue(moved(lines, []).isEmpty)
    XCTAssertTrue(moved(lines, [skip(130, 100), skip(100, .infinity)]).isEmpty)
  }
}
