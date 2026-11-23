import XCTest

@testable import PodcastAudioMatch

final class RepeatScannerTests: XCTestCase {
  /// One anchor step is eight frames: 0.21 s.
  private let tolerance = 8 * Snd.duration + 1e-6
  private let oldIds = Array(0..<6000)  // 156 s of an older episode

  /// A new episode: `before` frames of its own, then frames `from..<from + count` of the older
  /// episode, then 500 frames of its own.
  private func newIds(before: Int, from: Int = 1600, count: Int = 1152) -> [Int] {
    Rep.filler(1, before) + Array(from..<(from + count)) + Rep.filler(2, 500)
  }

  func testASharedStretchIsFoundWhereverItSitsInTheNewEpisode() {
    let found = Rep.scan([Rep.print(oldIds)], newIds(before: 3003))
    XCTAssertEqual(found.count, 1)
    guard found.count == 1 else { return }
    XCTAssertEqual(found[0].start, Snd.time(3003), accuracy: tolerance)
    XCTAssertEqual(found[0].end, Snd.time(3003 + 1152), accuracy: tolerance)
  }

  func testTheAnchorsOfTheOldPrintNeedNotLineUpWithTheNewFile() {
    for phase in 0..<8 {
      let found = Rep.scan(
        [Rep.print(oldIds)], newIds(before: 3003 + phase, from: 1600 + phase, count: 1150))
      XCTAssertEqual(found.count, 1, "phase \(phase)")
      guard let hit = found.first else { continue }
      XCTAssertEqual(hit.start, Snd.time(3003 + phase), accuracy: tolerance, "phase \(phase)")
      XCTAssertEqual(hit.end, Snd.time(3003 + phase + 1150), accuracy: tolerance, "phase \(phase)")
    }
  }

  func testTheSameStretchesWhenFedInOneCallOrInManyPieces() {
    let print = Rep.print(oldIds)
    let ids = newIds(before: 3003)
    let whole = Rep.scan([print], ids, pieces: ids.count)
    XCTAssertEqual(whole.count, 1)
    for pieces in [1, 7, 500] {
      XCTAssertEqual(Rep.scan([print], ids, pieces: pieces), whole, "pieces \(pieces)")
    }
  }

  func testARepeatInTheFirstMinuteIsLeftToTheShowOpening() {
    let print = Rep.print(oldIds)
    XCTAssertTrue(Rep.scan([print], newIds(before: 400)).isEmpty)  // 10 s in
    XCTAssertTrue(Rep.scan([print], newIds(before: 2200)).isEmpty)  // 57 s in
    XCTAssertEqual(Rep.scan([print], newIds(before: 2400)).count, 1)  // 63 s in
  }

  func testTheSameEpisodeNeverMatchesItself() {
    let print = Rep.print(oldIds, episode: "e1")
    XCTAssertTrue(Rep.scan([print], oldIds, episode: "e1").isEmpty)
    // The same file under another id (a second download): the whole of it repeats, so it is
    // the same recording and not a standing plug.
    XCTAssertTrue(Rep.scan([print], oldIds, episode: "e2").isEmpty)
    // The same file under another id, with the first 63 s made different (another ad up front):
    // 60% of it is the older file again, which is more than a plug, so nothing is given. When
    // 40% of it is shared, the stretch is given.
    XCTAssertTrue(Rep.scan([print], Rep.filler(1, 2400) + Array(2400..<6000)).isEmpty)
    XCTAssertEqual(Rep.scan([print], Rep.filler(1, 3600) + Array(3600..<6000)).count, 1)
  }

  func testAStretchOfLessThanEightSecondsGivesNothing() {
    let print = Rep.print(oldIds)
    XCTAssertTrue(Rep.scan([print], newIds(before: 3003, count: 191)).isEmpty)  // 5 s
    XCTAssertTrue(Rep.scan([print], newIds(before: 3003, count: 268)).isEmpty)  // 7 s
    let ten = Rep.scan([print], newIds(before: 3003, count: 383))  // 10 s
    XCTAssertEqual(ten.count, 1)
    XCTAssertEqual(ten.first.map { $0.end - $0.start } ?? 0, 10, accuracy: 2 * tolerance)
  }

