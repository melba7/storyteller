import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdCleanupTests: XCTestCase {
  private let plain = makeTranscript(talk(60))

  func testSureAndUnsureAreKeptAndGuessesDropped() {
    let ads = AdCleanup.run(
      ranges: [range(3, 6), range(20, 23, .unsure), range(40, 43, .guess)], transcript: plain)
    XCTAssertEqual(ads.map(\.confidence), [.sure, .unsure])
    XCTAssertEqual(ads.count, 2)
  }

  func testLineNumbersBecomeTimes() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 6)], transcript: plain).first)
    // Line 3 starts at 20 s and line 6 ends at 59 s; the nearest pauses are half a second
    // outside them.
    XCTAssertEqual(ad.start, 19.5, accuracy: 0.01)
    XCTAssertEqual(ad.end, 59.5, accuracy: 0.01)
    XCTAssertEqual(ad.advertiser, "Acme")
    XCTAssertEqual(ad.kind, .ad)
  }

  func testAnswersThatNameNoRealLinesAreDropped() {
    let ads = AdCleanup.run(
      ranges: [range(0, 4), range(58, 70), range(-3, 2)], transcript: plain)
    XCTAssertTrue(ads.isEmpty)
  }

  func testAReversedRangeIsRead() {
    XCTAssertEqual(AdCleanup.run(ranges: [range(6, 3)], transcript: plain).count, 1)
  }

  func testAnAdAcrossACutIsFoundOnce() throws {
    // One piece saw lines 3-8 and the next, overlapping, saw 6-12.
    let ads = AdCleanup.run(
      ranges: [range(3, 8, .unsure), range(6, 12, .sure)], transcript: plain)
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ad.start, 19.5, accuracy: 0.01)
    XCTAssertEqual(ad.end, 119.5, accuracy: 0.01)
    XCTAssertEqual(ad.confidence, .sure, "the same ad seen twice keeps the surer answer")
  }

  func testTheSameAdSeenTwiceIsOne() {
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 8), range(3, 8)], transcript: plain).count, 1)
  }

  func testAdsWithLittleSpeechBetweenThemAreOneBreak() throws {
    // One line (9 s of speech) lies between the two ads.
    let ads = AdCleanup.run(
      ranges: [range(3, 5, .sure), range(7, 9, .unsure)], transcript: plain)
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ad.confidence, .unsure, "a break is only as sure as its least sure part")
  }

  func testAdsWithTwelveSecondsOfSpeechBetweenThemAreSeparate() {
    // Two lines (18 s of speech) lie between them.
    let ads = AdCleanup.run(ranges: [range(3, 5), range(8, 10)], transcript: plain)
    XCTAssertEqual(ads.count, 2)
  }

  func testSilenceBetweenAdsDoesNotCountAsSpeech() {
    // Same lines as above but the middle ones are silent: no words between the ads.
    var transcript = makeTranscript(talk(60))
    transcript.words.removeAll { $0.start >= 50 && $0.start < 70 }
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 5), range(8, 10)], transcript: transcript).count, 1)
  }

  func testAMergedBreakNeverPassesFiveMinutes() {
    // 16 lines + 1 + 16 lines is 330 s.
    let ads = AdCleanup.run(ranges: [range(2, 17), range(19, 34)], transcript: plain)
    XCTAssertEqual(ads.count, 2)
  }

  func testAdsOfDifferentKindsAreNotMerged() {
    let ads = AdCleanup.run(ranges: [range(3, 5), range(7, 9, kind: .ownPlug)], transcript: plain)
    XCTAssertEqual(ads.map(\.kind), [.ad, .ownPlug])
  }

  func testUnderTenSecondsIsDroppedAndTenIsKept() {
    // One line is 9 s of speech (10 s with the pauses either side).
    var transcript = makeTranscript(talk(20))
    transcript.words.removeAll()  // no pauses: edges stay on the lines
    XCTAssertTrue(AdCleanup.run(ranges: [range(3, 3)], transcript: transcript).isEmpty)
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 4)], transcript: transcript).count, 1)
    let exact = makeTranscript([String](repeating: "a b c", count: 20))
    var tenSeconds = exact
    tenSeconds.lines[2].end = 30  // line 3 now lasts exactly 10 s
    tenSeconds.words.removeAll()
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 3)], transcript: tenSeconds).count, 1)
  }

  func testOverFiveMinutesIsNotSkipped() {
    // 31 lines cover 310 s.
    XCTAssertTrue(AdCleanup.run(ranges: [range(2, 32)], transcript: plain).isEmpty)
    XCTAssertEqual(AdCleanup.run(ranges: [range(2, 30)], transcript: plain).count, 1)
  }

  func testTheEndIsCarriedOnWhileTheNextLinesReadAsTheAd() throws {
    var texts = talk(30)
    texts[5] = "that is acme dot com slash show"
    texts[6] = "use code SHOW for ten percent off"
    let transcript = makeTranscript(texts)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: transcript).first)
    // Lines 6 and 7 are carried in (line 7 ends at 69 s); line 8 is plain talk.
    XCTAssertEqual(ad.end, 69.5, accuracy: 0.01)
  }

  func testTheSponsorsNameCarriesTheEndOn() throws {
    var texts = talk(30)
    texts[5] = "Quokka makes it simple"
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: makeTranscript(texts))
        .first)
    XCTAssertEqual(ad.end, 59.5, accuracy: 0.01)
  }

  func testPlainTalkAfterTheAdIsNotCarriedIn() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: plain).first)
    XCTAssertEqual(ad.end, 49.5, accuracy: 0.01)
  }

  func testCarryingOnStopsAfterEightLines() {
    let texts = [String](repeating: "go to acme dot com", count: 40)
    let carried = AdCleanup.carriedEnd(
      of: 5, advertiser: "Acme", lines: makeTranscript(texts).lines)
    XCTAssertEqual(carried, 13)
  }

  func testEdgesMoveToTheNearestPauseWithinReach() throws {
    // Words run without a gap except a 2 s pause from 28 s to 30 s; the answer's line starts
    // at 31 s, inside the next sentence.
    let words = (0..<60).map { i -> TranscriptWord in
      let start = Double(i) + (i >= 28 ? 2 : 0)
      return TranscriptWord(text: "w\(i)", start: start, end: start + 1)
    }
    let lines = [
      TranscriptLine(start: 0, end: 29, text: "before"), TranscriptLine(start: 31, end: 80, text: "ad"),
      TranscriptLine(start: 80, end: 100, text: "after"),
    ]
    let identity = TranscriptIdentity(
      locale: "en", recogniser: "f", recogniserVersion: "1", osVersion: "26", sha256: "aa")
    let transcript = Transcript(identity: identity, duration: 100, lines: lines, words: words)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: transcript).first)
    XCTAssertEqual(ad.start, 29, accuracy: 0.01, "the middle of the pause 28 s to 30 s")
  }

  func testAnEdgeFarFromAnyPauseStays() throws {
    let words = (0..<100).map { TranscriptWord(text: "w\($0)", start: Double($0), end: Double($0) + 1) }
    let lines = [
      TranscriptLine(start: 0, end: 40, text: "before"), TranscriptLine(start: 40, end: 80, text: "ad"),
      TranscriptLine(start: 80, end: 100, text: "after"),
    ]
    let identity = TranscriptIdentity(
      locale: "en", recogniser: "f", recogniserVersion: "1", osVersion: "26", sha256: "aa")
    let transcript = Transcript(identity: identity, duration: 100, lines: lines, words: words)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: transcript).first)
    XCTAssertEqual(ad.start, 40)
    XCTAssertEqual(ad.end, 80)
  }

  func testAnAdAtTheVeryEndStopsAtTheEndOfTheEpisode() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(55, 60)], transcript: plain).first)
    XCTAssertLessThanOrEqual(ad.end, 600)
    XCTAssertGreaterThan(ad.end, 590)
  }

  func testFirstWordsAreTheStartOfTheAd() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 6)], transcript: plain).first)
    XCTAssertTrue(ad.firstWords.hasPrefix("plain talk number 3 here"), ad.firstWords)
    XCTAssertLessThanOrEqual(ad.firstWords.split(separator: " ").count, AdRules.firstWords)
  }

  func testAnAdWithNoAdvertiserNameStillCarriesOnWebAddresses() throws {
    var texts = talk(30)
    texts[5] = "visit sleepy.com today"
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "")], transcript: makeTranscript(texts)).first)
    XCTAssertEqual(ad.end, 59.5, accuracy: 0.01)
  }

  func testNoLinesGiveNoAds() {
    XCTAssertTrue(AdCleanup.run(ranges: [range(1, 2)], transcript: makeTranscript([])).isEmpty)
  }
}
