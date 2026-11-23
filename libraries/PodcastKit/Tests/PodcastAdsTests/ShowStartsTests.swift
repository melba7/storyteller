import XCTest

@testable import PodcastAds

/// Whether a show's episodes start with an ad, so a show that never does is not waited for.
final class ShowStartsTests: XCTestCase {
  private func ad(_ start: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: start + 30, kind: .ad, advertiser: "Acme", confidence: confidence,
      firstWords: "")
  }

  func testAShowWithFewerThanFiveCheckedEpisodesIsNotKnownToStartClean() {
    var starts = ShowStarts()
    XCTAssertFalse(starts.startsClean(show: "show"))
    for _ in 0..<4 { starts.record(show: "show", hadAdAtStart: false) }
    XCTAssertFalse(starts.startsClean(show: "show"))
    starts.record(show: "show", hadAdAtStart: false)
    XCTAssertTrue(starts.startsClean(show: "show"))
  }

  func testOnlyTheLastFiveEpisodesCount() {
    var starts = ShowStarts()
    starts.record(show: "show", hadAdAtStart: true)
    for _ in 0..<4 { starts.record(show: "show", hadAdAtStart: false) }
    XCTAssertFalse(starts.startsClean(show: "show"), "the ad is one of the last five")
    starts.record(show: "show", hadAdAtStart: false)
    XCTAssertTrue(starts.startsClean(show: "show"), "the ad is the sixth from last")
    starts.record(show: "show", hadAdAtStart: true)
    XCTAssertFalse(starts.startsClean(show: "show"))
  }

  func testEachShowIsItsOwn() {
    var starts = ShowStarts()
    for _ in 0..<5 { starts.record(show: "clean", hadAdAtStart: false) }
    for _ in 0..<5 { starts.record(show: "busy", hadAdAtStart: true) }
    XCTAssertTrue(starts.startsClean(show: "clean"))
    XCTAssertFalse(starts.startsClean(show: "busy"))
    XCTAssertFalse(starts.startsClean(show: "other"))
  }

  func testAnAdThatStartsBeforeThirtySecondsIsAnAdAtTheStart() {
    XCTAssertTrue(ShowStarts.hadAdAtStart([ad(0)]))
    XCTAssertTrue(ShowStarts.hadAdAtStart([ad(29.9)]))
    XCTAssertTrue(ShowStarts.hadAdAtStart([ad(10, .unsure)]), "a skipped ad counts, sure or not")
    XCTAssertFalse(ShowStarts.hadAdAtStart([ad(30)]))
    XCTAssertFalse(ShowStarts.hadAdAtStart([ad(100)]))
    XCTAssertFalse(ShowStarts.hadAdAtStart([ad(10, .guess)]), "a guess is never skipped")
    XCTAssertFalse(ShowStarts.hadAdAtStart([]))
  }

  func testAScanThatDidNotReachSixtySecondsRecordsNothing() {
    var starts = ShowStarts()
    for _ in 0..<5 { starts.record(show: "show", ads: [], reached: 59.9) }
    XCTAssertFalse(starts.startsClean(show: "show"))
    for _ in 0..<5 { starts.record(show: "show", ads: [], reached: 60) }
    XCTAssertTrue(starts.startsClean(show: "show"))
    starts.record(show: "show", ads: [ad(5)], reached: 180)
    XCTAssertFalse(starts.startsClean(show: "show"))
  }

  func testAtMostTwoHundredShowsAreKeptTheOldestRecordGoesFirst() {
    var starts = ShowStarts()
    for number in 0..<205 { starts.record(show: "show\(number)", hadAdAtStart: false) }
    XCTAssertEqual(starts.shows.count, 200)
    XCTAssertFalse(starts.shows.contains { $0.id == "show4" })
    XCTAssertTrue(starts.shows.contains { $0.id == "show5" })
    // Recording again makes a show the newest.
    starts.record(show: "show5", hadAdAtStart: false)
    starts.record(show: "new", hadAdAtStart: false)
    XCTAssertTrue(starts.shows.contains { $0.id == "show5" })
    XCTAssertFalse(starts.shows.contains { $0.id == "show6" })
  }

  func testTheFileIsSavedAndReadBackAndABrokenOneStartsEmpty() throws {
    let url = try temporaryFolder().appendingPathComponent("Podcasts/" + ShowStarts.fileName)
    XCTAssertEqual(ShowStarts.load(from: url), ShowStarts())
    var starts = ShowStarts()
    for _ in 0..<5 { starts.record(show: "show", hadAdAtStart: false) }
    try starts.save(to: url)
    XCTAssertEqual(ShowStarts.load(from: url), starts)
    XCTAssertTrue(ShowStarts.load(from: url).startsClean(show: "show"))
    try Data("not json".utf8).write(to: url)
    XCTAssertEqual(ShowStarts.load(from: url), ShowStarts())
    var newer = starts
    newer.version = 99
    try newer.save(to: url)
    XCTAssertEqual(ShowStarts.load(from: url), ShowStarts())
  }

  // MARK: Where the opening ad ended (file version 2)

  private func adBetween(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure)
    -> FoundAd
  {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence,
      firstWords: "")
  }

  private func fileWith(_ text: String) throws -> URL {
    let url = try temporaryFolder().appendingPathComponent(ShowStarts.fileName)
    try Data(text.utf8).write(to: url)
    return url
  }

  private let versionOne =
    #"{"shows":[{"id":"show","results":[true,true,false,true,false]},"#
    + #"{"id":"clean","results":[false,false,false,false,false]}],"version":1}"#

  func testAVersionOneFileStillReadsWithItsEndsUnknown() throws {
    let starts = ShowStarts.load(from: try fileWith(versionOne))
    XCTAssertEqual(starts.shows.map(\.id), ["show", "clean"])
    XCTAssertEqual(starts.shows[0].results, [true, true, false, true, false])
    XCTAssertNil(starts.shows[0].ends, "the ends of an old file are unknown")
    XCTAssertTrue(starts.startsClean(show: "clean"), "the old bits still answer")
    XCTAssertFalse(starts.startsClean(show: "show"))
    XCTAssertEqual(starts.version, ShowStarts.currentVersion, "it is written again as version 2")
  }

  func testARecordOnAVersionOneShowKeepsTheEndsBesideTheBits() throws {
    var starts = ShowStarts.load(from: try fileWith(versionOne))
    starts.record(show: "show", ads: [adBetween(4, 40)], reached: 180)
    let show = try XCTUnwrap(starts.shows.last)
    XCTAssertEqual(show.id, "show")
    XCTAssertEqual(show.results, [true, false, true, false, true])
    XCTAssertEqual(show.ends, [nil, nil, nil, nil, 40], "old episodes stay unknown")
    starts.record(show: "show", ads: [], reached: 180)
    XCTAssertEqual(starts.shows.last?.ends, [nil, nil, nil, 40, nil])
    XCTAssertEqual(starts.shows.last?.results.count, ShowStarts.kept)
  }

  func testEveryRecordKeepsTheEndsAsLongAsTheResults() {
    var starts = ShowStarts()
    for number in 0..<8 {
      let opens = number % 2 == 0
      starts.record(show: "show", hadAdAtStart: opens, openingEnd: opens ? 30 + Double(number) : 99)
    }
    let show = starts.shows[0]
    // Episodes 3 to 7 are the last five; the ends of those without an ad (99) are left out.
    XCTAssertEqual(show.results, [false, true, false, true, false])
    XCTAssertEqual(show.ends, [nil, 34, nil, 36, nil])
  }

  func testTheOldRecordCallStillWorksAndKnowsNoEnd() {
    var starts = ShowStarts()
    starts.record(show: "show", hadAdAtStart: true)
    XCTAssertEqual(starts.shows[0].results, [true])
    XCTAssertEqual(starts.shows[0].ends, [nil])
  }

  func testTheOpeningEndIsTheEndOfTheFirstBlockOfSkippedAds() {
    // One ad.
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(5, 40)]), 40)
    // The Mac's rule: an ad that starts within 20 seconds of the last one's end joins the block.
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(0, 20), adBetween(30, 52)]), 52)
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(0, 20), adBetween(40, 60)]), 60, "20 s joins")
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(0, 20), adBetween(40.5, 60)]), 20, "20.5 s not")
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(0, 20), adBetween(100, 130)]), 20)
    // Whatever the order of the list, a later ad never extends the block past a gap.
    XCTAssertEqual(
      ShowStarts.openingEnd([adBetween(100, 130), adBetween(0, 20), adBetween(135, 150)]), 20)
    // An unsure ad is skipped too; a guess is not an ad.
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(2, 35, .unsure)]), 35)
    XCTAssertNil(ShowStarts.openingEnd([adBetween(2, 35, .guess)]))
    XCTAssertEqual(ShowStarts.openingEnd([adBetween(2, 20, .guess), adBetween(10, 50)]), 50)
    // No ad at the start, or no ad at all.
    XCTAssertNil(ShowStarts.openingEnd([adBetween(30, 60)]))
    XCTAssertNil(ShowStarts.openingEnd([]))
  }

  func testAnEndIsKeptOnlyWhenTheScanSawTheAdEnd() {
    var starts = ShowStarts()
    starts.record(show: "show", ads: [adBetween(0, 55)], reached: 60)
    XCTAssertEqual(starts.shows[0].ends, [55])
    starts.record(show: "show", ads: [adBetween(0, 60)], reached: 60)
    XCTAssertEqual(starts.shows[0].results, [true, true])
    XCTAssertEqual(starts.shows[0].ends, [55, nil], "an ad to the scan's edge has no known end")
    starts.record(show: "show", ads: [adBetween(0, 200)], reached: 180)
    XCTAssertEqual(starts.shows[0].ends, [55, nil, nil])
    starts.record(show: "show", ads: [adBetween(0, 20)], reached: 59)
    XCTAssertEqual(starts.shows[0].results.count, 3, "a scan under 60 seconds records nothing")
  }

  func testNoBadEndIsStoredAndSavingStillWorks() throws {
    var starts = ShowStarts()
    for bad in [Double.nan, .infinity, -.infinity, -3, 0, 1e300, ShowStarts.latestEnd + 1] {
      starts.record(show: "show", hadAdAtStart: true, openingEnd: bad)
    }
    XCTAssertEqual(starts.shows[0].ends, [nil, nil, nil, nil, nil])
    starts.record(show: "show", ads: [adBetween(0, .nan)], reached: 180)
    starts.record(show: "show", ads: [adBetween(.nan, 20)], reached: 180)
    starts.record(show: "show", hadAdAtStart: true, openingEnd: ShowStarts.latestEnd)
    // The ad that ends at NaN is still an opening ad; the one that starts at NaN is not at the start.
    XCTAssertEqual(starts.shows[0].results, [true, true, true, false, true])
    XCTAssertEqual(starts.shows[0].ends, [nil, nil, nil, nil, ShowStarts.latestEnd])
    let url = try temporaryFolder().appendingPathComponent(ShowStarts.fileName)
    try starts.save(to: url)
    XCTAssertEqual(ShowStarts.load(from: url), starts)
  }

  func testAnEndOnAnEpisodeWithoutAnOpeningAdIsNotKept() {
    var starts = ShowStarts()
    starts.record(show: "show", hadAdAtStart: false, openingEnd: 40)
    XCTAssertEqual(starts.shows[0].ends, [nil])
  }

  func testAVersionTwoFileReadsBackAndAVersionOneReaderIgnoresItsEnds() throws {
    var starts = ShowStarts()
    starts.record(show: "show", ads: [adBetween(0, 40)], reached: 180)
    starts.record(show: "show", ads: [], reached: 180)
    let url = try temporaryFolder().appendingPathComponent(ShowStarts.fileName)
    try starts.save(to: url)
    XCTAssertEqual(ShowStarts.load(from: url), starts)
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(text.contains(#""version":2"#), text)
    XCTAssertTrue(text.contains(#""ends":[40,null]"#), text)
    // What version 1 of the type was: it must read the bits and skip the field it does not know.
    struct VersionOne: Decodable {
      struct Show: Decodable {
        var id: String
        var results: [Bool]
      }
      var version: Int
      var shows: [Show]
    }
    let old = try JSONDecoder().decode(VersionOne.self, from: Data(text.utf8))
    XCTAssertEqual(old.shows.map(\.results), [[true, false]])
  }

  func testEndsInAFileAreCheckedWhenItIsRead() throws {
    let text =
      #"{"version":2,"shows":["#
      + #"{"id":"a","results":[true,true,false,true],"ends":[-5,40,41,1e300]},"#
      + #"{"id":"b","results":[true,true,true,true],"ends":[40]},"#
      + #"{"id":"c","results":[true,true],"ends":[null,35.5]}]}"#
    let starts = ShowStarts.load(from: try fileWith(text))
    XCTAssertEqual(starts.shows[0].ends, [nil, 40, nil, nil], "negative, past a day, no opening")
    XCTAssertNil(starts.shows[1].ends, "a list of the wrong length is not believed")
    XCTAssertEqual(starts.shows[2].ends, [nil, 35.5])
  }

  func testAFileWithTooMuchInItIsCutToTheLimits() throws {
    let shows = (0..<250).map {
      #"{"id":"s\#($0)","results":[true,false,true,false,true,true,false,true],"#
        + #""ends":[1,null,2,null,3,4,null,5]}"#
    }
    let text = #"{"version":2,"shows":["# + shows.joined(separator: ",") + "]}"
    let starts = ShowStarts.load(from: try fileWith(text))
    XCTAssertEqual(starts.shows.count, ShowStarts.mostShows)
    XCTAssertEqual(starts.shows.first?.id, "s50", "the newest shows are kept")
    XCTAssertEqual(starts.shows[0].results, [false, true, true, false, true], "the last five")
    XCTAssertEqual(starts.shows[0].ends, [nil, 3, 4, nil, 5])
  }

  func testADamagedFileReadsAsEmpty() throws {
    for text in [
      "", "{", "not json", "[]", #"{"version":2}"#, #"{"version":2,"shows":"x"}"#,
      #"{"version":2,"shows":[{"id":"a"}]}"#,
      #"{"version":2,"shows":[{"id":"a","results":[true],"ends":"soon"}]}"#,
      #"{"version":2,"shows":[{"id":"a","results":[true],"ends":[NaN]}]}"#,
      #"{"version":0,"shows":[]}"#, #"{"version":3,"shows":[]}"#,
    ] {
      XCTAssertEqual(ShowStarts.load(from: try fileWith(text)), ShowStarts(), text)
    }
    XCTAssertEqual(ShowStarts.load(from: try temporaryFolder()), ShowStarts(), "a folder")
  }

  func testAFileOverTheLimitReadsAsEmptyWhateverItHolds() throws {
    let body = #"{"shows":[{"id":"show","results":[true]}],"version":2}"#
    let exactly = body + String(repeating: " ", count: ShowStarts.maxBytes - body.utf8.count)
    let one = try fileWith(exactly)
    XCTAssertEqual(ShowStarts.load(from: one).shows.map(\.id), ["show"], "at the limit it is read")
    let over = try fileWith(exactly + " ")
    XCTAssertEqual(ShowStarts.load(from: over), ShowStarts(), "one byte over the limit it is not")
  }
}
