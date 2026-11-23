import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Finding a remembered ad by all of its runs of words, also when its opening was not heard.
final class KnownAdsWholeTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func adWords(_ count: Int = 80) -> [String] { (0..<count).map { "spot\($0)" } }
  private func plain(_ count: Int, from: Int = 0) -> [String] { (from..<(from + count)).map { "talk\($0)" } }

  /// The texts as timed words, half a second each.
  private func timed(_ texts: [String]) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(text: $0.element, start: Double($0.offset) * 0.5, end: Double($0.offset + 1) * 0.5)
    }
  }

  private func known(_ words: [String], scope: String? = nil) -> KnownAds {
    KnownAds(ads: [
      KnownAd(
        showId: "show", advertiser: "Acme", kind: .ad, text: words.joined(separator: " "),
        length: 40, seen: 1, lastSeen: now, scope: scope)
    ])
  }

  /// The ad's words with the ones at `changed` replaced by words that are not in the ad.
  private func reading(_ changed: Range<Int>..., of count: Int = 80) -> [String] {
    adWords(count).enumerated().map { word in
      changed.contains { $0.contains(word.offset) } ? "other\(word.offset)" : word.element
    }
  }

  private func whole(_ hits: [KnownAdHit]) -> [(Double, Double)] {
    hits.compactMap {
      if case .whole(let start, let end) = $0.match { return (start, end) }
      return nil
    }
  }

  func testAnAdWhoseOpeningWasHeardDifferentlyIsFoundAndStartsAFewWordsEarly() {
    let heard = timed(plain(30) + reading(0..<20) + plain(30, from: 500))
    let hits = known(adWords()).find(in: heard, show: "show")
    // The first matching run is the ad's 20th; the match starts five words before it, no more.
    XCTAssertEqual(whole(hits).count, 1)
    XCTAssertEqual(whole(hits).first?.0, Double(30 + 20 - 5) * 0.5)
    XCTAssertEqual(whole(hits).first?.1, 55.0, "the last word of the ad")
  }

  func testTheEndMovesOutByTheWordsThatAreMissingButAtMostFive() {
    let heard = timed(plain(30) + reading(0..<20, 70..<80) + plain(30, from: 500))
    let hits = known(adWords()).find(in: heard, show: "show")
    // The last matching run ends at the ad's 70th word; ten words are missing, five are included.
    XCTAssertEqual(whole(hits).first?.1, Double(30 + 70 + 5) * 0.5)
    XCTAssertEqual(whole(hits).first?.0, Double(30 + 15) * 0.5)
  }

  func testTheEdgesNeverGoOutsideTheTranscript() {
    let heard = timed(reading(0..<8, of: 40) + plain(2, from: 500))
    let atEdges = known(adWords(40)).find(in: heard, show: "show")
    XCTAssertEqual(whole(atEdges).first?.0, 1.5, "word 3 is the first matching word, 5 words back would be -2")
    let clipped = timed(Array(adWords(40).dropLast(3)))
    XCTAssertEqual(whole(known(adWords(40)).find(in: clipped, show: "show")).first?.1, 18.5)
  }

  func testTooFewDifferentRunsAreNotAnAd() {
    // A 40-word ad has 38 runs and needs 23. Words 7 to 30 make 22 runs, words 7 to 31 make 23.
    let words = adWords(40)
    let short = timed(plain(30) + Array(words[7..<31]) + plain(30, from: 500))
    XCTAssertEqual(known(words).find(in: short, show: "show"), [])
    let enough = timed(plain(30) + Array(words[7..<32]) + plain(30, from: 500))
    XCTAssertEqual(known(words).find(in: enough, show: "show").count, 1)
  }

  func testAnAdOfTwelveWordsNeedsEightDifferentRuns() {
    // Its first ten runs open it the old way with six; the sturdy search wants eight.
    let words = adWords(12)  // 10 runs
    let seven = KnownAds.Heard(timed(plain(30) + Array(words[0..<9]) + plain(30, from: 500)))
    XCTAssertEqual(KnownAds.sturdy(words, in: seven).count, 0)
    let eight = KnownAds.Heard(timed(plain(30) + Array(words[0..<10]) + plain(30, from: 500)))
    XCTAssertEqual(KnownAds.sturdy(words, in: eight).count, 1)
  }

  func testTheSameRunsHeardTwiceCountOnce() {
    // Words 7 to 30 of a 40-word ad make 22 different runs; heard twice they are still 22.
    let words = adWords(40)
    let twice = KnownAds.Heard(timed(plain(30) + Array(words[7..<31]) + Array(words[7..<31]) + plain(30, from: 500)))
    XCTAssertEqual(KnownAds.sturdy(words, in: twice).count, 0)
  }

  func testAnAdReadTwiceWithDifferentOpeningsIsFoundTwice() {
    let heard = timed(
      plain(30) + reading(0..<15) + plain(50, from: 500) + reading(0..<25) + plain(30, from: 900))
    XCTAssertEqual(whole(known(adWords()).find(in: heard, show: "show")).count, 2)
  }

  func testNeighbouringBandsGiveOneMatchForOnePlace() {
    // Twelve words of aside in the middle of the ad move the second half by twelve words.
    let texts = plain(30) + Array(adWords()[0..<20]) + plain(12, from: 700) + Array(adWords()[20...])
      + plain(30, from: 500)
    let hits = known(adWords()).find(in: timed(texts), show: "show")
    XCTAssertEqual(hits.count, 1)
  }

  func testAnAdSplitAcrossTwoBandsByAnAsideIsOneMatchWhenItsOpeningWasHeardDifferently() {
    // The opening is misheard, so the opening search finds nothing. An eight-word aside after the
    // 40th word shifts the rest by eight words: the ad's runs lie in two neighbouring bands, and
    // neither band alone holds three fifths of them.
    let words = adWords()
    let texts = plain(35) + reading(0..<20)[0..<40] + plain(8, from: 700) + Array(words[40...])
      + plain(30, from: 500)
    let hits = known(words).find(in: timed(texts), show: "show")
    XCTAssertEqual(whole(hits).count, 1)
    XCTAssertEqual(hits.count, 1)
  }

  func testTheSameStretchFoundAtTwoDistancesIsOneMatch() {
    // An ad made of one block three times over also matches itself shifted by a whole block, in
    // bands far apart from the aligned one. Those matches lie on the same words.
    let block = Array(adWords(40))
    let words = block + block + block
    let heard = KnownAds.Heard(timed(plain(30) + words + plain(30, from: 500)))
    XCTAssertEqual(KnownAds.sturdy(words, in: heard).count, 1)
  }

  func testAnOpeningFoundTheOldWayAndWholeByTheNewWayAreReportedOnce() {
    let heard = timed(plain(30) + adWords() + plain(30, from: 500))
    XCTAssertEqual(known(adWords()).find(in: heard, show: "show").count, 1)
    XCTAssertEqual(whole(known(adWords()).find(in: heard, show: "show")).first?.0, 15.0)
  }

  func testAnEndOfTranscriptInsideTheAdIsStillAnOpening() {
    let heard = timed(plain(30) + Array(adWords().prefix(20)))
    XCTAssertEqual(
      known(adWords()).find(in: heard, show: "show").first?.match, .opening(start: 15.0, expectedEnd: 55.0))
  }

  func testAnAdOfAnotherShowIsNotFoundAndAnAllScopeAdIs() {
    let heard = timed(plain(30) + reading(0..<20) + plain(30, from: 500))
    XCTAssertEqual(known(adWords()).find(in: heard, show: "another"), [])
    XCTAssertEqual(known(adWords(), scope: "all").find(in: heard, show: "another").count, 1)
  }

  func testALongTaughtAdIsFoundAllTheWayToItsEnd() {
    let long = adWords(500)
    let heard = timed(plain(30) + long + plain(30, from: 500))
    XCTAssertEqual(whole(known(long).find(in: heard, show: "show")).first?.1, Double(30 + 500) * 0.5)
  }

  func testAThreeHourTranscriptAgainstAFullLibraryTakesWellUnderTheLimit() {
    var seed: UInt64 = 7
    func next(_ below: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(below))
    }
    let vocabulary = (0..<4000).map { "w\($0)" }
    let talk = (0..<35_000).map { _ in vocabulary[next(vocabulary.count)] }
    var ads: [KnownAd] = []
    for number in 0..<1_500 {
      let words = (0..<600).map { _ in vocabulary[next(vocabulary.count)] }
      ads.append(
        KnownAd(
          showId: number % 2 == 0 ? "show" : "other", advertiser: "A\(number)", kind: .ad,
          text: words.joined(separator: " "), length: 200, seen: 1, lastSeen: now,
          scope: number % 2 == 0 ? nil : "all"))
    }
    let planted = ads[10].words
    let heard = timed(Array(talk[0..<20_000]) + planted + Array(talk[20_000...]))
    let started = Date()
    let hits = KnownAds(ads: ads).find(in: heard, show: "show")
    let seconds = Date().timeIntervalSince(started)
    XCTAssertEqual(whole(hits).count, 1)
    XCTAssertEqual(hits.first?.ad.advertiser, "A10")
    XCTAssertLessThan(seconds, 8, "a test build is slow; a release build needs well under a second")
  }
}
