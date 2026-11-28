import XCTest

@testable import PodcastAds

/// What the Mac's episode map gives as ads of the finder "ahead", and the `map` field of an entry.
final class AheadMapAdsTests: XCTestCase {
  private func mark(_ kind: AdKind, _ start: Double, _ end: Double, _ words: String) -> AheadMark {
    AheadMark(
      kind: kind, confidence: .high, start: start, end: end, startWords: words, endWords: "the end")
  }

  private var entry: AheadEntry {
    AheadEntry(
      feed: "https://show.test/rss", guid: "g1", title: "One", marked: 1_800_000_000,
      ads: [
        mark(.ad, 60, 90, "this show is brought to you by made up mattresses"),
        mark(.promo, 250, 270, "coming up on another show of ours"),
      ])
  }

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: confidence, firstWords: "",
      source: AheadAds.source)
  }

  // MARK: The ads of a carry

  func testACarriedMarkKeepsItsKindItsWordsAndTheFindersName() {
    let ads = AheadAds.carried(
      [MapStretchAd(start: 275, end: 295, kind: "promo", from: 250)], entry: entry)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ads[0].start, 275)
    XCTAssertEqual(ads[0].end, 295)
    XCTAssertEqual(ads[0].kind, .promo)
    XCTAssertEqual(ads[0].confidence, .sure)
    XCTAssertEqual(ads[0].source, "ahead")
    XCTAssertTrue(ads[0].firstWords.hasPrefix("coming up on another show"))
  }

  func testAStretchOnlyThePhoneHasIsAPlainAd() {
    let ads = AheadAds.carried([MapStretchAd(start: 142, end: 167)], entry: entry)
    XCTAssertEqual(ads, [ad(142, 167)])
  }

  func testACarriedMarkAndAnUnmatchedStretchThatTouchAreOneAd() {
    let ads = AheadAds.carried(
      [MapStretchAd(start: 60, end: 90, kind: "ad", from: 60), MapStretchAd(start: 90, end: 115)],
      entry: entry)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ads[0].start, 60)
    XCTAssertEqual(ads[0].end, 115)
  }

  func testAnUnknownKindTheCreditsAndAnEmptyStretchAreLeftOut() {
    let ads = AheadAds.carried(
      [
        MapStretchAd(start: 10, end: 40, kind: "jingle", from: 10),
        MapStretchAd(start: 50, end: 80, kind: "credits", from: 50),
        MapStretchAd(start: 100, end: 100), MapStretchAd(start: .nan, end: 130),
      ], entry: entry)
    XCTAssertTrue(ads.isEmpty)
  }

  // MARK: With what the words found

  func testTheMapsAdTakesThePlaceOfAWordAdItOverlapsAndOthersStay() {
    let words = AheadFound(ads: [ad(58, 93), ad(400, 430)], asks: [ad(61, 80, .unsure), ad(500, 520, .unsure)])
    let made = AheadAds.withMap(words, carried: [ad(60, 90)])
    XCTAssertEqual(made.ads, [ad(60, 90), ad(400, 430)])
    XCTAssertEqual(made.asks, [ad(500, 520, .unsure)])
  }

  func testAMapAdOverAStretchTheListenerJudgedIsNotGiven() {
    let made = AheadAds.withMap(
      AheadFound(), carried: [ad(60, 90), ad(200, 230)], judged: [(start: 70, end: 75)])
    XCTAssertEqual(made.ads, [ad(200, 230)])
  }

  func testNoMapAdsChangeNothing() {
    let words = AheadFound(ads: [ad(58, 93)], asks: [ad(500, 520, .unsure)])
    XCTAssertEqual(AheadAds.withMap(words, carried: []), words)
  }

  func testAnEpisodeWhoseMapCameIsLookedAtOnceMoreWithTheSameMarks() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_800_000_000)
    passes.record(episode: "e2", marked: 1_800_000_000)
    XCTAssertFalse(passes.needs(episode: "e1", marked: 1_800_000_000))
    passes.forget(episode: "e1")
    XCTAssertTrue(passes.needs(episode: "e1", marked: 1_800_000_000))
    XCTAssertFalse(passes.needs(episode: "e2", marked: 1_800_000_000))
  }

  // MARK: The entry's map

  private func file(map: String) -> Data {
    Data(
      #"{"version": 1, "writtenAt": 1, "episodes": [{"feed": "f", "guid": "g1", "title": "t", "marked": 1800000000, "ads": [], "copy": {"file": "prepared/abc.mp3", "sha256": "\#(String(repeating: "a", count: 64))", "bytes": 10}, "map": \#(map)}]}"#
        .utf8)
  }

  func testAnEntryReadsItsMap() {
    let read = AheadFile(data: file(map: #""maps/0123456789ab.json""#))
    XCTAssertEqual(read.episodes.first?.map, "maps/0123456789ab.json")
    XCTAssertNotNil(read.episodes.first?.copy)
  }

  func testAMapThatIsNotAPlainNameInTheMapsFolderIsNoMapAndTheEntryStays() {
    for bad in [
      #""maps/../ahead-ads.json""#, #""prepared/abc.json""#, #""maps/a/b.json""#, #""maps/abc.mp3""#,
      #""maps/.json""#, "7",
    ] {
      let read = AheadFile(data: file(map: bad))
      XCTAssertEqual(read.episodes.count, 1, bad)
      XCTAssertNil(read.episodes.first?.map, bad)
    }
  }

  func testAnEntryWithoutAMapReadsAsBefore() {
    let old = Data(
      #"{"version": 1, "writtenAt": 1, "episodes": [{"feed": "f", "guid": "g1", "title": "t", "marked": 1800000000, "ads": []}]}"#
        .utf8)
    XCTAssertNil(AheadFile(data: old).episodes.first?.map)
  }
}
