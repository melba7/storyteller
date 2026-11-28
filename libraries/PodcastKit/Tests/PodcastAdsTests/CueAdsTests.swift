import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The two finders that use the Mac's cues, on made-up transcripts.
final class CueAdsTests: XCTestCase {
  private let show = "https://one.test/rss"
  private let cues = AdCues(
    data: Data(
      """
      {"version": 1, "starts": ["now a word"], "returns": ["and we are"],
       "shows": [{"feed": "https://one.test/rss", "starts": ["quick message from"], "returns": []}],
       "common": ["about", "with", "that", "show"], "usual": ["today"]}
      """.utf8))

  private func line(_ start: Double, _ text: String) -> TranscriptLine {
    TranscriptLine(start: start, end: start + 5, text: text)
  }

  private func skip(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    FoundAd(start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func opened(_ lines: [TranscriptLine], _ skips: [FoundAd], show: String? = nil) -> [FoundAd] {
    CueAds.openings(lines: lines, skips: skips, cues: cues, show: show ?? self.show)
  }

  // MARK: Opening lines

  func testAnOpeningLinePullsTheNearestLaterSkipBackToIt() {
    let found = opened(
      [line(50, "talk talk"), line(100, "Now, a word from our friends at Acme"), line(150, "buy things")],
      [skip(150, 200), skip(400, 450)])
    XCTAssertEqual(found.count, 1)
    guard let first = found.first else { return }
    XCTAssertEqual(first.start, 100)
    XCTAssertEqual(first.end, 150)
    XCTAssertEqual(first.kind, .ad)
    XCTAssertEqual(first.confidence, .unsure)
    XCTAssertEqual(first.source, "opening-lines")
    XCTAssertEqual(first.advertiser, "")
    XCTAssertEqual(first.firstWords, "now a word from our friends at acme")
  }

  func testTheLineIsAtMostSixtySecondsBeforeTheSkip() {
    XCTAssertEqual(opened([line(100, "now a word from us")], [skip(160, 200)]).count, 1)
    XCTAssertEqual(opened([line(100, "now a word from us")], [skip(160.5, 200)]).count, 0)
    XCTAssertEqual(CueAds.reach, 60)
  }

  func testAReturnLineBetweenStopsThePull() {
    let lines = [line(100, "now a word from us"), line(120, "and we are back")]
    XCTAssertTrue(opened(lines, [skip(150, 200)]).isEmpty)
    // A return line before the opening line, or after the skip starts, does not stop it.
    let outside = [line(90, "and we are back"), line(100, "now a word from us"), line(150, "and we are here")]
    XCTAssertEqual(opened(outside, [skip(150, 200)]).count, 1)
  }

  func testALineInsideASkipIsIgnored() {
    XCTAssertTrue(opened([line(160, "now a word from us")], [skip(150, 200)]).isEmpty)
    XCTAssertTrue(opened([line(150, "now a word from us")], [skip(150, 200)]).isEmpty, "the start is inside")
    XCTAssertTrue(opened([line(20, "now a word from us")], [skip(150, 200)]).isEmpty, "a line with no skip after it in reach")
  }

  func testAShowsOwnCueOpensOnlyThatShow() {
    let lines = [line(100, "quick message from acme")]
    XCTAssertEqual(opened(lines, [skip(150, 200)]).count, 1)
    XCTAssertTrue(opened(lines, [skip(150, 200)], show: "https://other.test/rss").isEmpty)
  }

  func testAStretchIsPulledBackOnce() {
    let found = opened(
      [line(100, "now a word one"), line(110, "now a word two")], [skip(150, 200)])
    XCTAssertEqual(found.map(\.start), [100])
    // Two stretches each get their own line.
    let two = opened(
      [line(100, "now a word one"), line(300, "now a word two")], [skip(150, 200), skip(350, 400)])
    XCTAssertEqual(two.map(\.start), [100, 300])
  }

  func testTheKindIsThatOfTheFirstAdOfTheStretchWhateverTheKinds() {
    let skips = [skip(160, 200, .ad), skip(150, 170, .promo)]
    let found = opened([line(100, "now a word from us")], skips)
    XCTAssertEqual(found.first?.kind, .promo, "the two overlap, and the promo starts first")
    let touching = opened([line(100, "now a word from us")], [skip(150, 170, .ownPlug), skip(170, 200, .ad)])
    XCTAssertEqual(touching.first?.kind, .ownPlug)
  }

  func testLinesInAnyOrderGiveTheSameAnswer() {
    let lines = [line(150, "x"), line(110, "now a word two"), line(100, "now a word one")]
    XCTAssertEqual(opened(lines, [skip(160, 200)]).map(\.start), [100])
  }

  func testBadInputAddsNothing() {
    let lines = [line(100, "now a word from us")]
    XCTAssertTrue(opened([], [skip(150, 200)]).isEmpty)
    XCTAssertTrue(opened(lines, []).isEmpty)
    XCTAssertTrue(CueAds.openings(lines: lines, skips: [skip(150, 200)], cues: AdCues(), show: show).isEmpty)
    XCTAssertTrue(opened([line(.nan, "now a word from us")], [skip(150, 200)]).isEmpty)
    XCTAssertTrue(opened(lines, [skip(.nan, 200), skip(150, .infinity), skip(200, 150)]).isEmpty)
  }

  // MARK: Filled holes

  private var fill: [TranscriptLine] { [
    line(10, "welcome everyone, gardens grow tomatoes"),
    line(105, "zorbex is the thing"),
    line(132, "zorbex smoothie tastes great"),
    line(155, "zorbex again"),
    line(300, "great gardens"),
  ] }

  private func filled(
    _ lines: [TranscriptLine], _ skips: [FoundAd]
  ) -> [FoundAd] {
    CueAds.holes(lines: lines, skips: skips, cues: cues, show: show)
  }

  func testAHoleWithAnEchoAndTheTopicOfTheAdsIsFilled() {
    let found = filled(fill, [skip(100, 130, .promo), skip(150, 180)])
    XCTAssertEqual(found.count, 1)
    guard let hole = found.first else { return }
    XCTAssertEqual(hole.start, 130)
    XCTAssertEqual(hole.end, 150)
    XCTAssertEqual(hole.kind, .promo, "the kind of the stretch before it")
    XCTAssertEqual(hole.confidence, .unsure)
    XCTAssertEqual(hole.source, "filled-holes")
    XCTAssertEqual(hole.advertiser, "")
    XCTAssertEqual(hole.firstWords, "zorbex smoothie tastes great")
  }

  func testWithoutAnEchoInTheStretchesTheHoleStays() {
    var lines = fill
    lines[1] = line(105, "plain words here")
    lines[3] = line(155, "plain again")
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(150, 180)]).isEmpty)
  }

  func testAWordTheShowUsesOutsideIsNoEcho() {
    var lines = fill
    lines.append(line(400, "zorbex in the garden"))
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(150, 180)]).isEmpty)
  }

  func testAQuarterOfTheHolesWordsMayBeTheShowsAndMoreMayNot() {
    // Four content words in the hole, one of them (great) used by the show outside: a quarter.
    XCTAssertEqual(filled(fill, [skip(100, 130), skip(150, 180)]).count, 1)
    var more = fill
    more.append(line(310, "tastes of tomatoes"))
    XCTAssertTrue(
      filled(more, [skip(100, 130), skip(150, 180)]).isEmpty, "two of four are the show's")
  }

  func testTheHoleIsAtMostSixtySecondsLong() {
    let lines = [line(105, "zorbex is the thing"), line(132, "zorbex smoothie tastes"), line(195, "zorbex again")]
    XCTAssertEqual(filled(lines, [skip(100, 130), skip(190, 220)]).count, 1)
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(190.5, 220)]).isEmpty)
    XCTAssertEqual(CueAds.longestHole, 60)
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(130, 220)]).isEmpty, "no hole")
  }

  func testAReturnLineInTheHoleStopsIt() {
    var lines = fill
    lines.append(line(140, "and we are back to the garden"))
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(150, 180)]).isEmpty)
  }

  func testAHoleWithNoContentWordIsNotFilled() {
    var lines = fill
    lines[2] = line(132, "so we go on to it")
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(150, 180)]).isEmpty)
    lines[2] = line(132, "about with that show")
    XCTAssertTrue(filled(lines, [skip(100, 130), skip(150, 180)]).isEmpty, "common words are no content")
  }

  func testTwoHolesInAChainAreBothFilledAndKeepTheFirstKind() {
    let lines = [
      line(105, "zorbex is the thing"), line(132, "zorbex smoothie"), line(155, "zorbex again"),
      line(182, "quillmat shake"), line(205, "quillmat too"),
    ]
    let found = filled(lines, [skip(100, 130, .promo), skip(150, 180, .ad), skip(200, 230, .ad)])
    XCTAssertEqual(found.map(\.start), [130, 180])
    XCTAssertEqual(found.map(\.end), [150, 200])
    XCTAssertEqual(found.map(\.kind), [.promo, .promo])
  }

  func testHolesBadInputAddsNothing() {
    XCTAssertTrue(filled([], [skip(100, 130), skip(150, 180)]).isEmpty)
    XCTAssertTrue(filled(fill, [skip(100, 130)]).isEmpty, "one stretch has no hole")
    XCTAssertTrue(filled(fill, []).isEmpty)
    XCTAssertTrue(CueAds.holes(lines: fill, skips: [skip(100, 130), skip(150, 180)], cues: AdCues(), show: show).isEmpty)
    XCTAssertTrue(filled([line(.nan, "zorbex")], [skip(100, 130), skip(150, 180)]).isEmpty)
    XCTAssertTrue(filled(fill, [skip(.nan, 130), skip(150, .infinity)]).isEmpty)
  }

  func testTheOpeningsAndTheHolesWorkTogether() {
    let lines = [line(60, "now a word from zorbex"), line(132, "zorbex smoothie"), line(155, "zorbex again")]
    let skips = [skip(100, 130), skip(150, 180)]
    let first = opened(lines, skips)
    XCTAssertEqual(first.map(\.start), [60])
    XCTAssertEqual(first.first?.end, 100)
    let second = filled(lines, skips + first)
    XCTAssertEqual(second.map(\.start), [130])
  }

  // MARK: The ad-end check

  func testTheHolesAlsoCarryAnEndOnWhileTheNextLinesSell() {
    let code = "use code GARDEN at checkout"
    // One skip and no hole: the line after it gives a promo code.
    let one = filled([line(131, code), line(136, "plain talk")], [skip(100, 130)])
    XCTAssertEqual(one.map(\.start), [130])
    XCTAssertEqual(one.map(\.end), [136])
    XCTAssertEqual(one.first?.source, "filled-holes")
    // A filled hole first, then the end of the joined stretch.
    var lines = fill
    lines.insert(line(181, code), at: 4)
    lines.insert(line(186, "plain talk"), at: 5)
    let both = filled(lines, [skip(100, 130, .promo), skip(150, 180)])
    XCTAssertEqual(both.map(\.start), [130, 180])
    XCTAssertEqual(both.map(\.end), [150, 186])
    XCTAssertEqual(both.map(\.kind), [.promo, .ad])
    // With no cues from the Mac the finder is off, and so is the check.
    XCTAssertTrue(
      CueAds.holes(lines: [line(131, code)], skips: [skip(100, 130)], cues: AdCues(), show: show)
        .isEmpty)
    // The Mac's marks are handed on to the check: an end that is a mark's end stays.
    XCTAssertTrue(
      CueAds.holes(
        lines: [line(131, code), line(136, "plain talk")], skips: [skip(100, 130)], cues: cues,
        show: show, marks: [skip(110, 130)]
      ).isEmpty)
  }
}
