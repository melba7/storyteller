import XCTest

@testable import PodcastDownloads

/// The episodes the Mac is preparing a copy of (`held`) in the plan for downloading ahead.
final class DownloadAheadHeldTests: XCTestCase {
  private func item(_ id: String) -> DownloadAhead.Item {
    DownloadAhead.Item(id: id, url: "https://cdn.example.com/\(id).mp3", skipAds: true)
  }

  private func entry(_ id: String, ahead: Bool) -> DownloadEntry {
    DownloadEntry(
      episodeId: id, url: "https://cdn.example.com/\(id).mp3", fileExtension: "mp3", state: .queued,
      automatic: true, ahead: ahead)
  }

  private func plan(
    _ upNext: [String], held: Set<String>, playing: String? = "now", entries: [DownloadEntry] = [],
    started: Set<String> = []
  ) -> DownloadAhead.Plan {
    DownloadAhead.plan(
      upNext: upNext.map { item($0) }, playingId: playing, entries: entries, started: started,
      onWiFi: true, lowData: false, phoneFull: false, held: held)
  }

  private let four = ["a", "b", "c", "d"]

  func testAHeldEpisodeIsNotStartedAndTheNextInLineIsFetchedInstead() {
    XCTAssertEqual(plan(four, held: ["a"]).start, ["b", "c"])
    XCTAssertEqual(plan(four, held: ["b"]).start, ["a", "c"])
    XCTAssertEqual(plan(four, held: ["a", "b"]).start, ["c", "d"])
  }

  func testNothingStartsWhenEveryEpisodeIsHeld() {
    XCTAssertEqual(plan(four, held: Set(four)), DownloadAhead.Plan())
  }

  func testWithNothingHeldThePlanIsAsBefore() {
    XCTAssertEqual(plan(four, held: []).start, ["a", "b"])
    XCTAssertEqual(plan(four, held: ["not in up next"]).start, ["a", "b"])
  }

  func testAHeldEpisodeTakesNoPlaceAmongTheTwo() {
    // One ahead download exists already, so there is room for one more: the held "b" is passed
    // over and "c" gets it.
    let entries = [entry("a", ahead: true)]
    XCTAssertEqual(plan(four, held: ["b"], entries: entries).start, ["c"])
  }

  func testAnEpisodeIsFetchedOnceItIsNoLongerHeld() {
    // The wait is over (2 hours passed, or the Mac took the entry back): the next look starts it.
    XCTAssertEqual(plan(four, held: ["a"], started: ["b", "c"]).start, [])
    XCTAssertEqual(plan(["a", "d"], held: []).start, ["a", "d"])
  }

  func testAnAheadDownloadOfAHeldEpisodeIsKeptAdoptedOrDroppedAsAnyOther() {
    let entries = [entry("a", ahead: true)]
    // Still in Up Next: it stays, and keeps its place among the two.
    XCTAssertEqual(
      plan(four, held: ["a"], entries: entries), DownloadAhead.Plan(start: ["b"]))
    // Playing now: it becomes the listener's.
    XCTAssertEqual(plan(["b"], held: ["a"], playing: "a", entries: entries).adopt, ["a"])
    // Gone from Up Next and never started: it is taken back.
    XCTAssertEqual(plan(["b"], held: ["a"], entries: entries).drop, ["a"])
  }
}
