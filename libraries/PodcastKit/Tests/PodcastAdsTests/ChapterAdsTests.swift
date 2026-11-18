import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Chapters that name a sponsor are ads, when the words inside agree (N9).
final class ChapterAdsTests: XCTestCase {
  private typealias Mark = ChapterAds.Mark

  /// 80 lines of plain talk (800 s), with `lines` (counted from 1) replaced by the given texts.
  private func transcript(_ replaced: [Int: String] = [:]) -> Transcript {
    var texts = talk(80)
    for (number, text) in replaced { texts[number - 1] = text }
    return makeTranscript(texts)
  }

  private let chapters = [
    Mark(start: 0, title: "Intro"),
    Mark(start: 600, title: "Sponsor: Squarespace"),
    Mark(start: 690, title: "Follow-up"),
  ]

  private func found(
    _ start: Double, _ end: Double, _ confidence: AdConfidence = .sure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence, firstWords: "")
  }

  // MARK: Which chapters are ads

  func testASponsorChapterWithItsNameInTheWordsIsOneAd() throws {
    let spoken = transcript([65: "go to squarespace dot com slash show"])
    let ads = ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800)
    XCTAssertEqual(ads.count, 1)
    let ad = try XCTUnwrap(ads.first)
    // The first line that sells is line 65 (640 s): the ad starts a quarter second before it.
    XCTAssertEqual(ad.start, 639.75, accuracy: 0.001)
    // The end lands a quarter second before the first word of the show (line 70 starts at 690).
    XCTAssertEqual(ad.end, 689.75, accuracy: 0.001)
    XCTAssertEqual(ad.kind, .ad)
    XCTAssertEqual(ad.confidence, .sure)
    XCTAssertEqual(ad.advertiser, "Squarespace")
    XCTAssertTrue(ad.firstWords.hasPrefix("go to squarespace dot com"))
  }

  func testTheAdStartsAtTheFirstSellingLineWhenInsertedAdsPushedTheReadLater() throws {
    // The chapter says 600 to 690, but the real read runs 630 to 720: its first 30 s are talk.
    let spoken = transcript([
      64: "this episode is brought to you by squarespace", 65: "go to squarespace dot com slash show",
      66: "squarespace makes it simple",
    ])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).first)
    // The first selling line is line 64 (630 s): a quarter second before its first word.
    XCTAssertEqual(ad.start, 629.75, accuracy: 0.001)
    XCTAssertEqual(ad.end, 689.75, accuracy: 0.001)
    XCTAssertEqual(ad.confidence, .sure)
    XCTAssertTrue(ad.firstWords.hasPrefix("this episode is brought to you by"))
  }

  func testAReadThatStartsWithTheChapterStartsWithIt() throws {
    let spoken = transcript([
      61: "this episode is brought to you by squarespace", 65: "go to squarespace dot com slash show",
    ])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).first)
    XCTAssertEqual(ad.start, 600, accuracy: 0.001)
    XCTAssertEqual(ad.end, 689.75, accuracy: 0.001)
  }

  func testALeadInStartsTheAdBeforeTheLineThatSells() throws {
    let spoken = transcript([
      63: "and now a word from our friends", 65: "go to squarespace dot com slash show",
    ])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).first)
    XCTAssertEqual(ad.start, 619.75, accuracy: 0.001)
  }

  func testTheSameChapterWithPlainTalkInsideIsNoAd() {
    XCTAssertEqual(
      ChapterAds.find(marks: chapters, transcript: transcript(), episodeDuration: 800), [])
  }

  func testAHardSignalAloneIsEnoughForAChapterWithNoName() {
    let marks = [Mark(start: 600, title: "Ad break"), Mark(start: 660, title: "Back")]
    let spoken = transcript([64: "use code show for ten percent off"])
    XCTAssertEqual(
      ChapterAds.find(marks: marks, transcript: spoken, episodeDuration: 800).count, 1)
  }

  func testTheNameInTheTitleIsEnoughWithoutAWebAddress() {
    let spoken = transcript([65: "we love squarespace so much"])
    XCTAssertEqual(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).count, 1)
  }

  func testAdventuresInPeruIsNoCandidate() {
    let marks = [Mark(start: 600, title: "Adventures in Peru"), Mark(start: 690, title: "Next")]
    let spoken = transcript([65: "go to squarespace dot com slash show"])
    XCTAssertEqual(ChapterAds.find(marks: marks, transcript: spoken, episodeDuration: 800), [])
  }

  func testTheTitlesThatAreCandidates() {
    for title in [
      "Sponsor", "Sponsors", "Sponsored: Quokka", "Ad", "Ads", "Ad break", "[Ad] Quokka",
      "Advertisement", "Adverts", "Commercial break", "Break", "Today's episode is sponsored by Quokka",
      "Brought to you by Quokka", "- Sponsor",
    ] {
      XCTAssertTrue(ChapterAds.isAdTitle(title), title)
    }
    for title in [
      "Intro", "Adventures in Peru", "Adam Grant", "Breaking news", "Breakfast", "Add a mic",
      "Interview", "Broadcast", "",
    ] {
      XCTAssertFalse(ChapterAds.isAdTitle(title), title)
    }
  }

  func testAChapterOfTheWrongLengthIsNoAd() {
    let spoken = transcript([61: "go to squarespace dot com slash show"])
    let short = [Mark(start: 600, title: "Sponsor"), Mark(start: 608, title: "Back")]
    XCTAssertEqual(ChapterAds.find(marks: short, transcript: spoken, episodeDuration: 800), [])
    let long = [Mark(start: 100, title: "Sponsor"), Mark(start: 500, title: "Back")]
    let spokenLong = transcript([11: "go to squarespace dot com slash show"])
    XCTAssertEqual(ChapterAds.find(marks: long, transcript: spokenLong, episodeDuration: 800), [])
  }

  func testAChapterOwnEndThatComesFirstIsUsed() throws {
    let marks = [
      Mark(start: 600, end: 650, title: "Sponsor: Squarespace"), Mark(start: 690, title: "Back"),
    ]
    let spoken = transcript([65: "go to squarespace dot com slash show"])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: marks, transcript: spoken, episodeDuration: 800).first)
    XCTAssertEqual(ad.end, 649.75, accuracy: 0.001)
  }

  func testTheLastChapterEndsWithTheEpisodeOrIsNoAdWithoutItsLength() throws {
    let marks = [Mark(start: 0, title: "Intro"), Mark(start: 700, title: "Sponsor: Squarespace")]
    let spoken = transcript([75: "go to squarespace dot com slash show"])
    XCTAssertEqual(ChapterAds.find(marks: marks, transcript: spoken, episodeDuration: nil), [])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: marks, transcript: spoken, episodeDuration: 780).first)
    XCTAssertEqual(ad.start, 739.75, accuracy: 0.001)  // line 75 is the first that sells
    XCTAssertEqual(ad.end, 780, accuracy: 0.3)
  }

  func testAChapterThatReachesPastTheWordsWeHaveIsNoAd() {
    let head = makeTranscript(Array(talk(30).prefix(29)) + ["go to squarespace dot com"])
    let marks = [Mark(start: 250, title: "Sponsor: Squarespace"), Mark(start: 330, title: "Back")]
    XCTAssertEqual(ChapterAds.find(marks: marks, transcript: head, episodeDuration: 3000), [])
  }

  func testMarksOutOfOrderAreSorted() {
    let spoken = transcript([65: "go to squarespace dot com slash show"])
    XCTAssertEqual(
      ChapterAds.find(marks: chapters.reversed(), transcript: spoken, episodeDuration: 800).count, 1)
  }

  func testTheShowComingBackInTheLastLinesEndsTheAdBeforeThem() throws {
    // Chapters that inserted ads have pushed late: the ad's own words end at line 65 and the
    // hosts are back from line 67, so the chapter's last lines are the show's.
    let spoken = transcript([
      64: "go to squarespace dot com slash show", 65: "thanks again to squarespace",
      67: "welcome back to the show everyone",
    ])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).first)
    XCTAssertEqual(ad.start, 629.75, accuracy: 0.001)  // line 64 is the first that sells
    // Line 66 is the last before the return cue (line 67 starts at 660): the ad ends a quarter
    // second before its first word, as any ad does.
    XCTAssertEqual(ad.end, 659.75, accuracy: 0.001)
  }

  func testAReturnCueFollowedByTheSponsorAgainDoesNotCut() throws {
    let spoken = transcript([
      67: "welcome back and now a word from squarespace",
      68: "go to squarespace dot com slash show",
    ])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: spoken, episodeDuration: 800).first)
    XCTAssertEqual(ad.end, 689.75, accuracy: 0.001)
  }

  func testAChapterNeverMakesAnAdLongerThanItself() throws {
    // The end can only land before the chapter's end, however far the next word is.
    let words = transcript([65: "go to squarespace dot com slash show"])
    let ad = try XCTUnwrap(
      ChapterAds.find(marks: chapters, transcript: words, episodeDuration: 800).first)
    XCTAssertLessThanOrEqual(ad.end, 690)
    XCTAssertGreaterThanOrEqual(ad.start, 600)
  }

  // MARK: Joining the chapters' ads to the others

  func testAChapterAdThatNoOtherAdOverlapsIsAdded() {
    let result = ChapterAds.merge([found(600, 690)], into: [found(100, 160)])
    XCTAssertEqual(result, [found(100, 160), found(600, 690)])
  }

  func testTheChaptersEndWinsWhenItIsEarlier() {
    let result = ChapterAds.merge([found(600, 690)], into: [found(600, 705, .unsure)])
    XCTAssertEqual(result, [found(600, 690, .unsure)])
  }

  func testTheChaptersEndNeverLengthensAnAd() {
    let result = ChapterAds.merge([found(600, 690)], into: [found(600, 680)])
    XCTAssertEqual(result, [found(600, 680)])
  }

  func testTheStartOfAnAdIsNeverMovedEarlier() {
    let result = ChapterAds.merge([found(590, 690)], into: [found(600, 700)])
    XCTAssertEqual(result, [found(600, 690)])
  }

  func testAnAdThatTwoChaptersCoverEndsWithTheLastOfThem() {
    let result = ChapterAds.merge(
      [found(600, 690), found(700, 790)], into: [found(600, 800)])
    XCTAssertEqual(result, [found(600, 790)])
  }

  func testNoCutLeavesAnAdUnderTenSeconds() {
    let result = ChapterAds.merge([found(590, 605)], into: [found(600, 700)])
    XCTAssertEqual(result, [found(600, 700)])
  }

  func testTheResultIsInOrder() {
    let result = ChapterAds.merge([found(600, 690)], into: [found(900, 960), found(100, 160)])
    XCTAssertEqual(result.map(\.start), [100, 600, 900])
  }

  func testApplyFindsAndJoinsInOneCall() {
    let spoken = transcript([65: "go to squarespace dot com slash show"])
    let result = ChapterAds.apply(
      chapters, to: [found(600, 705, .unsure)], transcript: spoken, episodeDuration: 800)
    XCTAssertEqual(result.map(\.end), [689.75])
    XCTAssertEqual(
      ChapterAds.apply(chapters, to: [], transcript: spoken, episodeDuration: 800).count, 1)
  }
}
