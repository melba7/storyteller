import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdEdgeReportTests: XCTestCase {
  func testTheShareOfWordGapsAndTouchingWordsIsCounted() {
    // Four words: a gap of 0.5 s, one of 0, one of 0.1.
    let words = [
      TranscriptWord(text: "a", start: 0, end: 1), TranscriptWord(text: "b", start: 1.5, end: 2),
      TranscriptWord(text: "c", start: 2, end: 3), TranscriptWord(text: "d", start: 3.1, end: 4),
    ]
    var transcript = makeTranscript(["a b", "c d"])
    transcript.words = words
    let stats = AdEdgeReport.stats(of: transcript)
    XCTAssertEqual(stats.words, 4)
    XCTAssertEqual(stats.gapShare, 1.0 / 3, accuracy: 0.001)
    XCTAssertEqual(stats.touchingShare, 1.0 / 3, accuracy: 0.001)
    XCTAssertEqual(stats.wordsPerLine, 2)
    XCTAssertEqual(stats.secondsPerLine, 9)
  }

  func testWordsThatRunOnAreSaidToHideThePauses() {
    let words = (0..<20).map { TranscriptWord(text: "w", start: Double($0), end: Double($0 + 1)) }
    var transcript = makeTranscript(["a"])
    transcript.words = words
    let text = AdEdgeReport.lines(for: AdEdgeReport.stats(of: transcript)).joined(separator: "\n")
    XCTAssertTrue(text.contains("100.0 %"), text)
    XCTAssertTrue(text.contains("hide the pauses"), text)
  }

  func testATranscriptWithoutWordsSaysSo() {
    let stats = AdEdgeReport.stats(of: makeTranscript([]))
    XCTAssertEqual(stats.words, 0)
    XCTAssertEqual(stats.gapShare, 0)
    XCTAssertEqual(
      AdEdgeReport.lines(for: stats), ["The transcript has too few words to say anything."])
  }

  func testTheClockHasHoursMinutesSecondsAndTenths() {
    XCTAssertEqual(AdEdgeReport.clock(79.8), "00:01:19.8")
    XCTAssertEqual(AdEdgeReport.clock(3723.04), "01:02:03.0")
    XCTAssertEqual(AdEdgeReport.clock(-5), "00:00:00.0")
  }

  func testATraceNamesTheLinesAndWhatEachStepDidToTheEnd() throws {
    var texts = talk(30)
    texts[5] = "go to acme dot com"
    let transcript = makeTranscript(texts)
    let trace = try XCTUnwrap(
      AdCleanup.explain(ranges: [range(3, 5)], transcript: transcript).first)
    let text = AdEdgeReport.lines(for: trace, number: 1, transcript: transcript)
      .joined(separator: "\n")
    XCTAssertTrue(text.contains("Ad 1: 00:00:19.8 to 00:00:59.8 (40 s), ad, sure, Acme"), text)
    XCTAssertTrue(text.contains("The model said lines 3 to 5 (00:00:20.0 to 00:00:49.0)"), text)
    XCTAssertTrue(text.contains("Carried onto the end: [6] \"go to acme dot com\""), text)
    XCTAssertTrue(text.contains("Trimmed off the end, the show being back: none"), text)
    XCTAssertTrue(
      text.contains("The end moved +10.0 s by trimming or carrying and +0.8 s by landing"), text)
    XCTAssertTrue(text.contains("The start moved -0.2 s by landing"), text)
    XCTAssertTrue(text.contains("---- end 00:00:59.8 ----"), text)
    XCTAssertTrue(text.contains("[7] 00:01:00.0 to 00:01:09.0  plain talk number 7 here"), text)
  }

  func testTheComparisonWithMarkedAdsSaysWhichWayEachEdgeIsOff() {
    let found = FoundAd(
      start: 99, end: 164, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
    let result = AdTruth.compare(
      found: [found], truth: [TruthAd(start: 100, end: 160), TruthAd(start: 900, end: 960)])
    let text = AdEdgeReport.lines(for: result).joined(separator: "\n")
    XCTAssertTrue(text.contains("start 1.0 s early (some of the show is skipped)"), text)
    XCTAssertTrue(text.contains("end 4.0 s late (some of the show is skipped)"), text)
    XCTAssertTrue(text.contains("mean 4.0 s, worst 4.0 s"), text)
    XCTAssertTrue(text.contains("Missed ads: 1 [00:15:00.0 to 00:16:00.0]"), text)
    XCTAssertTrue(text.contains("False ads: 0"), text)
  }
}
