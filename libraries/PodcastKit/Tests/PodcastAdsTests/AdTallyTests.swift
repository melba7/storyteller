import XCTest

@testable import PodcastAds

/// The count of what happened with the ads, for each show.
final class AdTallyTests: XCTestCase {
  private func object(_ text: String) throws -> [String: Any] {
    try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  func testEachKindIsCountedForItsShow() {
    var tally = AdTally()
    tally.count(.skipped, show: "s1", seconds: 60, at: 1000)
    tally.count(.skipped, show: "s1", seconds: 30, at: 2000)
    tally.count(.undone, show: "s1", seconds: 30, at: 3000)
    tally.count(.trimmed, show: "s1", at: 4000)
    tally.count(.missed, show: "s2", at: 5000)
    XCTAssertEqual(
      tally.shows["s1"], AdTally.Counts(skipped: 2, undone: 1, trimmed: 1, missed: 0, seconds: 60))
    XCTAssertEqual(
      tally.shows["s2"], AdTally.Counts(skipped: 0, undone: 0, trimmed: 0, missed: 1, seconds: 0))
  }

  func testSinceIsTheFirstCountAndStaysThere() {
    var tally = AdTally()
    XCTAssertNil(tally.since)
    tally.count(.missed, show: "s", at: 1000)
    tally.count(.missed, show: "s", at: 9000)
    XCTAssertEqual(tally.since, 1000)
  }

  func testAnUndoneSkipNeverTakesTheSecondsBelowZero() {
    var tally = AdTally()
    tally.count(.skipped, show: "s", seconds: 20, at: 1)
    tally.count(.undone, show: "s", seconds: 50, at: 2)
    XCTAssertEqual(tally.shows["s"]?.seconds, 0)
  }

  func testAShowThatIsNotKnownCountsUnderTheEmptyId() {
    var tally = AdTally()
    tally.count(.skipped, show: nil, seconds: 10, at: 1)
    tally.count(.skipped, show: "", seconds: 10, at: 2)
    XCTAssertEqual(tally.shows[""]?.skipped, 2)
    XCTAssertEqual(tally.shows.count, 1)
  }

  func testTheJSONTextIsTheContracts() throws {
    let empty = try object(AdTally().json)
    XCTAssertTrue(empty["since"] is NSNull)
    XCTAssertEqual((empty["shows"] as? [String: Any])?.count, 0)

    var tally = AdTally()
    tally.count(.skipped, show: "s1", seconds: 45.5, at: 1234)
    let fields = try object(tally.json)
    XCTAssertEqual(fields["since"] as? Double, 1234)
    let show = try XCTUnwrap((fields["shows"] as? [String: Any])?["s1"] as? [String: Any])
    XCTAssertEqual(Set(show.keys), ["skipped", "undone", "trimmed", "missed", "seconds"])
    XCTAssertEqual(show["skipped"] as? Int, 1)
    XCTAssertEqual(show["seconds"] as? Double, 45.5)
  }

  func testItSavesAndLoadsAndABadFileIsEmpty() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tally-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Podcasts/ad-tally.json")
    XCTAssertEqual(AdTally.load(from: file), AdTally())
    var tally = AdTally()
    tally.count(.skipped, show: "s1", seconds: 12, at: 7)
    try tally.save(to: file)
    XCTAssertEqual(AdTally.load(from: file), tally)
    try Data("not json".utf8).write(to: file)
    XCTAssertEqual(AdTally.load(from: file), AdTally())
  }

  func testAFileWithMissingFieldsStillLoads() {
    let text = #"{"since": 5, "shows": {"s": {"skipped": 2}}}"#
    let tally = AdTally.decode(Data(text.utf8))
    XCTAssertEqual(tally.since, 5)
    XCTAssertEqual(tally.shows["s"]?.skipped, 2)
    XCTAssertEqual(tally.shows["s"]?.seconds, 0)
  }
}
