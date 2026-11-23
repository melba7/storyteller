import XCTest

@testable import PodcastAudioMatch

final class JointSnapTests: XCTestCase {
  private typealias Run = JointFrames.Run

  /// Joints of a file that is neither steady nor busy.
  private func file(_ times: [Double], seconds: Double = 1000) -> Joints {
    Joints(times: times, seconds: seconds, steady: false)
  }

  private func joints(_ frames: [MP3Frame]) -> Joints {
    var finder = JointFinder()
    finder.feed(frames)
    return finder.joints
  }

  private func assertSnap(
    _ start: Double, _ end: Double, _ joints: Joints, previousEnd: Double? = nil,
    nextStart: Double? = nil, gives wanted: (Double, Double), _ note: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let moved = JointSnap.snap(
      start: start, end: end, joints: joints, previousEnd: previousEnd, nextStart: nextStart)
    XCTAssertEqual(moved.start, wanted.0, accuracy: 1e-9, "start \(note)", file: file, line: line)
    XCTAssertEqual(moved.end, wanted.1, accuracy: 1e-9, "end \(note)", file: file, line: line)
  }

  // MARK: From frames to borders

  func testAJointBeforeAFoundStartMovesTheStartOntoItAndAJointAfterAFoundEndMovesTheEnd() {
    let found = joints(JointFrames.spliced())
    let first = JointFrames.time(300)
    let last = JointFrames.time(1300)
    assertSnap(first + 1.4, last - 1.1, found, gives: (first, last))
  }

  func testAJointSixSecondsAwayMovesNothing() {
    let found = joints(JointFrames.spliced())
    let first = JointFrames.time(300)
    let last = JointFrames.time(1300)
    assertSnap(first + 6, last + 6, found, gives: (first + 6, last + 6), "joints before")
    assertSnap(first - 6, last - 6, found, gives: (first - 6, last - 6), "joints after")
  }

  func testAFileFullOfJointsMovesNothing() {
    let found = joints(JointFrames.busy(joints: 40))
    guard found.times.count == 40 else { return XCTFail("\(found.times.count) joints, not 40") }
    XCTAssertFalse(found.usable)
    let start = found.times[5] + 1
    let end = found.times[9] - 1
    assertSnap(start, end, found, gives: (start, end))
  }

  func testASteadyFileMovesNothing() {
    // One bitrate all through, with a joint (an Info tag) in the middle.
    let found = joints(JointFrames.frames([Run(count: 4000), Run(count: 100, tag: true)]))
    guard found.times.count == 1 else { return XCTFail("\(found.times.count) joints, not 1") }
    XCTAssertTrue(found.steady)
    let start = found.times[0] + 1
    assertSnap(start, start + 30, found, gives: (start, start + 30))
  }

  func testASteadyFileMovesABorderOnlyWhenTheCallerAsksForIt() {
    let found = joints(JointFrames.frames([Run(count: 4000), Run(count: 100, tag: true)]))
    guard found.times.count == 1 else { return XCTFail("\(found.times.count) joints, not 1") }
    XCTAssertTrue(found.steady)
    let joint = found.times[0]
    let start = joint + 1
    let end = start + 30
    // The default is what it was: a steady file is not used.
    XCTAssertFalse(found.usable)
    XCTAssertFalse(found.usable(steadyToo: false))
    let kept = JointSnap.snap(start: start, end: end, joints: found)
    XCTAssertEqual(kept.start, start)
    XCTAssertEqual(kept.end, end)
    let sameAgain = JointSnap.snap(start: start, end: end, joints: found, steadyToo: false)
    XCTAssertEqual(sameAgain.start, start)
    XCTAssertEqual(sameAgain.end, end)
    // Asked for, the joint in the window moves the start.
    XCTAssertTrue(found.usable(steadyToo: true))
    let moved = JointSnap.snap(start: start, end: end, joints: found, steadyToo: true)
    XCTAssertEqual(moved.start, joint, accuracy: 1e-9)
    XCTAssertEqual(moved.end, end, accuracy: 1e-9)
  }