  // MARK: bad numbers

  /// The new episode with the frame of each anchor `m` of the shared stretch made different (the
  /// shared stretch starts at the old frame 1600, which is an anchor).
  private func damaged(_ anchors: [Int]) -> [Int] {
    var ids = newIds(before: 3003)
    for m in anchors { ids[3003 + 8 * m] = 900_000 + m }
    return ids
  }

  func testAFewDamagedAnchorsInsideALongMatchStillCount() {
    let found = Rep.scan([Rep.print(oldIds)], damaged([5, 6, 20, 41, 100]))
    XCTAssertEqual(found.count, 1)
    guard found.count == 1 else { return }
    XCTAssertEqual(found[0].start, Snd.time(3003), accuracy: tolerance)
    XCTAssertEqual(found[0].end, Snd.time(3003 + 1152), accuracy: tolerance)
  }

  func testAShortHoleDoesNotSplitTheStretchAndALongOneDoes() {
    let print = Rep.print(oldIds)
    // Five anchors in a row (1.2 s) are gone: one stretch, from end to end.
    let short = Rep.scan([print], damaged(Array(70..<75)))
    XCTAssertEqual(short.count, 1)
    XCTAssertEqual(short.first?.start ?? 0, Snd.time(3003), accuracy: tolerance)
    XCTAssertEqual(short.first?.end ?? 0, Snd.time(3003 + 1152), accuracy: tolerance)
    // Twenty anchors in a row (4 s) are gone: two stretches.
    let long = Rep.scan([print], damaged(Array(60..<80)))
    XCTAssertEqual(long.count, 2)
    XCTAssertEqual(long.first?.end ?? 0, Snd.time(3003 + 8 * 60), accuracy: 2 * tolerance)
    XCTAssertEqual(long.last?.start ?? 0, Snd.time(3003 + 8 * 80), accuracy: 2 * tolerance)
  }

  func testAStretchWithHalfOfItsAnchorsDamagedIsNotARepeat() {
    let found = Rep.scan([Rep.print(oldIds)], damaged(Array(stride(from: 1, to: 144, by: 2))))
    XCTAssertTrue(found.isEmpty)
  }

  // MARK: staying in step

  func testTheMatchMustStayInStepWithinOneAnchorStep() {
    let print = Rep.print(oldIds)
    // Three extra frames in the middle: the offset moves by less than a step, one stretch.
    let small =
      Rep.filler(1, 3003) + Array(1600..<2000) + Rep.filler(3, 3) + Array(2000..<2752)
      + Rep.filler(2, 500)
    let near = Rep.scan([print], small)
    XCTAssertEqual(near.count, 1)
    XCTAssertEqual(near.first?.start ?? 0, Snd.time(3003), accuracy: tolerance)
    XCTAssertEqual(near.first?.end ?? 0, Snd.time(3003 + 1152 + 3), accuracy: tolerance)
    // Twelve extra frames, more than a step: the first 3.9 s are not in step with the rest.
    let medium =
      Rep.filler(1, 3003) + Array(1600..<1750) + Rep.filler(3, 12) + Array(1750..<2752)
      + Rep.filler(2, 500)
    let mid = Rep.scan([print], medium)
    XCTAssertEqual(mid.count, 1)
    XCTAssertEqual(mid.first?.start ?? 0, Snd.time(3003 + 150 + 12), accuracy: tolerance)
    XCTAssertEqual(mid.first?.end ?? 0, Snd.time(3003 + 1152 + 12), accuracy: tolerance)
    // Forty extra frames after 150: the same, far off.
    let big =
      Rep.filler(1, 3003) + Array(1600..<1750) + Rep.filler(3, 40) + Array(1750..<2752)
      + Rep.filler(2, 500)
    let far = Rep.scan([print], big)
    XCTAssertEqual(far.count, 1)
    XCTAssertEqual(far.first?.start ?? 0, Snd.time(3003 + 150 + 40), accuracy: tolerance)
    XCTAssertEqual(far.first?.end ?? 0, Snd.time(3003 + 1152 + 40), accuracy: tolerance)
  }

  // MARK: more than one older episode

