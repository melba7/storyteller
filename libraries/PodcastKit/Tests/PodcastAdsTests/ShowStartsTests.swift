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
}
