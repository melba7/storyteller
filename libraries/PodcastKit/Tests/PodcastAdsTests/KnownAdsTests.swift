import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class KnownAdsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let day = 86_400.0

  /// The words of a 60-word ad, such as "spot0 spot1 ... spot59".
  private func adWords(_ count: Int = 60) -> [String] { (0..<count).map { "spot\($0)" } }

  /// Words of plain talk: "talk0 talk1 ...", named from `from` so two lists never share a run.
  private func plain(_ count: Int, from: Int = 0) -> [String] { (from..<(from + count)).map { "talk\($0)" } }

  /// The texts as timed words, `step` seconds each, one right after the other.
  private func timed(_ texts: [String], step: Double = 0.5) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(text: $0.element, start: Double($0.offset) * step, end: Double($0.offset + 1) * step)
    }
  }

  private func transcript(_ texts: [String], step: Double = 0.5) -> Transcript {
    Transcript(
      identity: TranscriptIdentity(
        locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: "aa"),
      duration: Double(texts.count) * step, lines: [], words: timed(texts, step: step))
  }

  private func file(
    _ ads: [FoundAd], undone: [UndoneAd] = [], coveredUntil: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 600,
      ads: ads, undone: undone, coveredUntil: coveredUntil)
  }

  private func found(
    _ start: Double, _ end: Double, _ confidence: AdConfidence = .sure, name: String = "Acme"
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: name, confidence: confidence, firstWords: "")
  }

  /// A memory that has learned the 60-word ad placed after `lead` words of talk.
  private func learned(lead: Int = 30, show: String = "show") -> KnownAds {
    var known = KnownAds()
    let texts = plain(lead) + adWords() + plain(30, from: 500)
    let start = Double(lead) * 0.5
    known.learn(
      from: file([found(start, start + 30)]), transcript: transcript(texts), show: show, now: now)
    return known
  }

  // MARK: Learning

  func testASureAdIsLearnedWithItsWordsLengthAndShow() {
    let known = learned()
    XCTAssertEqual(known.ads.count, 1)
    XCTAssertEqual(known.ads.first?.words, adWords())
    XCTAssertEqual(known.ads.first?.length, 30)
    XCTAssertEqual(known.ads.first?.advertiser, "Acme")
    XCTAssertEqual(known.ads.first?.showId, "show")
    XCTAssertEqual(known.ads.first?.seen, 1)
    XCTAssertEqual(known.ads.first?.lastSeen, now)
  }

  func testWordsAreKeptInLowerCaseWithoutPunctuationAndAtMostOneHundredFifty() {
    XCTAssertEqual(KnownAds.normalise("Acme.com,"), "acmecom")
    XCTAssertEqual(KnownAds.normalise("It's"), "its")
    XCTAssertNil(KnownAds.normalise("—"))
    var known = KnownAds()
    let long = (0..<200).map { "Word\($0)." }
    known.learn(
      from: file([found(0, 100)]), transcript: transcript(long), show: "show", now: now)
    XCTAssertEqual(known.ads.first?.words.count, 150)
    XCTAssertEqual(known.ads.first?.words.first, "word0")
    XCTAssertEqual(known.ads.first?.words.last, "word149")
  }

  func testAnUnsureUndoneTooShortOrTooLongAdIsNotLearned() {
    let texts = plain(30) + adWords(200) + plain(30, from: 500)
    let ground = transcript(texts, step: 0.25)  // 4 words a second, so even 12 s holds 48 words
    func learn(_ ad: FoundAd, undone: [UndoneAd] = [], trimmed: [Double] = []) -> Int {
      var known = KnownAds()
      known.learn(
        from: file([ad], undone: undone), transcript: ground, show: "show", trimmed: trimmed, now: now)
      return known.ads.count
    }
    XCTAssertEqual(learn(found(10, 40)), 1)
    XCTAssertEqual(learn(found(10, 40, .unsure)), 0)
    XCTAssertEqual(learn(found(10, 40, .guess)), 0)
    XCTAssertEqual(learn(found(10, 40), undone: [UndoneAd(start: 10, end: 40)]), 0)
    XCTAssertEqual(learn(found(10, 40), trimmed: [10.2]), 0)
    XCTAssertEqual(learn(found(10, 22)), 0, "12 s is too short")
    XCTAssertEqual(learn(found(10, 25)), 1, "15 s is the shortest")
    XCTAssertEqual(learn(found(10, 130)), 1, "120 s is the longest")
    XCTAssertEqual(learn(found(10, 140)), 0, "130 s is too long")
  }

  func testAnAdWithTooFewWordsOrFromAPartialFileIsNotLearned() {
    var sparse = KnownAds()  // 20 words in 20 s
    sparse.learn(
      from: file([found(0, 20)]), transcript: transcript(adWords(20), step: 1), show: "show", now: now)
    XCTAssertTrue(sparse.ads.isEmpty)
    var partial = KnownAds()
    partial.learn(
      from: file([found(15, 45)], coveredUntil: 60),
      transcript: transcript(plain(30) + adWords()), show: "show", now: now)
    XCTAssertTrue(partial.ads.isEmpty)
  }

  func testTheSameAdTwiceIsOneEntryThatWasSeenTwice() {
    var known = learned()
    let later = now.addingTimeInterval(3 * day)
    var changed = adWords()
    changed[20] = "different"
    changed[40] = "words"
    known.learn(
      from: file([found(10, 40, name: "")]),
      transcript: transcript(plain(20, from: 700) + changed), show: "show", now: later)
    XCTAssertEqual(known.ads.count, 1)
    XCTAssertEqual(known.ads.first?.seen, 2)
    XCTAssertEqual(known.ads.first?.lastSeen, later)
    XCTAssertEqual(known.ads.first?.words, adWords(), "the first wording stays")
  }

  func testAnotherAdOrTheSameAdOfAnotherShowIsAnotherEntry() {
    var known = learned()
    known.learn(
      from: file([found(0, 30)]),
      transcript: transcript((0..<60).map { "other\($0)" }), show: "show", now: now)
    XCTAssertEqual(known.ads.count, 2)
    var both = learned()
    both.ads += learned(show: "another").ads
    XCTAssertEqual(both.ads.count, 2)
    both.learn(
      from: file([found(15, 45)]),
      transcript: transcript(plain(30) + adWords()), show: "another", now: now)
    XCTAssertEqual(both.ads.map(\.seen).sorted(), [1, 2])
  }

  func testAtMostFortyPerShowFourHundredInAllAndNothingOlderThanSixtyDays() {
    func ad(_ show: String, _ number: Int, daysAgo: Double) -> KnownAd {
      KnownAd(
        showId: show, advertiser: "", kind: .ad, text: "one two three", length: 30, seen: 1,
        lastSeen: now.addingTimeInterval(-daysAgo * day).addingTimeInterval(Double(-number)))
    }
    var known = KnownAds(ads: (0..<45).map { ad("show", $0, daysAgo: 1) })
    known.prune(now: now)
    XCTAssertEqual(known.ads.count, 40)
    XCTAssertEqual(known.ads.last?.lastSeen, ad("show", 39, daysAgo: 1).lastSeen, "the oldest five went")

    var many = KnownAds(ads: (0..<50).flatMap { show in (0..<10).map { ad("show\(show)", $0, daysAgo: 1) } })
    many.prune(now: now)
    XCTAssertEqual(many.ads.count, 400)

    var old = KnownAds(ads: [ad("show", 0, daysAgo: 61), ad("show", 1, daysAgo: 59)])
    old.prune(now: now)
    XCTAssertEqual(old.ads.count, 1)
    XCTAssertEqual(old.ads.first?.lastSeen, ad("show", 1, daysAgo: 59).lastSeen)
  }

  // MARK: Finding

  func testALearnedAdWithTwoWordsChangedIsFoundWholeWithItsWordTimes() {
    let known = learned()
    var changed = adWords()
    changed[20] = "different"
    changed[40] = "words"
    let later = timed(plain(30, from: 900) + changed + plain(30, from: 1000))
    let hits = known.find(in: later, show: "show")
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.match, .whole(start: 15.0, end: 45.0))
    XCTAssertEqual(hits.first?.ad.advertiser, "Acme")
  }

  func testATranscriptThatEndsTwentyWordsIntoTheAdIsAnOpening() {
    let known = learned()
    let cut = timed(plain(30, from: 900) + Array(adWords().prefix(20)))
    XCTAssertEqual(
      known.find(in: cut, show: "show").first?.match, .opening(start: 15.0, expectedEnd: 45.0))
  }

  func testFiveSharedWordsInARowMatchNothing() {
    let known = learned()
    let start = timed(plain(40, from: 900) + Array(adWords().prefix(5)) + plain(40, from: 1000))
    XCTAssertEqual(known.find(in: start, show: "show"), [])
    let middle = timed(plain(40, from: 900) + Array(adWords()[30..<35]) + plain(40, from: 1000))
    XCTAssertEqual(known.find(in: middle, show: "show"), [])
    let atTheEnd = timed(plain(40, from: 900) + Array(adWords().prefix(5)))
    XCTAssertEqual(known.find(in: atTheEnd, show: "show"), [], "too little to call it an opening")
    let sixRuns = timed(plain(40, from: 900) + Array(adWords().prefix(8)))
    XCTAssertEqual(known.find(in: sixRuns, show: "show").count, 1, "six runs open it")
  }

  func testAnotherShowsAdsAreNotLookedFor() {
    let known = learned()
    let later = timed(plain(30, from: 900) + adWords() + plain(30, from: 1000))
    XCTAssertEqual(known.find(in: later, show: "another"), [])
    XCTAssertEqual(known.find(in: later, show: "show").count, 1)
  }

  func testAnAdThatTheHostsCutShortIsFoundAsFarAsItWentIfThreeFifthsAreThere() {
    let known = learned()
    let shortRead = timed(plain(30, from: 900) + Array(adWords().prefix(42)) + plain(60, from: 1000))
    XCTAssertEqual(known.find(in: shortRead, show: "show").first?.match, .whole(start: 15.0, end: 36.0))
    let tooShort = timed(plain(30, from: 900) + Array(adWords().prefix(30)) + plain(60, from: 1000))
    XCTAssertEqual(known.find(in: tooShort, show: "show"), [], "half an ad followed by talk is nothing")
  }

  func testAnAdThatIsReadTwiceIsFoundTwice() {
    let known = learned()
    let twice = timed(plain(20, from: 900) + adWords() + plain(50, from: 1000) + adWords() + plain(20, from: 1100))
    let starts = known.find(in: twice, show: "show").map(\.match.start)
    XCTAssertEqual(starts, [10.0, 65.0])
  }

  func testPunctuationAndCapitalsDoNotStopAMatch() {
    let known = learned()
    let loud = adWords().map { $0.capitalized + "," }
    let hits = known.find(in: timed(plain(10, from: 900) + loud + plain(10, from: 1000)), show: "show")
    XCTAssertEqual(hits.first?.match, .whole(start: 5.0, end: 35.0))
  }

  func testAMemoryWithNothingLearnedOrAnEmptyTranscriptFindsNothing() {
    XCTAssertEqual(KnownAds().find(in: timed(adWords()), show: "show"), [])
    XCTAssertEqual(learned().find(in: [], show: "show"), [])
    let broken = KnownAds(ads: [
      KnownAd(showId: "show", advertiser: "", kind: .ad, text: "", length: 30, seen: 1, lastSeen: now),
      KnownAd(showId: "show", advertiser: "", kind: .ad, text: "one two", length: 30, seen: 1, lastSeen: now),
    ])
    XCTAssertEqual(broken.find(in: timed(adWords()), show: "show"), [])
  }

  // MARK: The file

  func testTheMemoryIsSavedAndReadBack() throws {
    let folder = try temporaryFolder()
    let url = folder.appendingPathComponent("Podcasts/" + KnownAds.fileName)
    let known = learned()
    try known.save(to: url)
    XCTAssertEqual(KnownAds.load(from: url), known)
  }

  func testAMissingBrokenOrNewerFileGivesAnEmptyMemory() throws {
    let folder = try temporaryFolder()
    let url = folder.appendingPathComponent(KnownAds.fileName)
    XCTAssertEqual(KnownAds.load(from: url), KnownAds())
    try Data("not json".utf8).write(to: url)
    XCTAssertEqual(KnownAds.load(from: url), KnownAds())
    var newer = learned()
    newer.version = 99
    try newer.save(to: url)
    XCTAssertEqual(KnownAds.load(from: url), KnownAds())
  }

  func testAFullMemoryFitsInHalfAMegabyte() throws {
    let words = (0..<150).map { _ in "wordy" }.joined(separator: " ")
    let full = KnownAds(
      ads: (0..<400).map {
        KnownAd(
          showId: "show\($0 / 40)", advertiser: "Advertiser", kind: .ad, text: words, length: 60,
          seen: 3, lastSeen: now)
      })
    let url = try temporaryFolder().appendingPathComponent(KnownAds.fileName)
    try full.save(to: url)
    let size = try Data(contentsOf: url).count
    XCTAssertLessThan(size, 500_000)
  }
}