  func testStretchesFromTwoOlderEpisodesAreBothGivenAndTheSameOneOnlyOnce() {
    let a = Rep.print(oldIds, episode: "a")
    let b = Rep.print(Array(10_000..<16_000), episode: "b")
    let copyOfA = Rep.print(oldIds, episode: "c")
    let ids =
      Rep.filler(1, 3003) + Array(1600..<2752) + Rep.filler(2, 800) + Array(11_000..<12_152)
      + Rep.filler(3, 500)
    let both = Rep.scan([a, b], ids)
    XCTAssertEqual(both.count, 2)
    guard both.count == 2 else { return }
    XCTAssertEqual(both[0].start, Snd.time(3003), accuracy: tolerance)
    XCTAssertEqual(both[1].start, Snd.time(3003 + 1152 + 800), accuracy: tolerance)
    // Two older episodes hold the first stretch; only `b` holds the second.
    XCTAssertEqual(Rep.scan([a, copyOfA], ids).count, 1)
    XCTAssertEqual(Rep.scan([a, b, copyOfA], ids).count, 2)
  }

  // MARK: bad input and bounded work

  func testBadInputGivesNothingAndDoesNotTrap() {
    var empty = RepeatScanner(older: [], episode: "")
    empty.feed([])
    empty.feed(Snd.frames(Array(0..<100)))
    XCTAssertTrue(empty.finish().isEmpty)
    XCTAssertTrue(empty.finish().isEmpty)

    let hollow = EpisodePrint(episode: "x", date: .nan, frames: -5, seconds: .nan, anchors: [])
    var scanner = RepeatScanner(older: [hollow, Rep.print(oldIds)], episode: "n")
    scanner.feed([])
    XCTAssertTrue(scanner.finish().isEmpty)

    // Frames whose times are not numbers are passed over; what is found is always a real stretch.
    var frames = Snd.frames(newIds(before: 3003))
    for place in stride(from: 3100, to: 3200, by: 3) { frames[place].start = .nan }
    frames[3300].duration = .infinity
    frames[3301].duration = -4
    frames[3302].start = .infinity
    scanner = RepeatScanner(older: [Rep.print(oldIds)], episode: "n")
    scanner.feed(frames)
    for stretch in scanner.finish() {
      XCTAssertTrue(stretch.start.isFinite && stretch.end.isFinite)
      XCTAssertLessThanOrEqual(stretch.start, stretch.end)
    }
  }

  func testTheScannerIsEmptyAfterFinishAndCanScanAnotherFile() {
    var scanner = RepeatScanner(older: [Rep.print(oldIds)], episode: "n")
    let frames = Snd.frames(newIds(before: 3003))
    scanner.feed(frames)
    let first = scanner.finish()
    XCTAssertEqual(first.count, 1)
    XCTAssertTrue(scanner.finish().isEmpty)
    scanner.feed(frames)
    XCTAssertEqual(scanner.finish(), first)
  }

  func testAThreeHourEpisodeScansInBoundedTime() {
    let old = Array(0..<413_000)  // 3 hours of an older episode
    let print = Rep.print(old)
    XCTAssertEqual(print.anchors.count, 51_625)
    let ids =
      Rep.filler(1, 20_000) + Array(100_000..<101_152) + Rep.filler(2, 150_000)
      + Array(300_000..<300_800) + Rep.filler(3, 200_000) + Array(5000..<5480) + Rep.filler(4, 30_000)
    let started = Date()
    let found = Rep.scan([print], ids, pieces: 4096)
    XCTAssertLessThan(Date().timeIntervalSince(started), 30)
    XCTAssertEqual(found.count, 3)
    guard found.count == 3 else { return }
    XCTAssertEqual(found[0].start, Snd.time(20_000), accuracy: tolerance)
    XCTAssertEqual(found[0].end, Snd.time(21_152), accuracy: tolerance)
    XCTAssertEqual(found[1].start, Snd.time(171_152), accuracy: tolerance)
    XCTAssertEqual(found[1].end, Snd.time(171_952), accuracy: tolerance)
    XCTAssertEqual(found[2].start, Snd.time(371_952), accuracy: tolerance)
    XCTAssertEqual(found[2].end, Snd.time(372_432), accuracy: tolerance)
  }
}
