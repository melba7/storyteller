import XCTest

@testable import PodcastAudioMatch

/// A start that begins late is pulled back onto the latest joint up to a minute before it.
final class JointPullBackTests: XCTestCase {
  private func file(_ times: [Double], steady: Bool = true) -> Joints {
    Joints(times: times, seconds: 1000, steady: steady)
  }

  private func snap(
    _ joints: Joints, start: Double = 100, end: Double = 150, previousEnd: Double? = nil,
    nextStart: Double? = nil, steadyToo: Bool = true, pullBack: Double? = nil
  ) -> (start: Double, end: Double) {
    JointSnap.snap(
      start: start, end: end, joints: joints, previousEnd: previousEnd, nextStart: nextStart,
      steadyToo: steadyToo, pullBack: pullBack, mayPull: true)
  }

  func testALateStartMovesBackToTheLatestJointWithinAMinute() {
    let moved = snap(file([45, 52, 70]))
    XCTAssertEqual(moved.start, 70, accuracy: 1e-9)
    XCTAssertEqual(moved.end, 150, accuracy: 1e-9)
  }

  func testTheLatestJointWinsOverTheNearestOfTheSmallWindowOnlyWhenTheWindowIsEmpty() {
    // 98 is inside the small window, so it is the nearest joint and the pull does not run.
    XCTAssertEqual(snap(file([70, 98])).start, 98, accuracy: 1e-9)
    // 96 is outside it (more than 3 s earlier): the pull takes the latest, which is 96.
    XCTAssertEqual(snap(file([70, 96])).start, 96, accuracy: 1e-9)
  }

  func testTheReachIsExactAtAMinute() {
    XCTAssertEqual(snap(file([40.0])).start, 40.0, accuracy: 1e-9)
    XCTAssertEqual(snap(file([39.99])).start, 100, accuracy: 1e-9)
  }

  func testAJointAfterTheStartDoesNotPullAnything() {
    // 102.5 is later than the window's 1 s, and later than the start: nothing earlier to pull to.
    XCTAssertEqual(snap(file([102.5])).start, 100, accuracy: 1e-9)
  }

  func testThePullIsOffUnlessSteadyFilesAreAskedForOrPullBackIsGiven() {
    let joints = file([60])
    XCTAssertEqual(snap(joints, steadyToo: false).start, 100)
    XCTAssertEqual(snap(file([60], steady: false), steadyToo: false).start, 100)
    XCTAssertEqual(snap(joints, pullBack: 0).start, 100)
    XCTAssertEqual(snap(joints, pullBack: 30).start, 100)
    XCTAssertEqual(snap(joints, pullBack: 45).start, 60, accuracy: 1e-9)
    XCTAssertEqual(snap(file([60], steady: false), steadyToo: false, pullBack: 45).start, 60, accuracy: 1e-9)
  }

  func testItNeverGoesBeforeTheAdBeforeAndDoesNotReachIntoIt() {
    XCTAssertEqual(snap(file([45]), previousEnd: 50).start, 100)
    XCTAssertEqual(snap(file([45, 55]), previousEnd: 50).start, 55, accuracy: 1e-9)
    XCTAssertEqual(snap(file([50]), previousEnd: 50).start, 50, accuracy: 1e-9)
  }

  func testAStartThatTouchesTheAdBeforeIsNotPulled() {
    XCTAssertEqual(snap(file([70]), previousEnd: 100).start, 100)
  }

  func testNothingGoesBeforeZero() {
    let moved = snap(file([-5, 0.5]), start: 30, end: 80)
    XCTAssertEqual(moved.start, 0.5, accuracy: 1e-9)
    XCTAssertEqual(snap(file([-5]), start: 30, end: 80).start, 30)
  }

  func testEndsAreNeverMovedByThePull() {
    let moved = snap(file([45, 120]), end: 150)
    XCTAssertEqual(moved.start, 45, accuracy: 1e-9)
    XCTAssertEqual(moved.end, 150, accuracy: 1e-9)
  }

  func testAFileThatCannotBeUsedIsNotPulled() {
    let busy = Joints(times: [45], seconds: 1000, steady: true, overflowed: true)
    XCTAssertEqual(snap(busy).start, 100)
    XCTAssertEqual(snap(file([]), steadyToo: true).start, 100)
  }

  func testBadNumbersAreGivenBack() {
    XCTAssertEqual(snap(file([45]), pullBack: .nan).start, 100)
    XCTAssertEqual(snap(file([45]), pullBack: -5).start, 100)
  }
}
