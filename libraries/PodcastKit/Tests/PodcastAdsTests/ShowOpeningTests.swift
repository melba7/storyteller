import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Finding a show's opening words in a stream's head, and what that does to an ad at 0:00. The
/// opening may only shorten an ad or drop an unsure one: never make a skip longer.
final class ShowOpeningTests: XCTestCase {
  /// The words the show opens with ("from the example network this is the daily example i'm sam").
  private let opening = "from the example network this is the daily example im sam"

  private func openingWords() -> [String] {
    ["From", "the", "Example", "Network,", "this", "is", "The", "Daily", "Example.", "I'm", "Sam."]
  }

  /// "<tag>x0 <tag>x1 ...": words no other list shares a run with.
  private func talk(_ tag: String, _ count: Int) -> [String] { (0..<count).map { "\(tag)x\($0)" } }

  private func timed(_ texts: [String], step: Double = 0.5) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(
        text: $0.element, start: Double($0.offset) * step, end: Double($0.offset + 1) * step)
    }
  }

  private func ad(
    _ start: Double, _ end: Double, _ confidence: AdConfidence = .sure, kind: AdKind = .ad
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: confidence,
      firstWords: "")
  }

  /// A head whose pre-roll is `lead` words long (half a second each), then the opening, then talk.
  private func head(lead: Int, opening words: [String]? = nil) -> [TranscriptWord] {
    timed(talk("pre", lead) + (words ?? openingWords()) + talk("show", 40))
  }

  // MARK: Finding

  func testTheOpeningIsFoundAtTheTimeOfItsFirstWord() {
    XCTAssertEqual(ShowOpening.find(opening, in: head(lead: 62)), 31.0)
    XCTAssertEqual(ShowOpening.find(opening, in: head(lead: 0)), 0.0)
    XCTAssertEqual(ShowOpening.find(opening, in: head(lead: 400)), 200.0, "within five minutes")
  }

  func testAnOpeningLaterThanFiveMinutesOrNotWholeIsNotFound() {
    XCTAssertNil(ShowOpening.find(opening, in: head(lead: 640)), "at 320 s")
    XCTAssertEqual(ShowOpening.find(opening, in: head(lead: 600)), 300.0, "300 s is still in")
    let cut = timed(talk("pre", 30) + Array(openingWords().prefix(6)))
    XCTAssertNil(ShowOpening.find(opening, in: cut), "the head ends before the opening does")
  }

  func testAMissingFirstWordIsNotTheOpening() {
    let noFirst = Array(openingWords().dropFirst())
    XCTAssertNil(
      ShowOpening.find(opening, in: head(lead: 62, opening: noFirst)),
      "the time of the opening is where its first word is")
  }

  func testOneChangedWordStillMatchesAnElevenWordOpeningButNotAnEightWordOne() {
    var one = openingWords()
    one[7] = "Nightly"
    XCTAssertEqual(ShowOpening.find(opening, in: head(lead: 62, opening: one)), 31.0)
    var two = openingWords()
    two[3] = "Channel"
    two[8] = "Show"
    XCTAssertNil(ShowOpening.find(opening, in: head(lead: 62, opening: two)))
    let short = "from the example network this is the daily"
    var changed = Array(openingWords().prefix(8))
    XCTAssertEqual(ShowOpening.find(short, in: head(lead: 62, opening: changed)), 31.0)
    changed[6] = "A"
    XCTAssertNil(
      ShowOpening.find(short, in: head(lead: 62, opening: changed)),
      "all six runs of an eight-word opening must be there")
  }

  func testALongOpeningStillMatchesWithAFewWordsChanged() {
    let long = talk("intro", 30)
    var heard = long
    heard[12] = "different"
    heard[20] = "words"
    let words = timed(talk("pre", 20) + heard + talk("show", 20))
    XCTAssertEqual(ShowOpening.find(long.joined(separator: " "), in: words), 10.0)
  }

  func testAnOpeningShorterThanEightWordsIsNeverLookedFor() {
    let words = timed(talk("a", 5) + ["welcome", "to", "the", "show", "friends"])
    XCTAssertNil(ShowOpening.find("welcome to the show friends", in: words))
  }

  // MARK: What it does to an ad

  func testAnAdThatRunsPastTheOpeningEndsAQuarterSecondBeforeIt() {
    let words = head(lead: 62)  // the opening starts at 31.0
    let at = ShowOpening.find(opening, in: words)
    XCTAssertEqual(at, 31.0)
    XCTAssertEqual(ShowOpening.shorten([ad(0, 42)], openingAt: 31.0), [ad(0, 30.75)])
  }

  func testAnAdThatEndsBeforeTheOpeningIsLeftAlone() {
    XCTAssertEqual(ShowOpening.shorten([ad(0, 20)], openingAt: 31.0), [ad(0, 20)], "never longer")
    XCTAssertEqual(ShowOpening.shorten([ad(0, 40)], openingAt: 200.0), [ad(0, 40)])
    XCTAssertEqual(ShowOpening.shorten([ad(0, 30.8)], openingAt: 31.0), [ad(0, 30.75)])
  }

  func testAnOpeningAtTwoHundredSecondsDoesNotEndAnAdThatRunsZeroToForty() {
    let words = head(lead: 400)
    let at = ShowOpening.find(opening, in: words)
    XCTAssertEqual(at, 200.0)
    XCTAssertEqual(ShowOpening.shorten([ad(0, 40, .sure)], openingAt: 200.0), [ad(0, 40)])
    XCTAssertEqual(
      ShowOpening.shorten([ad(0, 40, .unsure)], openingAt: 200.0), [ad(0, 40, .unsure)])
  }

  func testAnAdThatStartsLaterIsNeverTouched() {
    XCTAssertEqual(ShowOpening.shorten([ad(90, 130)], openingAt: 100.0), [ad(90, 130)])
    XCTAssertEqual(
      ShowOpening.shorten([ad(90, 130, .unsure)], openingAt: 100.0), [ad(90, 130, .unsure)])
    XCTAssertEqual(ShowOpening.shorten([ad(8, 60)], openingAt: 31.0), [ad(8, 60)])
  }

  func testAnUnsureAdAtTheTopThatHoldsTheOpeningIsDropped() {
    XCTAssertEqual(ShowOpening.shorten([ad(0, 42, .unsure)], openingAt: 31.0), [])
    XCTAssertEqual(
      ShowOpening.shorten([ad(0, 20, .unsure)], openingAt: 31.0), [ad(0, 20, .unsure)],
      "an unsure ad that ends before the opening is as it was")
  }

  func testAnOpeningFoundAfterFiveMinutesChangesNothing() {
    XCTAssertEqual(ShowOpening.shorten([ad(0, 400)], openingAt: 320.0), [ad(0, 400)])
    XCTAssertEqual(
      ShowOpening.shorten([ad(0, 400, .unsure)], openingAt: 320.0), [ad(0, 400, .unsure)])
  }

  func testASureAdIsNeverCutToNothing() {
    XCTAssertEqual(
      ShowOpening.shorten([ad(0, 40)], openingAt: 0.8), [ad(0, 40)],
      "the show begins at once: nothing before it to cut at")
    XCTAssertEqual(ShowOpening.shorten([ad(0, 40)], openingAt: 1.25), [ad(0, 1.0)])
  }

  func testOtherAdsStayAndTheOwnPlugAtTheTopIsCutLikeAnAd() {
    let ads = [ad(0, 42, kind: .ownPlug), ad(120, 160), ad(200, 230, .unsure)]
    XCTAssertEqual(
      ShowOpening.shorten(ads, openingAt: 31.0),
      [ad(0, 30.75, kind: .ownPlug), ad(120, 160), ad(200, 230, .unsure)])
  }

  func testNoAdIsEverLongerAfterwards() {
    for at in stride(from: 0.0, through: 320.0, by: 7.5) {
      for end in [5.0, 20.0, 31.0, 42.0, 120.0, 400.0] {
        for confidence in [AdConfidence.sure, .unsure] {
          let before = ad(0, end, confidence)
          for after in ShowOpening.shorten([before], openingAt: at) {
            XCTAssertLessThanOrEqual(after.end, before.end)
            XCTAssertEqual(after.start, before.start)
          }
        }
      }
    }
  }
}
