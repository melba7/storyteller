import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdCleanupTests: XCTestCase {
  private let plain = makeTranscript(talk(60))

  /// Plain talk with a line that sells (a web address) at each of `lines`, counted from 1. An ad
  /// that the model is sure of needs such a line in it, or it comes out unsure (`AdEvidence`).
  private func selling(_ count: Int, at lines: [Int]) -> [String] {
    var texts = talk(count)
    for line in lines { texts[line - 1] = "go to acme dot com today" }
    return texts
  }

  func testSureAndUnsureAreKeptAndGuessesDropped() {
    let ads = AdCleanup.run(
      ranges: [range(3, 6), range(20, 23, .unsure), range(40, 43, .guess)],
      transcript: makeTranscript(selling(60, at: [4])))
    XCTAssertEqual(ads.map(\.confidence), [.sure, .unsure])
    XCTAssertEqual(ads.count, 2)
  }

  func testLineNumbersBecomeTimes() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 6)], transcript: plain).first)
    // Line 3 starts at 20 s and line 6 ends at 59 s; the next words start at 20 s and 60 s, and
    // the edges land a quarter second before them.
    XCTAssertEqual(ad.start, 19.75, accuracy: 0.01)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
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
      ranges: [range(3, 8, .unsure), range(6, 12, .sure)],
      transcript: makeTranscript(selling(60, at: [7])))
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ad.start, 19.75, accuracy: 0.01)
    XCTAssertEqual(ad.end, 119.75, accuracy: 0.01)
    XCTAssertEqual(ad.confidence, .sure, "the same ad seen twice keeps the surer answer")
  }

  func testTheSameAdSeenTwiceIsOne() {
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 8), range(3, 8)], transcript: plain).count, 1)
  }

  func testAdsWithLittleSpeechBetweenThemAreOneBreak() throws {
    // One filler line (9 s of speech) lies between the two ads.
    var texts = selling(60, at: [4, 8])
    texts[5] = "We'll be right back after one more word from our sponsor"
    let ads = AdCleanup.run(
      ranges: [range(3, 5, .sure), range(7, 9, .sure)], transcript: makeTranscript(texts))
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ad.confidence, .sure)
  }

  func testAdsWithTwelveSecondsOfSpeechBetweenThemAreSeparate() {
    // Two lines (18 s of speech) lie between them.
    let ads = AdCleanup.run(
      ranges: [range(3, 5), range(8, 10)], transcript: makeTranscript(selling(60, at: [4, 9])))
    XCTAssertEqual(ads.count, 2)
  }

  func testSilenceBetweenAdsDoesNotCountAsSpeech() {
    // Same lines as above but the middle ones are silent: no words between the ads.
    var transcript = makeTranscript(selling(60, at: [4, 9]))
    transcript.words.removeAll { $0.start >= 50 && $0.start < 70 }
    XCTAssertEqual(AdCleanup.run(ranges: [range(3, 5), range(8, 10)], transcript: transcript).count, 1)
  }

  func testAMergedBreakNeverPassesFiveMinutes() {
    // 16 lines + 1 + 16 lines is 330 s. The line between them is filler, so only the cap keeps
    // them apart.
    var texts = selling(60, at: [3, 20])
    texts[17] = "We'll be right back after one more word from our sponsor"
    let ads = AdCleanup.run(
      ranges: [range(2, 17), range(19, 34)], transcript: makeTranscript(texts))
    XCTAssertEqual(ads.count, 2)
  }

  func testAdsOfDifferentKindsAreNotMerged() {
    let ads = AdCleanup.run(
      ranges: [range(3, 5), range(7, 9, kind: .ownPlug)],
      transcript: makeTranscript(selling(60, at: [4, 8])))
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
    var texts = selling(30, at: [4])
    texts[5] = "that is acme dot com slash show"
    texts[6] = "use code SHOW for ten percent off"
    let transcript = makeTranscript(texts)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: transcript).first)
    // Lines 6 and 7 are carried in (line 7 ends at 69 s); line 8 is plain talk.
    XCTAssertEqual(ad.end, 69.75, accuracy: 0.01)
  }

  func testTheSponsorsNameCarriesTheEndOn() throws {
    var texts = talk(30)
    texts[3] = "so Quokka is here"
    texts[5] = "Quokka makes it simple"
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: makeTranscript(texts))
        .first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testPlainTalkAfterTheAdIsNotCarriedIn() throws {
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: plain).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  // MARK: A short, strict carry-on

  private func texts(_ count: Int, line6 text: String) -> [String] {
    var texts = selling(count, at: [4])
    texts[5] = text
    return texts
  }

  func testTalkAboutTheSponsorsCompanyIsNotCarriedIn() throws {
    let talk = "Quokka shares fell four percent after the company reported earnings on Tuesday"
    let transcript = makeTranscript(texts(30, line6: talk))
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  func testAThanksToTheSponsorIsCarriedIn() throws {
    let transcript = makeTranscript(texts(30, line6: "Thanks again to Quokka"))
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: transcript).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testALongLineThatNamesTheSponsorWithoutACueIsNotCarriedIn() throws {
    // Nine words, the name, no soft cue: the hosts are talking about the company.
    let transcript = makeTranscript(
      texts(30, line6: "I read that Quokka is opening an office in Lisbon next year"))
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "Quokka")], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  func testAReturnToTheShowEndsTheAdEvenWithAWebAddressAfterIt() throws {
    let transcript = makeTranscript(
      texts(30, line6: "Welcome back to the show, find us at example.com slash podcast"))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  func testTheShowIsBackInTheModelsOwnLastLinesTrimsTheAd() throws {
    let transcript = makeTranscript(texts(30, line6: "And we're back. So where were we"))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 6)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01, "the ad ends at line 5")
  }

  func testAHardSignalKeepsALineThatSaysWelcomeBack() throws {
    let transcript = makeTranscript(
      texts(30, line6: "Welcome back, and remember code SHOW at acme.com"))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 6)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testTheAdvertisersNameAfterTheReturnCueKeepsTheLine() throws {
    var texts = talk(30)
    texts[5] = "Welcome back to the show"
    texts[6] = "Quokka is the best"
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 7, advertiser: "Quokka")], transcript: makeTranscript(texts))
        .first)
    XCTAssertEqual(ad.end, 69.75, accuracy: 0.01)
  }

  func testOnlyTheModelsLastThreeLinesAreTrimmedAndNeverItsFirst() throws {
    var texts = talk(30)
    texts[3] = "welcome back to the show"  // line 4 of an ad that ends at line 9
    let transcript = makeTranscript(texts)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 9)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 89.75, accuracy: 0.01, "line 4 is not one of the last three")
    var first = talk(30)
    first[2] = "welcome back to the show"
    let short = makeTranscript(first)
    let whole = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: short).first)
    XCTAssertEqual(whole.start, 19.75, accuracy: 0.01, "the first line is never trimmed")
    XCTAssertEqual(whole.end, 49.75, accuracy: 0.01)
  }

  func testTheSponsorsNameCarriesTheEndOnWhateverTheRecogniserSpacedIt() throws {
    var texts = texts(30, line6: "Better Help makes it simple")
    texts[3] = "go to better help dot com"
    let ad = try XCTUnwrap(
      AdCleanup.run(
        ranges: [range(3, 5, advertiser: "BetterHelp")], transcript: makeTranscript(texts)
      ).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testCarryingOnStopsAfterTwoLines() {
    let texts = [String](repeating: "go to acme dot com", count: 40)
    let carried = AdCleanup.carriedEnd(
      of: 5, advertiser: "Acme", lines: makeTranscript(texts).lines)
    XCTAssertEqual(carried, 7)
  }

  func testACarriedLineMustEndWithinFifteenSecondsOfTheLineBeforeIt() {
    // Two lines of 3 s with 20 s of silence before the second.
    let lines = [
      TranscriptLine(start: 0, end: 30, text: "the ad"),
      TranscriptLine(start: 31, end: 34, text: "go to acme dot com"),
      TranscriptLine(start: 54, end: 57, text: "go to acme dot com"),
    ]
    XCTAssertEqual(AdCleanup.carriedEnd(of: 1, advertiser: "Acme", lines: lines), 2)
  }

  func testALongLineThatStartsSoonButEndsLateIsNotCarried() {
    // The model's last line ends at 50 s. The next starts 14 s later, so it starts within 15 s,
    // but it runs 16 s and ends 30 s after the ad: host talk that only mentions the site.
    let lines = [
      TranscriptLine(start: 0, end: 50, text: "this is brought to you by Acme at acme dot com"),
      TranscriptLine(start: 64, end: 80, text: "I told my brother about acme dot com last week"),
    ]
    XCTAssertEqual(AdCleanup.carriedEnd(of: 1, advertiser: "Acme", lines: lines), 1)
    let transcript = Transcript(
      identity: makeTranscript(["x"]).identity, duration: 100, lines: lines, words: [])
    let ad = AdCleanup.run(ranges: [range(1, 1)], transcript: transcript).first
    XCTAssertEqual(ad?.end, 50)
  }

  func testALineThatEndsExactlyFifteenSecondsAfterTheLineBeforeItIsCarried() {
    let carried = [
      TranscriptLine(start: 0, end: 50, text: "the ad"),
      TranscriptLine(start: 52, end: 65, text: "go to acme dot com"),
    ]
    XCTAssertEqual(AdCleanup.carriedEnd(of: 1, advertiser: "Acme", lines: carried), 2)
    var late = carried
    late[1].end = 65.5
    XCTAssertEqual(AdCleanup.carriedEnd(of: 1, advertiser: "Acme", lines: late), 1)
  }

  func testEachCarriedLineIsMeasuredFromTheOneBeforeIt() {
    // The second carried line ends 25 s after the model's last line, 12 s after the first one.
    let lines = [
      TranscriptLine(start: 0, end: 50, text: "the ad"),
      TranscriptLine(start: 52, end: 63, text: "go to acme dot com"),
      TranscriptLine(start: 64, end: 75, text: "use code SHOW at acme dot com"),
      TranscriptLine(start: 76, end: 80, text: "go to acme dot com"),
    ]
    XCTAssertEqual(AdCleanup.carriedEnd(of: 1, advertiser: "Acme", lines: lines), 3)
  }

  func testAnUnsureAdIsNeverCarriedOn() throws {
    let transcript = makeTranscript(texts(30, line6: "that is acme dot com slash show"))
    let unsure = [range(3, 5, .unsure)]
    let ad = try XCTUnwrap(AdCleanup.run(ranges: unsure, transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.01)
  }

  // MARK: A stricter merge

  private let breakLine = "We'll be right back after one more word from our sponsor"

  func testAdsWithPlainTalkBetweenThemAreTwoAds() {
    // One line (9 s of speech) of plain talk lies between the two ads.
    let ads = AdCleanup.run(
      ranges: [range(3, 5), range(7, 9)], transcript: makeTranscript(selling(30, at: [4, 8])))
    XCTAssertEqual(ads.count, 2)
  }

  func testAFillerLineBetweenTwoSureAdsMakesThemOneBreak() throws {
    var texts = selling(30, at: [4, 8])
    texts[5] = breakLine
    let ads = AdCleanup.run(
      ranges: [range(3, 5), range(7, 9)], transcript: makeTranscript(texts))
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ad.start, 19.75, accuracy: 0.01)
    XCTAssertEqual(ad.end, 89.75, accuracy: 0.01)
  }

  func testALineThatNamesEitherAdvertiserIsFiller() {
    var texts = selling(30, at: [4, 8])
    texts[5] = "so tell me more about Zebra"
    let ranges = [range(3, 5), range(7, 9, advertiser: "Zebra")]
    XCTAssertEqual(AdCleanup.run(ranges: ranges, transcript: makeTranscript(texts)).count, 1)
  }

  func testALineWithAWebAddressBetweenTwoAdsIsFiller() {
    // Lines 6 and 7 are carried into the first ad; line 8 is the third address line, so it is
    // left between the ads, and it is filler because of its address.
    var texts = selling(30, at: [4, 10])
    for line in 5...7 { texts[line] = "go to acme dot com" }
    let ranges = [range(3, 5), range(9, 11, advertiser: "Zebra")]
    XCTAssertEqual(AdCleanup.run(ranges: ranges, transcript: makeTranscript(texts)).count, 1)
  }

  func testASureAndAnUnsureAdWithFillerBetweenThemStayTwo() {
    var texts = selling(30, at: [4, 8])
    texts[5] = breakLine
    let ads = AdCleanup.run(
      ranges: [range(3, 5, .sure), range(7, 9, .unsure)], transcript: makeTranscript(texts))
    XCTAssertEqual(ads.map(\.confidence), [.sure, .unsure])
    let both = AdCleanup.run(
      ranges: [range(3, 5, .unsure), range(7, 9, .unsure)], transcript: makeTranscript(texts))
    XCTAssertEqual(both.count, 2, "an unsure ad never merges with a neighbour it does not overlap")
  }

  func testFillerDoesNotJoinAdsWithTwelveSecondsOfSpeechBetweenThem() {
    var texts = selling(30, at: [4, 9])
    texts[5] = breakLine
    texts[6] = breakLine  // 18 s of speech
    let ads = AdCleanup.run(
      ranges: [range(3, 5), range(8, 10)], transcript: makeTranscript(texts))
    XCTAssertEqual(ads.count, 2)
  }

  func testEveryLineBetweenTwoAdsMustBeFiller() {
    // Two short lines, 6 s of speech in all.
    func transcript(second: String) -> Transcript {
      ownTranscript(
        lines: [
          (0, 40, "the first ad acme.com"), (41, 44, breakLine), (45, 48, second),
          (49, 90, "the second ad acme.com"), (91, 130, "the show"),
        ],
        words: seconds(0, 44) + seconds(45, 130))
    }
    XCTAssertEqual(
      AdCleanup.run(ranges: [range(1, 1), range(4, 4)], transcript: transcript(second: "and we chat"))
        .count, 2)
    XCTAssertEqual(
      AdCleanup.run(ranges: [range(1, 1), range(4, 4)], transcript: transcript(second: breakLine))
        .count, 1)
  }

  func testUnderFourSecondsOfSpeechBetweenTwoSureAdsStillMerges() {
    let transcript = ownTranscript(
      lines: [
        (0, 40, "the first ad acme.com"), (41, 43, "and"), (44, 90, "the second ad acme.com"),
        (91, 130, "show"),
      ],
      words: seconds(0, 43) + seconds(44, 130))
    XCTAssertEqual(AdCleanup.run(ranges: [range(1, 1), range(3, 3)], transcript: transcript).count, 1)
  }

  // MARK: The trace

  func testExplainSaysOneLineWasCarriedAndNamesIt() throws {
    var texts = selling(30, at: [4])
    texts[5] = "go to acme dot com"
    let trace = try XCTUnwrap(
      AdCleanup.explain(ranges: [range(3, 5)], transcript: makeTranscript(texts)).first)
    XCTAssertEqual(trace.firstLine, 3)
    XCTAssertEqual(trace.lastLine, 5)
    XCTAssertEqual(trace.carried.map(\.number), [6])
    XCTAssertEqual(trace.carried.first?.text, "go to acme dot com")
    XCTAssertEqual(trace.carried.first?.start, 50)
    XCTAssertTrue(trace.trimmed.isEmpty)
    XCTAssertEqual(trace.answers, 1)
    XCTAssertEqual(trace.ad.start, 19.75, accuracy: 0.01)
    XCTAssertEqual(trace.ad.end, 59.75, accuracy: 0.01)
  }

  func testExplainNamesTheLinesTheShowIsBackTrimmedOff() throws {
    var texts = talk(30)
    texts[4] = "and we're back"
    texts[5] = "So where were we"
    let trace = try XCTUnwrap(
      AdCleanup.explain(ranges: [range(3, 6)], transcript: makeTranscript(texts)).first)
    XCTAssertEqual(trace.lastLine, 6, "the model's own last line")
    XCTAssertEqual(trace.trimmed.map(\.number), [5, 6])
    XCTAssertTrue(trace.carried.isEmpty)
    XCTAssertEqual(trace.ad.end, 39.75, accuracy: 0.01)
  }

  func testExplainCountsTheAnswersJoinedIntoOneAd() throws {
    let traces = AdCleanup.explain(
      ranges: [range(3, 8, .unsure), range(6, 12, .sure), range(30, 33)], transcript: plain)
    XCTAssertEqual(traces.map(\.answers), [2, 1])
    XCTAssertEqual(traces[0].firstLine, 3)
    XCTAssertEqual(traces[0].lastLine, 12)
  }

  func testExplainShowsTwoLinesBeforeAndThreeAfterEachEdge() throws {
    let trace = try XCTUnwrap(AdCleanup.explain(ranges: [range(3, 5)], transcript: plain).first)
    XCTAssertEqual(trace.aroundStart.before.map(\.number), [1, 2])
    XCTAssertEqual(trace.aroundStart.after.map(\.number), [3, 4, 5])
    XCTAssertEqual(trace.aroundEnd.before.map(\.number), [4, 5])
    XCTAssertEqual(trace.aroundEnd.after.map(\.number), [6, 7, 8])
    XCTAssertEqual(trace.aroundEnd.after.first?.text, "plain talk number 6 here")
    XCTAssertEqual(trace.aroundEnd.after.first?.start, 50)
    let top = try XCTUnwrap(AdCleanup.explain(ranges: [range(1, 3)], transcript: plain).first)
    XCTAssertTrue(top.aroundStart.before.isEmpty)
    let bottom = try XCTUnwrap(AdCleanup.explain(ranges: [range(58, 60)], transcript: plain).first)
    XCTAssertTrue(bottom.aroundEnd.after.isEmpty)
  }

  func testRunGivesTheAdsExplainDoes() {
    var texts = talk(60)
    texts[5] = "go to acme dot com"
    texts[24] = "welcome back to the show"
    let transcript = makeTranscript(texts)
    let ranges = [
      range(3, 5), range(10, 14, .unsure), range(20, 25), range(40, 43, .guess), range(4, 7),
    ]
    XCTAssertEqual(
      AdCleanup.run(ranges: ranges, transcript: transcript),
      AdCleanup.explain(ranges: ranges, transcript: transcript).map(\.ad))
  }

  // MARK: Where the player lands

  /// A transcript from hand-placed lines and words (start, end, text), for the tests that need
  /// exact word times.
  private func ownTranscript(
    lines: [(Double, Double, String)], words: [(Double, Double)], duration: Double = 200
  ) -> Transcript {
    let identity = TranscriptIdentity(
      locale: "en", recogniser: "f", recogniserVersion: "1", osVersion: "26", sha256: "aa")
    return Transcript(
      identity: identity, duration: duration,
      lines: lines.map { TranscriptLine(start: $0.0, end: $0.1, text: $0.2) },
      words: words.enumerated().map {
        TranscriptWord(text: "w\($0.offset)", start: $0.element.0, end: $0.element.1)
      })
  }

  /// One-second words from `from` up to `to`.
  private func seconds(_ from: Int, _ to: Int) -> [(Double, Double)] {
    (from..<to).map { (Double($0), Double($0 + 1)) }
  }

  func testTheLandingIsAQuarterSecondBeforeTheFirstWordAfterTheAd() throws {
    let transcript = makeTranscript(talk(30))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(3, 5)], transcript: transcript).first)
    XCTAssertEqual(ad.start, 19.75, accuracy: 0.001)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.001)
  }

  func testAPauseThreeSecondsIntoTheShowDoesNotPullTheEnd() throws {
    // The ad's last word is 48.0 to 49.0. The show's words run on from 49.2 to 52.0, then a
    // pause lasts to 54.0. The old snap moved the end to the middle of that pause, 53.0.
    let showWords: [(Double, Double)] = [(49.2, 49.9), (49.9, 50.6), (50.6, 51.3), (51.3, 52.0)]
    let words = seconds(0, 49) + showWords + seconds(54, 80)
    let transcript = ownTranscript(
      lines: [(0, 20, "before"), (20, 49, "the ad"), (49.2, 52, "the show"), (54, 80, "more")],
      words: words)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 48.95, accuracy: 0.001)
    XCTAssertEqual(ad.start, 20, accuracy: 0.001, "words run on from the word before, so no margin")
  }

  func testWordsThatRunOnToTheNextWordStillLeaveAMargin() throws {
    // The last ad word is 48.0 to 50.0 and the next word starts at 50.0.
    let words = seconds(0, 48) + [(48.0, 50.0)] + seconds(50, 80)
    let transcript = ownTranscript(
      lines: [(0, 20, "before"), (20, 50, "the ad"), (50, 80, "the show")], words: words)
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: transcript).first)
    XCTAssertEqual(ad.end, 49.75, accuracy: 0.001)
  }

  func testAnAdThatBeginsInTheFirstSixSecondsBeginsAtZero() throws {
    // An intro word 0.0 to 3.5, a gap, then the ad's first word at 4.0.
    let early = ownTranscript(
      lines: [(0, 3.5, "hi"), (4, 40, "the ad"), (40, 80, "the show")],
      words: [(0, 3.5)] + seconds(4, 80))
    let first = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: early).first)
    XCTAssertEqual(first.start, 0)
  }

  func testAnAdThatBeginsAfterSixSecondsLandsBeforeItsFirstWord() throws {
    // An intro word 0.0 to 5.5, a gap, then the ad's first word at 7.0.
    let late = ownTranscript(
      lines: [(0, 5.5, "hi"), (7, 40, "the ad"), (40, 80, "the show")],
      words: [(0, 5.5)] + seconds(7, 80))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: late).first)
    XCTAssertEqual(ad.start, 6.75, accuracy: 0.001)
  }

  func testAnAdWithNoWordBeforeItBeginsAtZero() throws {
    // Music for 20 s, then the ad's first word: nothing was said before it.
    let transcript = ownTranscript(
      lines: [(20, 60, "the ad"), (60, 100, "the show")], words: seconds(20, 100))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(1, 1)], transcript: transcript).first)
    XCTAssertEqual(ad.start, 0)
  }

  func testTheFirstWordsStayTheAdsOwnWhenTheStartMovesToZero() throws {
    let early = ownTranscript(
      lines: [(0, 3.5, "hi"), (4, 40, "the ad"), (40, 80, "the show")],
      words: [(0, 3.5)] + seconds(4, 80))
    let ad = try XCTUnwrap(AdCleanup.run(ranges: [range(2, 2)], transcript: early).first)
    XCTAssertFalse(ad.firstWords.hasPrefix("w0 "), ad.firstWords)
    XCTAssertTrue(ad.firstWords.hasPrefix("w1 "), ad.firstWords)
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
    var texts = selling(30, at: [4])
    texts[5] = "visit sleepy.com today"
    let ad = try XCTUnwrap(
      AdCleanup.run(ranges: [range(3, 5, advertiser: "")], transcript: makeTranscript(texts)).first)
    XCTAssertEqual(ad.end, 59.75, accuracy: 0.01)
  }

  func testNoLinesGiveNoAds() {
    XCTAssertTrue(AdCleanup.run(ranges: [range(1, 2)], transcript: makeTranscript([])).isEmpty)
  }
}
