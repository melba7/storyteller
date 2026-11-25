import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The finder "ahead": the Mac's marks of an episode found again in the episode's own words, with
/// the edges placed from the words and never from the marked times.
final class AheadAdsTests: XCTestCase {
  /// Words of an ad: "adone0 adone1 ...". Two ads never share a run of three words.
  private func adWords(_ tag: String = "adone", _ count: Int = 60) -> [String] {
    (0..<count).map { "\(tag)\($0)" }
  }

  /// Plain talk: "talk0 talk1 ...", named from `from` so two stretches never share a run.
  private func talk(_ count: Int, from: Int = 0) -> [String] { (from..<(from + count)).map { "talk\($0)" } }

  /// Words half a second each, one right after the other, from `start`.
  private func timed(_ texts: [String], from start: Double = 0) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(
        text: $0.element, start: start + Double($0.offset) * 0.5,
        end: start + Double($0.offset + 1) * 0.5)
    }
  }

  /// A mark for an ad of `words` whose times (on the Mac's copy) are `start` and `end`.
  private func mark(
    _ words: [String], start: Double, end: Double, kind: AdKind = .ad,
    confidence: AheadMark.Confidence = .high
  ) -> AheadMark {
    AheadMark(
      kind: kind, confidence: confidence, start: start, end: end,
      startWords: words.prefix(40).joined(separator: " "),
      endWords: words.suffix(40).joined(separator: " "))
  }

  private func entry(_ marks: [AheadMark]) -> AheadEntry {
    AheadEntry(feed: "https://f.test/rss", guid: "g1", title: "One", marked: 0, ads: marks)
  }

  /// 100 words of talk (50 s), the 60-word ad (30 s, from 50 s to 80 s), then 100 more words.
  private func episode(ad: [String]? = nil) -> [TranscriptWord] {
    timed(talk(100) + (ad ?? adWords()) + talk(100, from: 100))
  }

  // MARK: The edges come from the words

  func testBothEdgesAreFoundInTheWordsAndPlacedFromTheirTimes() throws {
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode())
    let ad = try XCTUnwrap(found.ads.first)
    XCTAssertEqual(found.ads.count, 1)
    XCTAssertEqual(ad.start, 50, accuracy: 0.3)
    XCTAssertEqual(ad.end, 80, accuracy: 0.3)
    XCTAssertEqual(ad.kind, .ad)
    XCTAssertEqual(ad.source, "ahead")
    XCTAssertEqual(ad.source, ShowTuning.ahead)
    XCTAssertEqual(ad.firstWords, adWords().prefix(AdRules.firstWords).joined(separator: " "))
    XCTAssertTrue(found.asks.isEmpty)
  }

  func testAnotherInsertedAdMovesTheTimesAndTheMarkStillFindsItsAd() throws {
    // The Mac's copy had the ad at 50 to 80 s. This copy has another ad of 43.5 s before it, so the
    // same words are at 93.5 to 123.5 s.
    let other = adWords("other", 87)
    let words = timed(talk(100) + other + adWords() + talk(100, from: 100))
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: words)
    let ad = try XCTUnwrap(found.ads.first)
    XCTAssertEqual(found.ads.count, 1)
    XCTAssertEqual(ad.start, 93.5, accuracy: 0.3)
    XCTAssertEqual(ad.end, 123.5, accuracy: 0.3)
  }

  func testAnAdThatBeginsInTheFirstSecondsBeginsAtZero() throws {
    let words = timed(talk(4) + adWords() + talk(100, from: 100))  // the ad's first word is at 2 s
    let found = AheadAds.find(entry([mark(adWords(), start: 2, end: 32)]), words: words)
    XCTAssertEqual(try XCTUnwrap(found.ads.first).start, 0, accuracy: 0.001)
  }

  func testTheKindOfTheMarkIsTheKindOfTheAd() throws {
    for kind in [AdKind.promo, .ownPlug] {
      let found = AheadAds.find(
        entry([mark(adWords(), start: 50, end: 80, kind: kind)]), words: episode())
      XCTAssertEqual(found.ads.first?.kind, kind)
    }
  }

  func testWordsThatAreSpokenALittleDifferentlyAreStillFound() throws {
    // The phone heard every tenth word of the ad another way.
    var heard = adWords()
    for at in stride(from: 5, to: heard.count, by: 10) { heard[at] = "misheard\(at)" }
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode(ad: heard))
    XCTAssertEqual(found.ads.count, 1)
  }

  // MARK: Claude's confidence

  func testHighAndMediumMarksGiveSureAds() {
    for given in [AheadMark.Confidence.high, .medium] {
      let found = AheadAds.find(
        entry([mark(adWords(), start: 50, end: 80, confidence: given)]), words: episode())
      XCTAssertEqual(found.ads.first?.confidence, .sure, "\(given)")
      XCTAssertEqual(found.ads.count, 1, "\(given)")
      XCTAssertTrue(found.asks.isEmpty, "\(given)")
    }
  }

  func testALowMarkFoundOnBothEdgesIsAQuestionAndNeverASkip() throws {
    // Claude marks a doubtful stretch as low: the phone may ask about it, but must not skip it.
    let found = AheadAds.find(
      entry([mark(adWords(), start: 50, end: 80, confidence: .low)]), words: episode())
    XCTAssertTrue(found.ads.isEmpty, "a low mark never skips")
    let ask = try XCTUnwrap(found.asks.first)
    XCTAssertEqual(found.asks.count, 1)
    XCTAssertEqual(ask.confidence, .unsure)
    XCTAssertEqual(ask.source, "ahead")
    XCTAssertEqual(ask.kind, .ad)
    XCTAssertEqual(ask.start, 50, accuracy: 0.3)
    XCTAssertEqual(ask.end, 80, accuracy: 0.3)
  }

  func testALowMarkFoundOnOneEdgeStillOnlyAsks() throws {
    let heard = Array(adWords().prefix(40)) + adWords("cut", 20)
    let found = AheadAds.find(
      entry([mark(adWords(), start: 50, end: 80, confidence: .low)]), words: episode(ad: heard))
    XCTAssertTrue(found.ads.isEmpty)
    XCTAssertEqual(try XCTUnwrap(found.asks.first).start, 50, accuracy: 0.3)
  }

  func testALowMarkKeepsTheKindOfTheMarkAsAQuestion() {
    for kind in [AdKind.promo, .ownPlug] {
      let found = AheadAds.find(
        entry([mark(adWords(), start: 50, end: 80, kind: kind, confidence: .low)]),
        words: episode())
      XCTAssertEqual(found.asks.first?.kind, kind)
      XCTAssertTrue(found.ads.isEmpty)
    }
  }

  func testALowMarkOfAnAdASureMarkFoundAddsNoQuestionOverIt() {
    let found = AheadAds.find(
      entry([
        mark(adWords(), start: 50, end: 80),
        mark(adWords(), start: 50, end: 80, confidence: .low),
      ]), words: episode())
    XCTAssertEqual(found.ads.count, 1)
    XCTAssertTrue(found.asks.isEmpty, "the question would lie over the skip")
  }

  func testASureAdAndALowOneInTheSameEpisodeAreASkipAndAQuestion() throws {
    let other = adWords("other", 60)
    let words = timed(talk(100) + adWords() + talk(100, from: 100) + other + talk(100, from: 200))
    let found = AheadAds.find(
      entry([
        mark(adWords(), start: 50, end: 80),
        mark(other, start: 130, end: 160, confidence: .low),
      ]), words: words)
    XCTAssertEqual(found.ads.count, 1)
    XCTAssertEqual(try XCTUnwrap(found.ads.first).start, 50, accuracy: 0.3)
    XCTAssertEqual(found.asks.count, 1)
    XCTAssertEqual(try XCTUnwrap(found.asks.first).start, 130, accuracy: 0.3)
  }

  func testTheHeadOfAStreamNeverGetsASkipFromALowMark() {
    // The head scan takes only `ads`: with the whole ad heard, a low mark still gives none.
    let marks = entry([mark(adWords(), start: 50, end: 80, confidence: .low)])
    XCTAssertTrue(AheadAds.find(marks, words: episode().filter { $0.end <= 90 }).ads.isEmpty)
  }

  // MARK: Only one edge

  func testAMissingEndGivesOnlyAnUnsureQuestionAtTheMarkedLength() throws {
    // The last 40 words of the ad are not in this copy (it was cut short).
    let heard = Array(adWords().prefix(40)) + adWords("cut", 20)
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode(ad: heard))
    XCTAssertTrue(found.ads.isEmpty, "a half match never skips")
    let ask = try XCTUnwrap(found.asks.first)
    XCTAssertEqual(found.asks.count, 1)
    XCTAssertEqual(ask.confidence, .unsure)
    XCTAssertEqual(ask.source, "ahead")
    XCTAssertEqual(ask.start, 50, accuracy: 0.3)
    XCTAssertEqual(ask.end - ask.start, 30, accuracy: 0.6)
  }

  func testAMissingStartGivesOnlyAnUnsureQuestionEndingWhereTheEndIs() throws {
    let heard = adWords("cut", 20) + Array(adWords().suffix(40))
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode(ad: heard))
    XCTAssertTrue(found.ads.isEmpty)
    let ask = try XCTUnwrap(found.asks.first)
    XCTAssertEqual(ask.end, 80, accuracy: 0.3)
    XCTAssertEqual(ask.end - ask.start, 30, accuracy: 0.6)
  }

  func testAnAdWhoseWordsAreNotFoundGivesNothingAtAll() {
    let found = AheadAds.find(entry([mark(adWords("gone"), start: 50, end: 80)]), words: episode())
    XCTAssertEqual(found, AheadFound(ads: [], asks: []))
  }

  // MARK: The length

  func testBothEdgesFarApartFromTheMarkedLengthAreNotAnAd() {
    // The ad's words are there, but a long stretch of talk lies between its start and its end
    // (the copy has something else in the middle): 130 s against 30 marked.
    let heard = Array(adWords().prefix(40)) + talk(200, from: 300) + Array(adWords().suffix(40))
    let found = AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode(ad: heard))
    XCTAssertTrue(found.ads.isEmpty)
  }

  func testALengthWithinHalfAndOneAndAHalfTimesTheMarkedLengthIsAccepted() {
    // Marked 30 s: this copy has 55 s (1.83 times) and 20 s (0.67 times) of words.
    let longer = Array(adWords().prefix(40)) + talk(30, from: 300) + Array(adWords().suffix(40))
    XCTAssertTrue(
      AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: episode(ad: longer)).ads
        .isEmpty)
    let shorter = Array(adWords().prefix(40))  // 20 s: the two lists of 40 words overlap
    let marked = AheadMark(
      kind: .ad, confidence: .high, start: 50, end: 80,
      startWords: shorter.joined(separator: " "), endWords: shorter.suffix(30).joined(separator: " "))
    XCTAssertEqual(
      AheadAds.find(entry([marked]), words: episode(ad: shorter)).ads.count, 1)
  }

  /// The band alone lets a 90 s mark take 110 s of words (1.2 times): a quarter of an hour of talk
  /// between two copies of an edge is not an ad, so the copy may hold at most 15 s more than marked.
  func testACopyThatHoldsMoreThanFifteenSecondsOverTheMarkedLengthIsNotAnAd() {
    let ad = adWords("adone", 180)  // 90 s marked
    let near = Array(ad.prefix(40)) + talk(120, from: 300) + Array(ad.suffix(40))  // 100 s of words
    let far = Array(ad.prefix(40)) + talk(140, from: 300) + Array(ad.suffix(40))  // 110 s of words
    XCTAssertEqual(
      AheadAds.find(entry([mark(ad, start: 50, end: 140)]), words: episode(ad: near)).ads.count, 1)
    XCTAssertTrue(
      AheadAds.find(entry([mark(ad, start: 50, end: 140)]), words: episode(ad: far)).ads.isEmpty)
  }

  func testOfTwoPlacesOfTheStartTheOneThatGivesTheMarkedLengthIsTaken() throws {
    // The ad's opening words are said once at 20 s (in a trailer) and again at the ad itself.
    let trailer = Array(adWords().prefix(40))
    let words = timed(talk(40) + trailer + talk(100, from: 100) + adWords() + talk(60, from: 400))
    let found = AheadAds.find(entry([mark(adWords(), start: 90, end: 120)]), words: words)
    let ad = try XCTUnwrap(found.ads.first)
    XCTAssertEqual(found.ads.count, 1)
    XCTAssertEqual(ad.start, 90, accuracy: 0.3)
    XCTAssertEqual(ad.end - ad.start, 30, accuracy: 0.6)
  }

  func testWordsTooFewToFindGiveNothing() {
    let few = Array(adWords().prefix(AheadAds.fewestWords - 1))
    let found = AheadAds.find(
      entry([mark(few, start: 50, end: 80)]), words: episode(ad: few))
    XCTAssertEqual(found, AheadFound(ads: [], asks: []))
  }

  // MARK: Judged stretches and a stream's head

  func testAStretchTheListenerJudgedIsLeftAlone() {
    let marks = entry([mark(adWords(), start: 50, end: 80)])
    let kept = AheadAds.find(marks, words: episode(), judged: [(start: 200, end: 230)])
    XCTAssertEqual(kept.ads.count, 1)
    let judged = AheadAds.find(marks, words: episode(), judged: [(start: 60, end: 70)])
    XCTAssertEqual(judged, AheadFound(ads: [], asks: []))
  }

  func testTheHeadOfAStreamHasTheAdOnlyOnceItsEndWordsHaveArrived() throws {
    let marks = entry([mark(adWords(), start: 50, end: 80)])
    let whole = episode()
    // 65 s heard: the ad's start is there, its end is not.
    let early = whole.filter { $0.end <= 65 }
    let head = AheadAds.find(marks, words: early)
    XCTAssertTrue(head.ads.isEmpty)
    // 90 s heard: the ad is whole.
    let later = AheadAds.find(marks, words: whole.filter { $0.end <= 90 })
    XCTAssertEqual(try XCTUnwrap(later.ads.first).start, 50, accuracy: 0.3)
    XCTAssertEqual(try XCTUnwrap(later.ads.first).end, 80, accuracy: 0.3)
  }

  func testNoWordsOrNoMarksGiveNothing() {
    XCTAssertEqual(AheadAds.find(entry([]), words: episode()), AheadFound(ads: [], asks: []))
    XCTAssertEqual(
      AheadAds.find(entry([mark(adWords(), start: 50, end: 80)]), words: []),
      AheadFound(ads: [], asks: []))
  }

  func testAMarkWithNoLengthIsLeftOut() {
    XCTAssertEqual(
      AheadAds.find(entry([mark(adWords(), start: 80, end: 50)]), words: episode()),
      AheadFound(ads: [], asks: []))
  }

  func testTwoMarksOfOneAdAreTwoEqualAdsAtMost() {
    let marks = entry([
      mark(adWords(), start: 50, end: 80), mark(adWords(), start: 50, end: 80, confidence: .medium),
    ])
    let ads = AdJoin.join(AheadAds.find(marks, words: episode()).ads)
    XCTAssertEqual(ads.count, 1)
  }
}
