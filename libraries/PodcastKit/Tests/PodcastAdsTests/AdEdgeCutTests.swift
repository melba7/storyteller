import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdEdgeCutTests: XCTestCase {
  /// A transcript from lines placed by hand, each a start second and its text. Every word lasts
  /// half a second and the next one starts a second after it, so a pause of half a second lies
  /// between all words.
  private func transcript(_ lines: [(Double, String)]) -> Transcript {
    var words: [TranscriptWord] = []
    var made: [TranscriptLine] = []
    for (start, text) in lines {
      let pieces = text.split(separator: " ").map(String.init)
      for (index, piece) in pieces.enumerated() {
        let at = start + Double(index)
        words.append(TranscriptWord(text: piece, start: at, end: at + 0.5))
      }
      made.append(TranscriptLine(start: start, end: start + Double(pieces.count) - 0.5, text: text))
    }
    let identity = TranscriptIdentity(
      locale: "en", recogniser: "f", recogniserVersion: "1", osVersion: "26", sha256: "aa")
    return Transcript(identity: identity, duration: 200, lines: made, words: words)
  }

  private let body = "this is a plain line of fifteen words that talks about what a mattress can do"

  /// The ad found when the model says lines 2 and 3 of a transcript are one, and line 3 is
  /// `text`; line 4 is the show.
  private func ad(
    ending text: String, advertiser: String = "Acme", _ confidence: AdConfidence = .sure
  ) throws -> FoundAd {
    let made = transcript([
      (10, "so this is the plain talk before the ad"), (30, body), (50, text),
      (70, "the show goes on and on"),
    ])
    return try XCTUnwrap(
      AdCleanup.run(
        ranges: [range(2, 3, confidence, advertiser: advertiser)], transcript: made
      ).first)
  }

  // MARK: The end

  func testTheAdEndsBeforeTheShowIsBackInItsLastLine() throws {
    // "we're" starts at 57.0. Without the cut the end is a quarter second before the next
    // line, 69.75.
    let found = try ad(ending: "that's acme dot com slash show and we're back with Dana")
    XCTAssertEqual(found.end, 56.75, accuracy: 0.001)
    XCTAssertEqual(found.start, 29.75, accuracy: 0.001)
  }

  func testAWebAddressAfterTheCueKeepsTheWholeLine() throws {
    let found = try ad(ending: "so that is all for now and we're back at acme dot com")
    XCTAssertEqual(found.end, 69.75, accuracy: 0.001)
  }

  func testTheAdvertisersNameAfterTheCueKeepsTheWholeLine() throws {
    let found = try ad(
      ending: "go to quokka dot com and we're back with a word on Quokka", advertiser: "Quokka")
    XCTAssertEqual(found.end, 69.75, accuracy: 0.001)
  }

  func testFewerThanThreeWordsBeforeTheCueKeepTheWholeLine() throws {
    let found = try ad(ending: "acme.com we're back with Dana")
    XCTAssertEqual(found.end, 69.75, accuracy: 0.001)
    let three = try ad(ending: "acme dot com we're back with Dana")
    XCTAssertEqual(three.end, 52.75, accuracy: 0.001)
  }

  func testALineWithNoCueIsNotCut() throws {
    let found = try ad(ending: "that's acme dot com slash show and that is all")
    XCTAssertEqual(found.end, 69.75, accuracy: 0.001)
  }

  func testAnUnsureAdIsCutToo() throws {
    let found = try ad(
      ending: "that's acme dot com slash show and we're back with Dana", .unsure)
    XCTAssertEqual(found.end, 56.75, accuracy: 0.001)
  }

  func testALineThatDoesNotMatchItsWordsIsLeftAlone() throws {
    var made = transcript([
      (10, "so this is the plain talk before the ad"), (30, body),
      (50, "that's acme dot com slash show and we're back with Dana"),
      (70, "the show goes on and on"),
    ])
    made.words.removeAll { $0.start == 55 }  // the recogniser lost a word the line still has
    let found = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 3)], transcript: made).first)
    XCTAssertEqual(found.end, 69.75, accuracy: 0.001)
  }

  // MARK: The start

  private let lead = "so that was wild anyway we should take a short break and now "

  private func started(by text: String, _ confidence: AdConfidence = .sure) throws -> FoundAd {
    let made = transcript([
      (10, "so this is the plain talk before the ad"), (20, text),
      (50, "go to quokka dot com for ten percent off today"), (70, "the show goes on and on"),
    ])
    return try XCTUnwrap(
      AdCleanup.run(
        ranges: [range(2, 3, confidence, advertiser: "Quokka")], transcript: made
      ).first)
  }

  func testASureAdStartsAtItsLeadInWhenEightWordsOrMoreComeBeforeIt() throws {
    // "this" is word 13 of the line, so it starts at 33.0.
    let found = try started(by: lead + "this episode is brought to you by Quokka")
    XCTAssertEqual(found.start, 32.75, accuracy: 0.001)
    XCTAssertTrue(found.firstWords.hasPrefix("this episode is brought"), found.firstWords)
  }

  func testFewerThanEightWordsBeforeTheLeadInKeepTheLineStart() throws {
    let found = try started(by: "so that was wild anyway this episode is brought to you by Quokka")
    XCTAssertEqual(found.start, 19.75, accuracy: 0.001)
  }

  func testASignalBeforeTheLeadInKeepsTheLineStart() throws {
    let found = try started(
      by: "visit acme dot com so that was wild anyway and now this episode is brought to you by Quokka")
    XCTAssertEqual(found.start, 19.75, accuracy: 0.001)
  }

  func testAnUnsureAdKeepsItsLineStart() throws {
    let found = try started(by: lead + "this episode is brought to you by Quokka", .unsure)
    XCTAssertEqual(found.start, 19.75, accuracy: 0.001)
  }

  // MARK: Finding the words

  func testTheCueAndTheLeadInAreFoundAsWordNumbers() {
    XCTAssertEqual(AdSignals.returnCueRange(in: "and we're back with Dana"), 1..<3)
    XCTAssertEqual(AdSignals.returnCueRange(in: "Welcome back to the show"), 0..<2)
    XCTAssertNil(AdSignals.returnCueRange(in: "that is all"))
    XCTAssertEqual(AdSignals.leadInRange(in: "so now this episode is brought to you by Quokka"), 2..<6)
    XCTAssertEqual(AdSignals.leadInRange(in: "sponsored by Quokka"), 0..<2)
    XCTAssertNil(AdSignals.leadInRange(in: "plain talk number 3 here"))
  }

  func testTheEarliestCueWins() {
    XCTAssertEqual(AdSignals.returnCueRange(in: "welcome back and now we are back"), 0..<2)
    XCTAssertEqual(AdSignals.leadInRange(in: "a word from our sponsors brought to you by"), 0..<4)
  }
}