  func testABusyOrOverflowedOrEmptyFileIsNotUsedEvenForASteadyAsk() {
    // 39 Info tags in a file of one bitrate: steady, and far over 60 joints an hour.
    let busy = joints(JointFrames.frames((0..<40).map { _ in Run(count: 50, tag: true) }))
    XCTAssertTrue(busy.steady)
    XCTAssertEqual(busy.times.count, 39)
    let files = [
      busy,
      Joints(times: [99.5], seconds: 1000, steady: true, overflowed: true),
      Joints(times: [], seconds: 1000, steady: true),
      Joints(times: [99.5], seconds: .nan, steady: true),
      Joints(times: Array(repeating: 99.5, count: 11), seconds: 600, steady: true),
    ]
    for found in files {
      XCTAssertFalse(found.usable(steadyToo: true))
      let start = found.times.first.map { $0 + 0.5 } ?? 100
      let result = JointSnap.snap(start: start, end: start + 50, joints: found, steadyToo: true)
      XCTAssertEqual(result.start, start)
      XCTAssertEqual(result.end, start + 50)
    }
  }

  func testAFileThatIsNotSteadyIsUsedWhateverTheCallerAsksForSteadyFiles() {
    let found = file([99.5])
    XCTAssertTrue(found.usable)
    XCTAssertTrue(found.usable(steadyToo: false))
    XCTAssertTrue(found.usable(steadyToo: true))
    assertSnap(100, 150, found, gives: (99.5, 150))
    let asked = JointSnap.snap(start: 100, end: 150, joints: found, steadyToo: true)
    XCTAssertEqual(asked.start, 99.5)
    XCTAssertEqual(asked.end, 150)
  }

  // MARK: Windows

  func testTheWindowsAreExactAtTheirEdges() {
    // A start may move 3 s earlier or 1 s later, an end 2 s earlier or 4 s later.
    let starts: [(joint: Double, moves: Bool)] = [
      (97.0, true), (96.99, false), (101.0, true), (101.01, false),
    ]
    for item in starts {
      let result = JointSnap.snap(start: 100, end: 150, joints: file([item.joint]))
      XCTAssertEqual(result.start, item.moves ? item.joint : 100, "start and \(item)")
      XCTAssertEqual(result.end, 150, "start and \(item)")
    }
    let ends: [(joint: Double, moves: Bool)] = [
      (198.0, true), (197.99, false), (204.0, true), (204.01, false),
    ]
    for item in ends {
      let result = JointSnap.snap(start: 100, end: 200, joints: file([item.joint]))
      XCTAssertEqual(result.start, 100, "end and \(item)")
      XCTAssertEqual(result.end, item.moves ? item.joint : 200, "end and \(item)")
    }
  }

  func testTheNearestJointWinsOnEachBorderSeparately() {
    let found = file([97.5, 99.0, 100.4, 148.0, 150.5, 152.0])
    // The start 100 takes 100.4 (0.4 away). The end 150 takes 150.5, not 148.0 or 152.0.
    assertSnap(100, 150, found, gives: (100.4, 150.5))
  }

  func testATieGoesToTheEarlierJointInAnyOrder() {
    assertSnap(100, 150, file([99.5, 100.5]), gives: (99.5, 150))
    assertSnap(100, 150, file([100.5, 99.5]), gives: (99.5, 150))
    // 8.6 and 11.4 are 1.4 away from 10 (the numbers differ in the last digits).
    assertSnap(5, 10, file([11.4, 8.6]), gives: (5, 8.6))
    assertSnap(10, 50, file([10.7, 9.3]), gives: (9.3, 50))
  }

  // MARK: Limits

  func testASnapNeverCrossesTheOtherBorder() {
    // The start window reaches 10.8, but that is after the end, so only the end takes it.
    assertSnap(10, 10.5, file([10.8]), gives: (10, 10.8), "start past the end")
    // The end window reaches 9.8, but that is before the start, so only the start takes it.
    assertSnap(10, 10.5, file([9.8]), gives: (9.8, 10.5), "end before the start")
    // The same joints when the other border cannot take them: nothing moves.
    assertSnap(10, 10.5, file([10.8]), nextStart: 10.6, gives: (10, 10.5), "end held back")
    assertSnap(10, 10.5, file([9.8]), previousEnd: 9.9, gives: (10, 10.5), "start held back")
    // A joint between the borders would be taken by both, which would leave nothing.
    assertSnap(10, 10.5, file([10.3]), gives: (10, 10.5), "both on one joint")
  }

