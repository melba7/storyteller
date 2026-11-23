import XCTest

@testable import PodcastAudioMatch

final class PrintShelfTests: XCTestCase {
  private func entry(_ show: String, bytes: Int = 70_000, touched: Double) -> PrintShelf.Entry {
    PrintShelf.Entry(show: show, bytes: bytes, touched: touched)
  }

  func testNothingGoesWhileTheShelfIsWithinItsLimits() {
    let shelf = (0..<PrintShelf.maxShows).map { entry("show\($0)", bytes: 70_000, touched: Double($0)) }
    XCTAssertEqual(PrintShelf.evictions(shelf), [])
    XCTAssertEqual(PrintShelf.evictions([]), [])
  }

  func testTheLeastRecentlyTouchedShowsGoFirstWhenThereAreTooMany() {
    var shelf = (0..<(PrintShelf.maxShows + 3)).map { entry("show\($0)", touched: Double($0)) }
    shelf.reverse()  // the order of the list does not matter
    XCTAssertEqual(PrintShelf.evictions(shelf), ["show0", "show1", "show2"])
  }

  func testTheLeastRecentlyTouchedShowsGoWhenThereAreTooManyBytes() {
    // Seven shows of 2 MB: six fit in 12 MB.
    let shelf = (0..<7).map { entry("show\($0)", bytes: 2_000_000, touched: Double($0)) }
    XCTAssertEqual(PrintShelf.evictions(shelf), ["show0"])
    let more = shelf + [entry("big", bytes: 5_000_000, touched: 100)]
    // The big one is the newest; three of the 2 MB shows fit beside it (11 MB).
    XCTAssertEqual(PrintShelf.evictions(more), ["show0", "show1", "show2", "show3"])
  }

  func testOnceAShowIsCutEveryOlderOneGoesToo() {
    let shelf = [
      entry("new", bytes: 5_000_000, touched: 3), entry("middle", bytes: 8_000_000, touched: 2),
      entry("old", bytes: 10_000, touched: 1),
    ]
    XCTAssertEqual(PrintShelf.evictions(shelf), ["old", "middle"])
  }

  func testNumbersThatAreNotNumbersDoNotTrapAndCountAsOldAndEmpty() {
    let shelf = [
      entry("fine", bytes: 100, touched: 5),
      entry("nan", bytes: 100, touched: .nan),
      entry("negative", bytes: -50, touched: 6),
      entry("huge", bytes: Int.max, touched: 1),
    ]
    XCTAssertEqual(PrintShelf.evictions(shelf), ["nan", "huge"])
  }
}
