import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The playbook's pull (`CueAds.playbook`), on made-up transcripts.
final class CueAdsPlaybookTests: XCTestCase {
  private let show = "https://one.test/rss"
  private let cues = AdCues(
    data: Data(
      """
      {"version": 1, "starts": [], "returns": [],
       "shows": [{"feed": "https://one.test/rss", "phrases": ["a word from", "mail bag time"]},
                 {"feed": "https://other.test/rss", "phrases": ["other show phrase"]}],
       "common": [], "usual": []}
      """.utf8))

  private func line(_ start: Double, _ text: String) -> TranscriptLine {
    TranscriptLine(start: start, end: start + 5, text: text)
  }

  private func skip(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    FoundAd(start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func pulled(_ lines: [TranscriptLine], _ skips: [FoundAd], show: String? = nil) -> [FoundAd] {
    CueAds.playbook(lines: lines, skips: skips, cues: cues, show: show ?? self.show)
  }

  private func spans(_ found: [FoundAd]) -> [[Double]] { found.map { [$0.start, $0.end] } }

  func testAPhraseLineBeforeASkipPullsItsStartBack() {
    let found = pulled(
      [line(50, "talk talk"), line(100, "And now, a word from our friends"), line(120, "they are nice"),
       line(150, "buy things")],
      [skip(150, 200, .promo), skip(400, 450)])
    XCTAssertEqual(spans(found), [[100, 150]])
    guard let first = found.first else { return }
    XCTAssertEqual(first.kind, .promo, "the kind of the stretch it is pulled to")
    XCTAssertEqual(first.confidence, .unsure)
    XCTAssertEqual(first.source, "opening-lines")
    XCTAssertEqual(first.advertiser, "")
    XCTAssertEqual(first.firstWords, "and now a word from our friends")
  }

  func testTheLineIsFromSixtySecondsToHalfASecondBeforeTheSkip() {
    let text = "a word from them"
    XCTAssertEqual(spans(pulled([line(100, text)], [skip(160, 200)])), [[100, 160]])
    XCTAssertTrue(pulled([line(100, text)], [skip(160.5, 200)]).isEmpty, "over a minute before")
    XCTAssertTrue(pulled([line(100, text)], [skip(100.5, 200)]).isEmpty, "half a second is too near")
    XCTAssertEqual(spans(pulled([line(100, text)], [skip(100.6, 200)])), [[100, 100.6]])
    XCTAssertTrue(pulled([line(100, text)], [skip(100, 200)]).isEmpty, "the line starts the skip")
    XCTAssertTrue(pulled([line(210, text)], [skip(150, 200)]).isEmpty, "a line after the skip")
  }

  func testTheLatestPhraseLineInReachIsTheOne() {
    let found = pulled(
      [line(100, "a word from one"), line(120, "it is mail bag time"), line(130, "plain talk")],
      [skip(150, 200)])
    XCTAssertEqual(spans(found), [[120, 150]])
    XCTAssertEqual(found.first?.firstWords, "it is mail bag time")
  }

  func testOnlyThisShowsPhrasesAsWholeWordsCount() {
    XCTAssertTrue(pulled([line(100, "other show phrase")], [skip(150, 200)]).isEmpty)
    XCTAssertEqual(pulled([line(100, "other show phrase")], [skip(150, 200)], show: "https://other.test/rss").count, 1)
    XCTAssertTrue(pulled([line(100, "a wordy from them")], [skip(150, 200)]).isEmpty)
    XCTAssertTrue(pulled([line(100, "a word from them")], [skip(150, 200)], show: "nobody").isEmpty)
  }

  func testWhatIsAddedIsOnlyThePartNoSkipCovers() {
    // The phrase line lies inside the skip before: only the gap between the two is added.
    let inside = pulled([line(110, "a word from them"), line(125, "gap talk")], [skip(100, 120), skip(140, 200, .promo)])
    XCTAssertEqual(spans(inside), [[120, 140]])
    XCTAssertEqual(inside.first?.kind, .promo)
    XCTAssertEqual(inside.first?.firstWords, "gap talk", "the first line that starts in the piece")
    // The pull reaches over a short skip: a piece before it (of its kind) and one after it.
    let over = pulled([line(100, "a word from them")], [skip(110, 120, .credits), skip(140, 200, .promo)])
    XCTAssertEqual(spans(over), [[100, 110], [120, 140]])
    XCTAssertEqual(over.map(\.kind), [.credits, .promo])
    XCTAssertEqual(over.map(\.firstWords), ["a word from them", ""])
  }

  func testEachStretchIsPulledOnItsOwnAndSkipsAreJoinedFirst() {
    let lines = [line(100, "a word from one"), line(300, "mail bag time again")]
    XCTAssertEqual(spans(pulled(lines, [skip(350, 400), skip(150, 200)])), [[100, 150], [300, 350]])
    // Two skips that overlap are one stretch; the line inside it pulls nothing.
    XCTAssertTrue(pulled([line(160, "a word from one")], [skip(150, 170), skip(165, 200)]).isEmpty)
    // Lines in any order give the same answer.
    XCTAssertEqual(spans(pulled(lines.reversed(), [skip(150, 200), skip(350, 400)])), [[100, 150], [300, 350]])
  }

  func testNoPhrasesNoSkipsOrBadInputAddNothing() {
    let lines = [line(100, "a word from them")]
    XCTAssertTrue(pulled(lines, []).isEmpty)
    XCTAssertTrue(CueAds.playbook(lines: lines, skips: [skip(150, 200)], cues: AdCues(), show: show).isEmpty)
    XCTAssertTrue(pulled([line(.nan, "a word from them")], [skip(150, 200)]).isEmpty)
    XCTAssertTrue(pulled(lines, [skip(.nan, 200), skip(150, .infinity), skip(200, 150)]).isEmpty)
    XCTAssertTrue(pulled([], [skip(150, 200)]).isEmpty)
  }
}
