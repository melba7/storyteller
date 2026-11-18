import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What the head scan does with the remembered ads it finds, and forgetting one for Undo.
final class KnownAdsUseTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func adWords(_ count: Int = 60) -> [String] { (0..<count).map { "spot\($0)" } }
  private func plain(_ count: Int, from: Int = 0) -> [String] { (from..<(from + count)).map { "talk\($0)" } }

  private func timed(_ texts: [String], step: Double = 0.5, from: Double = 0) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(
        text: $0.element, start: from + Double($0.offset) * step, end: from + Double($0.offset + 1) * step)
    }
  }

  private func remembered(
    show: String = "show", words: [String]? = nil, length: Double = 30, seen: Int = 1
  ) -> KnownAd {
    KnownAd(
      showId: show, advertiser: "Acme", kind: .ad, text: (words ?? adWords()).joined(separator: " "),
      length: length, seen: seen, lastSeen: now)
  }

  // MARK: Forgetting

  func testForgettingAnAdRemovesTheStoredAdThatTheRangeIs() {
    var known = KnownAds(ads: [remembered()])
    let words = timed(plain(30) + adWords() + plain(30, from: 500))
    XCTAssertEqual(known.forget(start: 15, end: 45, in: words, show: "show"), 1)
    XCTAssertTrue(known.ads.isEmpty)
    XCTAssertEqual(known.find(in: words, show: "show"), [])
  }

  func testAnAdReadWithSomeWordsChangedIsForgottenToo() {
    var known = KnownAds(ads: [remembered()])
    var changed = adWords()
    changed[20] = "different"
    changed[40] = "words"
    let words = timed(plain(30) + changed + plain(30, from: 500))
    XCTAssertEqual(known.forget(start: 15, end: 45, in: words, show: "show"), 1)
  }

  func testOnlyTheShowsOwnAdAndOnlyTheOneThatMatchesIsForgotten() {
    let other = (0..<60).map { "other\($0)" }
    var known = KnownAds(ads: [
      remembered(), remembered(show: "another"), remembered(words: other),
    ])
    let words = timed(plain(30) + adWords() + plain(30, from: 500))
    XCTAssertEqual(known.forget(start: 15, end: 45, in: words, show: "show"), 1)
    XCTAssertEqual(known.ads.map(\.showId), ["another", "show"])
    XCTAssertEqual(known.ads.last?.words, other)
  }

  func testPlainTalkATinyRangeOrAnUnknownShowForgetsNothing() {
    var known = KnownAds(ads: [remembered()])
    let words = timed(plain(30) + adWords() + plain(30, from: 500))
    XCTAssertEqual(known.forget(start: 0, end: 14, in: words, show: "show"), 0, "plain talk")
    XCTAssertEqual(known.forget(start: 15, end: 16, in: words, show: "show"), 0, "two words")
    XCTAssertEqual(known.forget(start: 15, end: 45, in: words, show: "nobody"), 0, "another show")
    XCTAssertEqual(known.forget(start: 15, end: 45, in: [], show: "show"), 0, "no words")
    XCTAssertEqual(known.ads.count, 1)
  }

  // MARK: Using what was found

  private func hit(
    _ match: KnownAdMatch, seen: Int = 1, length: Double = 30, advertiser: String = "Acme"
  ) -> KnownAdHit {
    var ad = remembered(length: length, seen: seen)
    ad.advertiser = advertiser
    return KnownAdHit(ad: ad, match: match)
  }

  func testAWholeMatchIsASureAdWithTheRememberedAdvertiserAndFirstWords() {
    let words = timed(plain(40) + adWords() + plain(40, from: 500))
    let use = KnownAdUse.from([hit(.whole(start: 20, end: 50))], words: words)
    XCTAssertEqual(use.ads.count, 1)
    let ad = use.ads[0]
    XCTAssertEqual(ad.start, 20)
    XCTAssertEqual(ad.confidence, .sure)
    XCTAssertEqual(ad.advertiser, "Acme")
    XCTAssertEqual(ad.kind, .ad)
    XCTAssertEqual(ad.firstWords, adWords().prefix(14).joined(separator: " "))
    XCTAssertTrue(use.provisional.isEmpty)
    XCTAssertNil(use.jumpTo)
  }

  func testTheEndLandsAQuarterSecondBeforeTheNextWordButNeverPastTheMatch() {
    let contiguous = timed(plain(40) + adWords() + plain(40, from: 500))  // next word starts at 50.0
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 20, end: 50))], words: contiguous).ads[0].end, 49.75)
    // A two second pause: the end stays where the last word ended.
    let paused = timed(plain(40)) + timed(adWords(), from: 20) + timed(plain(40, from: 500), from: 52)
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 20, end: 50))], words: paused).ads[0].end, 50)
    // Nothing after it: the end stays.
    let last = timed(plain(40) + adWords())
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 20, end: 50))], words: last).ads[0].end, 50)
  }

  func testAnAdThatBeginsInTheFirstSixSecondsBeginsAtZero() {
    let words = timed(plain(40) + adWords())
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 4, end: 34))], words: words).ads[0].start, 0)
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 6, end: 36))], words: words).ads[0].start, 0)
    XCTAssertEqual(KnownAdUse.from([hit(.whole(start: 7, end: 37))], words: words).ads[0].start, 7)
  }

  func testAnOpeningSeenOnceOnlyMovesTheNextStepToTenSecondsPastItsExpectedEnd() {
    let use = KnownAdUse.from([hit(.opening(start: 3, expectedEnd: 33), seen: 1)], words: timed(plain(20)))
    XCTAssertEqual(use.ads, [])
    XCTAssertEqual(use.jumpTo, 43)
  }

  func testAnOpeningSeenTwiceIsAlsoSavedAtOnceEndingOneSecondBeforeItsExpectedEnd() {
    // 36 s of words are heard, so the guess may reach the expected end (see the cap below).
    let use = KnownAdUse.from([hit(.opening(start: 10, expectedEnd: 40), seen: 2)], words: timed(plain(72)))
    XCTAssertEqual(use.ads.count, 1)
    XCTAssertEqual(use.ads[0].start, 10)
    XCTAssertEqual(use.ads[0].end, 39)
    XCTAssertEqual(use.ads[0].confidence, .unsure, "its end is a guess")
    XCTAssertEqual(use.provisional, use.ads)
    XCTAssertEqual(use.jumpTo, 50)
  }

  func testAnOpeningIsOnlyGuessedAFewSecondsPastWhatWasHeard() {
    // The remembered read is 90 s long, but the transcript ends at 25 s: the end of the guess is
    // 5 s past that, not at the expected end, so a different, shorter read is not skipped whole.
    let heard = timed(plain(50))  // 25 s of words
    let use = KnownAdUse.from([hit(.opening(start: 0, expectedEnd: 90), seen: 3, length: 90)], words: heard)
    XCTAssertEqual(use.ads.map(\.end), [30])
    XCTAssertEqual(use.ads.map(\.confidence), [.unsure])
    XCTAssertEqual(use.provisional, use.ads)
    XCTAssertEqual(use.jumpTo, 100, "the next step still goes on to the whole read")
    // Never past the expected end: heard 38 s of a read that should end at 40 s.
    let near = KnownAdUse.from([hit(.opening(start: 10, expectedEnd: 40), seen: 2)], words: timed(plain(76)))
    XCTAssertEqual(near.ads.map(\.end), [39])
  }

  func testTheCappedGuessIsDroppedOnceTheNextStepFindsNoMatch() {
    let heard = timed(plain(50))
    let guess = KnownAdUse.from([hit(.opening(start: 0, expectedEnd: 90), seen: 3, length: 90)], words: heard)
    // A longer look hears a different read: the memory finds nothing now.
    let later = KnownAdUse.from([], words: timed(plain(200)))
    XCTAssertEqual(
      KnownAdUse.withoutOutdated(guess.ads, everGuessed: guess.provisional, current: later.provisional), [])
  }

  func testAnOpeningThatBeginsInTheFirstSecondsStartsAtZeroToo() {
    let use = KnownAdUse.from([hit(.opening(start: 3, expectedEnd: 33), seen: 3)], words: timed(plain(60)))
    XCTAssertEqual(use.ads.map(\.start), [0])
    XCTAssertEqual(use.ads.map(\.end), [32])
  }

  func testAnOpeningWithNoRoomForAnAdIsNotSaved() {
    let use = KnownAdUse.from([hit(.opening(start: 10, expectedEnd: 11.5), seen: 5)], words: timed(plain(20)))
    XCTAssertEqual(use.ads, [])
  }

  func testSeveralHitsGiveTheirAdsInOrderAndTheFurthestJump() {
    let words = timed(plain(200))
    let use = KnownAdUse.from(
      [
        hit(.opening(start: 80, expectedEnd: 110), seen: 2),
        hit(.whole(start: 20, end: 50)),
        hit(.opening(start: 60, expectedEnd: 70), seen: 1),
      ], words: words)
    XCTAssertEqual(use.ads.map(\.start), [20, 80])
    XCTAssertEqual(use.jumpTo, 120)
  }

  func testNothingFoundIsNothingToUse() {
    XCTAssertEqual(KnownAdUse.from([], words: []), KnownAdUse())
  }

  // MARK: A guessed end must not outlive the real one

  func testAGuessedAdThatALaterLookReplacedIsDroppedSoTheLongerEndDoesNotWin() {
    let guessed = FoundAd(
      start: 3, end: 39, kind: .ad, advertiser: "Acme", confidence: .unsure, firstWords: "a")
    let whole = FoundAd(
      start: 3, end: 37.75, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "a")
    let rules = FoundAd(
      start: 80, end: 95, kind: .ad, advertiser: "Other", confidence: .sure, firstWords: "b")
    // The file on disk still holds the guess, and the rules' ad.
    let onDisk = [guessed, rules]
    let kept = KnownAdUse.withoutOutdated(onDisk, everGuessed: [guessed], current: [])
    XCTAssertEqual(kept, [rules])
    XCTAssertEqual(AdHeadRules.merge([whole] + kept).first?.end, 37.75)
    XCTAssertEqual(AdHeadRules.merge([whole] + onDisk).first?.end, 39, "what happens without it")
  }

  func testAGuessedAdThatIsStillGuessedStaysAndOthersAreNeverDropped() {
    let guessed = FoundAd(
      start: 3, end: 39, kind: .ad, advertiser: "Acme", confidence: .unsure, firstWords: "a")
    let other = FoundAd(
      start: 80, end: 95, kind: .ad, advertiser: "Other", confidence: .sure, firstWords: "b")
    XCTAssertEqual(
      KnownAdUse.withoutOutdated([guessed, other], everGuessed: [guessed], current: [guessed]),
      [guessed, other])
    XCTAssertEqual(KnownAdUse.withoutOutdated([guessed, other], everGuessed: [], current: []), [guessed, other])
  }
}
