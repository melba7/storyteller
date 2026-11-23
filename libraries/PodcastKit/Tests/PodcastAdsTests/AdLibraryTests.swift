import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The taught ads as the phone gets them, and how they become remembered ads.
final class AdLibraryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// Raw words as a Mac would transcribe them: "Spot0, Spot1! ..." with capitals and punctuation.
  private func raw(_ count: Int = 40) -> String {
    (0..<count).map { "Spot\($0)\($0 % 2 == 0 ? "," : "!")" }.joined(separator: " ")
  }

  private func entry(
    show: String = "show", scope: String = "show", sort: String = "sponsor", who: String = "Acme",
    text: String? = nil, length: Double = 30, seen: Int = 3
  ) -> AdLibraryFile.Entry {
    .init(
      show: show, scope: scope, sort: sort, who: who, text: text ?? raw(), length: length,
      seen: seen)
  }

  private func seeds(_ entries: [AdLibraryFile.Entry]) throws -> KnownAds {
    let data = try JSONEncoder().encode(AdLibraryFile(version: 1, ads: entries))
    return AdLibrary.seeds(from: data, now: now)
  }

  func testAnEntryBecomesARememberedAdWithNormalisedWords() throws {
    let known = try seeds([entry()])
    XCTAssertEqual(known.ads.count, 1)
    let ad = known.ads[0]
    XCTAssertEqual(ad.words, (0..<40).map { "spot\($0)" })
    XCTAssertEqual(ad.showId, "show")
    XCTAssertEqual(ad.scope, "show")
    XCTAssertEqual(ad.advertiser, "Acme")
    XCTAssertEqual(ad.kind, .ad)
    XCTAssertEqual(ad.length, 30)
    XCTAssertEqual(ad.seen, 3)
    XCTAssertEqual(ad.lastSeen, now)
  }

  func testAtMostTheFirstSixHundredWordsAreKept() throws {
    XCTAssertEqual(AdLibrary.mostWords, 600)
    let known = try seeds([entry(text: raw(700))])
    XCTAssertEqual(known.ads.first?.words.count, 600)
    XCTAssertEqual(known.ads.first?.words.last, "spot599")
  }

  func testTheMemorysOwnLearningStaysAtOneHundredFiftyWords() {
    XCTAssertEqual(KnownAds.mostWords, 150)
  }

  func testWordsThatAreOnlyPunctuationAreLeftOut() throws {
    let text = raw(30).replacingOccurrences(of: " ", with: " — \n ")
    XCTAssertEqual(try seeds([entry(text: text)]).ads.first?.words.count, 30)
  }

  func testTheSortNamesMapToKinds() {
    XCTAssertEqual(AdKind(sort: "sponsor"), .ad)
    XCTAssertEqual(AdKind(sort: "network_promo"), .promo)
    XCTAssertEqual(AdKind(sort: "host_ask"), .ownPlug)
    XCTAssertEqual(AdKind(sort: "intro_credits"), .credits)
    XCTAssertNil(AdKind(sort: "jingle"))
    XCTAssertNil(AdKind(sort: ""))
  }

  func testEntriesThatCannotBeUsedAreLeftOut() throws {
    let bad = [
      entry(sort: "jingle"), entry(scope: "world"), entry(show: "", scope: "show"),
      entry(text: raw(24)), entry(length: 7.9), entry(length: 300.1), entry(length: 0),
      entry(length: -30),
    ]
    XCTAssertEqual(try seeds(bad).ads, [])
    XCTAssertEqual(try seeds([entry(show: "", scope: "all")]).ads.count, 1, "all needs no show")
    XCTAssertEqual(try seeds([entry(text: raw(25), length: 8)]).ads.count, 1)
    XCTAssertEqual(try seeds([entry(length: 300)]).ads.count, 1)
  }

  func testALengthThatIsNotFiniteIsLeftOut() {
    // JSON cannot say NaN or infinity, but a number too large for a Double reads as infinity
    // in some decoders; the rule is checked on the entry itself.
    XCTAssertFalse(AdLibrary.usable(length: .infinity))
    XCTAssertFalse(AdLibrary.usable(length: .nan))
    XCTAssertTrue(AdLibrary.usable(length: 8))
  }

  func testSeenBelowOneBecomesOne() throws {
    XCTAssertEqual(try seeds([entry(seen: 0)]).ads.first?.seen, 1)
    XCTAssertEqual(try seeds([entry(seen: -5)]).ads.first?.seen, 1)
  }

  func testOneBadEntryDoesNotSpoilTheFile() throws {
    let good = try String(data: JSONEncoder().encode(entry()), encoding: .utf8)!
    let other = good.replacingOccurrences(of: "Spot", with: "Other")
    let json = """
      {"version":1,"ads":[\(good),{"show":"s","scope":"show","sort":"sponsor","who":"X",\
      "text":5,"length":"long","seen":1},42,{"nonsense":true},\(other)]}
      """
    XCTAssertEqual(AdLibrary.seeds(from: Data(json.utf8), now: now).ads.count, 2)
  }

  func testTheSameAdTwiceCountsOnceWithTheLargerSeen() throws {
    let same = try seeds([entry(seen: 2), entry(text: raw().uppercased(), seen: 7), entry(seen: 4)])
    XCTAssertEqual(same.ads.count, 1)
    XCTAssertEqual(same.ads.first?.seen, 7)
  }

  func testTheSameTextInAnotherShowOrScopeIsAnotherAd() throws {
    let known = try seeds([
      entry(show: "a"), entry(show: "b"), entry(show: "a", scope: "all"),
    ])
    XCTAssertEqual(known.ads.count, 3)
  }

  func testAnotherVersionOrOtherDataGivesNothing() throws {
    let other = try JSONEncoder().encode(AdLibraryFile(version: 2, ads: [entry()]))
    XCTAssertEqual(AdLibrary.seeds(from: other, now: now), KnownAds())
    XCTAssertEqual(AdLibrary.seeds(from: Data("[1,2]".utf8), now: now), KnownAds())
    XCTAssertEqual(AdLibrary.seeds(from: Data(), now: now), KnownAds())
  }

  func testFileName() { XCTAssertEqual(AdLibraryFile.fileName, "ad-library.json") }

  // MARK: End to end

  func testATaughtAllShowsPromoIsFoundWholeInAnotherShowAndBecomesASurePromo() throws {
    let seeds = try seeds([
      entry(show: "", scope: "all", sort: "network_promo", who: "The Network", length: 20)
    ])
    let talk = (0..<30).map { "talk\($0)" }
    let spoken = talk + raw().split(separator: " ").map(String.init) + (30..<60).map { "talk\($0)" }
    let words = spoken.enumerated().map {
      TranscriptWord(text: $0.element, start: Double($0.offset) * 0.5, end: Double($0.offset + 1) * 0.5)
    }
    let hits = KnownAds().find(in: words, show: "another-show", seeds: seeds)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.match, .whole(start: 15, end: 35))
    let use = KnownAdUse.from(hits, words: words)
    XCTAssertEqual(use.ads.count, 1)
    XCTAssertEqual(use.ads.first?.kind, .promo)
    XCTAssertEqual(use.ads.first?.confidence, .sure)
    XCTAssertEqual(use.ads.first?.advertiser, "The Network")
  }
}
