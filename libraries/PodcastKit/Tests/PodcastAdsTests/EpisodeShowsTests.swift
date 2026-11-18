import XCTest

@testable import PodcastAds

/// Which show each episode is of, kept so the ads of a download can be remembered by show.
final class EpisodeShowsTests: XCTestCase {
  private var url: URL!

  override func setUpWithError() throws {
    url = try temporaryFolder().appendingPathComponent("episode-shows.json")
  }

  override func tearDown() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

  func testAnEpisodesShowIsKeptAndReadBackByANewInstance() {
    let shows = EpisodeShows(url: url)
    XCTAssertNil(shows.show(for: "ep1"))
    shows.remember("show-a", for: "ep1")
    shows.remember("show-b", for: "ep2")
    XCTAssertEqual(shows.show(for: "ep1"), "show-a")
    let again = EpisodeShows(url: url)
    XCTAssertEqual(again.show(for: "ep1"), "show-a")
    XCTAssertEqual(again.show(for: "ep2"), "show-b")
  }

  func testAMissingOrEmptyShowLeavesWhatWasNoted() {
    let shows = EpisodeShows(url: url)
    shows.remember("show-a", for: "ep1")
    shows.remember(nil, for: "ep1")
    shows.remember("", for: "ep1")
    XCTAssertEqual(shows.show(for: "ep1"), "show-a")
    shows.remember("show-b", for: "ep1")
    XCTAssertEqual(shows.show(for: "ep1"), "show-b")
  }

  func testOnlyTheNewestFiveHundredAreKeptAndNotingAgainRenewsAnEpisode() {
    let shows = EpisodeShows(url: url)
    for number in 0..<520 { shows.remember("show", for: "ep\(number)") }
    XCTAssertEqual(shows.count, 500)
    XCTAssertNil(shows.show(for: "ep19"))
    XCTAssertEqual(shows.show(for: "ep20"), "show")
    shows.remember("show", for: "ep20")  // now the newest
    shows.remember("show", for: "ep520")
    XCTAssertEqual(shows.show(for: "ep20"), "show")
    XCTAssertNil(shows.show(for: "ep21"))
    XCTAssertEqual(EpisodeShows(url: url).count, 500)
  }

  func testAMissingOrBrokenFileStartsEmpty() throws {
    XCTAssertEqual(EpisodeShows(url: url).count, 0)
    try Data("not json".utf8).write(to: url)
    let shows = EpisodeShows(url: url)
    XCTAssertEqual(shows.count, 0)
    shows.remember("show-a", for: "ep1")
    XCTAssertEqual(EpisodeShows(url: url).show(for: "ep1"), "show-a")
  }
}