  func testASnapNeverOverlapsTheAdBeforeOrAfter() {
    // The start window reaches 7.0, but the ad before this one ends at 8.0.
    assertSnap(10, 30, file([7.0]), previousEnd: 8.0, gives: (10, 30))
    assertSnap(10, 30, file([7.0, 8.5]), previousEnd: 8.0, gives: (8.5, 30))
    assertSnap(10, 30, file([8.0]), previousEnd: 8.0, gives: (8.0, 30), "touching is no overlap")
    // The end window reaches 23.0, but the next ad starts at 22.0.
    assertSnap(10, 20, file([23.0]), nextStart: 22.0, gives: (10, 20))
    assertSnap(10, 20, file([21.5, 23.0]), nextStart: 22.0, gives: (10, 21.5))
    assertSnap(10, 20, file([22.0]), nextStart: 22.0, gives: (10, 22.0), "touching is no overlap")
  }

  func testNoBorderMovesOutsideTheFile() {
    // A joint before 0 or after the end of the file cannot be reached, whatever its time says.
    assertSnap(1, 50, file([-0.5], seconds: 100), gives: (1, 50))
    assertSnap(1, 50, file([-0.5, 0.0], seconds: 100), gives: (0, 50))
    assertSnap(1, 99, file([100.5], seconds: 100), gives: (1, 99))
    assertSnap(1, 99, file([100.5, 99.9], seconds: 100), gives: (1, 99.9))
  }

  // MARK: Files that are not used

  func testAFileIsUsedUpToSixtyJointsAnHourAndNotBeyond() {
    let times = (0..<200).map { Double($0) }
    // The shortest stretch that is measured is 10 minutes, so 10 joints are allowed in it.
    XCTAssertTrue(Joints(times: Array(times.prefix(10)), seconds: 600, steady: false).usable)
    XCTAssertFalse(Joints(times: Array(times.prefix(11)), seconds: 600, steady: false).usable)
    XCTAssertTrue(Joints(times: Array(times.prefix(10)), seconds: 100, steady: false).usable)
    XCTAssertFalse(Joints(times: Array(times.prefix(11)), seconds: 100, steady: false).usable)
    XCTAssertTrue(Joints(times: Array(times.prefix(120)), seconds: 7200, steady: false).usable)
    XCTAssertFalse(Joints(times: Array(times.prefix(121)), seconds: 7200, steady: false).usable)
  }

  func testAFileThatIsBusySteadyOverflowedOrEmptyMovesNothing() {
    let times = [99.5]
    for found in [
      Joints(times: times, seconds: 1000, steady: true),
      Joints(times: times, seconds: 1000, steady: false, overflowed: true),
      Joints(times: [], seconds: 1000, steady: false),
      Joints(times: Array(repeating: 99.5, count: 11), seconds: 600, steady: false),
    ] {
      XCTAssertFalse(found.usable)
      assertSnap(100, 150, found, gives: (100, 150))
    }
  }

  // MARK: Bad input

  private func same(_ one: Double, _ other: Double) -> Bool {
    (one.isNaN && other.isNaN) || one == other
  }

  func testInputThatCannotBeRightReturnsTheStretchUnchanged() {
    let found = file([99.5, 150.5])
    let bad: [(Double, Double, Double?, Double?)] = [
      (.nan, 150, nil, nil), (100, .nan, nil, nil), (.infinity, 150, nil, nil),
      (100, .infinity, nil, nil), (-.infinity, 150, nil, nil), (-1, 150, nil, nil),
      (100, -5, nil, nil), (150, 100, nil, nil), (100, 100, nil, nil),
      (100, 150, .nan, nil), (100, 150, nil, .nan), (100, 150, -1, nil), (100, 150, nil, -3),
      (100, 150, .infinity, nil), (100, 150, nil, -.infinity),
    ]
    for item in bad {
      let result = JointSnap.snap(
        start: item.0, end: item.1, joints: found, previousEnd: item.2, nextStart: item.3)
      XCTAssertTrue(same(result.start, item.0), "start of \(item)")
      XCTAssertTrue(same(result.end, item.1), "end of \(item)")
    }
  }

  func testJointsThatCannotBeRightAreLeftOut() {
    assertSnap(100, 150, file([.nan, 99.5, .infinity, -.infinity]), gives: (99.5, 150))
    for seconds in [Double.nan, .infinity, 0, -10] {
      let found = Joints(times: [99.5], seconds: seconds, steady: false)
      XCTAssertFalse(found.usable)
      assertSnap(100, 150, found, gives: (100, 150))
    }
  }
}
