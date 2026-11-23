import XCTest

@testable import PodcastAudioMatch

/// The rules that keep the scanner from giving what is not a repeat of the show.
final class RepeatScannerGuardsTests: XCTestCase {
  private let tolerance = 8 * Snd.duration + 1e-6

  /// A standing ad of 1152 frames (30 s) that is in no filler.
  private let ad = Array(50_000..<51_152)

  func testAnAdThatPlaysTwiceInOneOlderEpisodeAndOnceInEachOtherIsFound() {
    // The ad starts at a multiple of 8 frames in each older episode, so its frames are anchors in
    // all three prints and one number is in four places (the old rule allowed three at most).
    let a = Rep.print(
      Rep.filler(5, 800) + ad + Rep.filler(6, 2000) + ad + Rep.filler(7, 500), episode: "a", date: 3)
    let b = Rep.print(Rep.filler(8, 1504) + ad + Rep.filler(9, 700), episode: "b", date: 2)
    let c = Rep.print(Rep.filler(10, 2504) + ad + Rep.filler(11, 300), episode: "c", date: 1)
    let new = Rep.filler(1, 3003) + ad + Rep.filler(2, 500)
    for older in [[a, b, c], [a, b], [b, c], [c, b, a]] {
      let found = Rep.scan(older, new)
      XCTAssertEqual(found.count, 1, "\(older.map(\.episode))")
      guard found.count == 1 else { continue }
      XCTAssertEqual(found[0].start, Snd.time(3003), accuracy: tolerance)
      XCTAssertEqual(found[0].end, Snd.time(3003 + 1152), accuracy: tolerance)
    }
  }

  func testASilentStretchIsNotARepeatAndDoesNotSlowTheScan() {
    // Silence: the same frame over and over, 500 frames (13 s) in the older file. In the new file
    // 600 silent frames (16 s) sit in the middle of other audio, after the first minute. Without
    // the rule that a number in many places starts nothing, the silence would be a repeat.
    let print = Rep.print(Array(0..<500) + Array(repeating: 77, count: 500) + Array(600..<1100))
    let middle = Rep.filler(1, 3003) + Array(repeating: 77, count: 600) + Rep.filler(2, 500)
    XCTAssertTrue(Rep.scan([print], middle).isEmpty)
    let started = Date()
    XCTAssertTrue(Rep.scan([print], Array(repeating: 77, count: 60_000)).isEmpty)
    XCTAssertLessThan(Date().timeIntervalSince(started), 20)
  }

  func testTheSameEpisodeIsLeftOutByIdEvenWhenOnlyAPieceOfItIsInTheNewFile() {
    let print = Rep.print(Array(0..<6000), episode: "e1")
    // A 30 s piece of the older file in the middle of other audio: far less than half of it.
    let piece = Rep.filler(1, 3003) + Array(1600..<2752) + Rep.filler(2, 500)
    XCTAssertTrue(Rep.scan([print], piece, episode: "e1").isEmpty)
    XCTAssertEqual(Rep.scan([print], piece, episode: "e2").count, 1)
  }

  func testAStretchOfOverFiveMinutesIsNotGiven() {
    let print = Rep.print(Array(0..<60_000))
    // A shared stretch of 392 s in a file of 21 minutes (31% of it): too long to be an ad.
    let long = Rep.filler(1, 3003) + Array(2000..<17_000) + Rep.filler(2, 30_000)
    XCTAssertTrue(Rep.scan([print], long).isEmpty)
    // One of 280 s is still given.
    let shorter = Rep.filler(1, 3003) + Array(2000..<12_720) + Rep.filler(2, 30_000)
    let found = Rep.scan([print], shorter)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first.map { $0.end - $0.start } ?? 0, 280, accuracy: 2 * tolerance)
  }
}
