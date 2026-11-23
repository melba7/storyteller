import XCTest

@testable import PodcastAudioMatch

/// What may stop the pull-back: the caller's say-so, the stretches the listener judged, and the
/// reach of a trim.
final class JointPullRulesTests: XCTestCase {
  private func file(_ times: [Double]) -> Joints { Joints(times: times, seconds: 1000, steady: true) }

  private func snap(
    _ joints: Joints, start: Double = 100, end: Double = 150, previousEnd: Double? = nil,
    mayPull: Bool = true, judged: [(start: Double, end: Double)] = []
  ) -> Double {
    JointSnap.snap(
      start: start, end: end, joints: joints, previousEnd: previousEnd, steadyToo: true,
      mayPull: mayPull, judged: judged
    ).start
  }

  func testThePullHappensOnlyWhenTheCallerSaysItMay() {
    XCTAssertEqual(snap(file([70])), 70, accuracy: 1e-9)
    XCTAssertEqual(snap(file([70]), mayPull: false), 100)
    // The small window does not need the say-so.
    XCTAssertEqual(snap(file([99]), mayPull: false), 99, accuracy: 1e-9)
  }

  func testAJudgedStretchBeforeTheAdIsAFloorLikeThePreviousAd() {
    let judged = [(start: 60.0, end: 80.0)]
    XCTAssertEqual(snap(file([70])), 70, accuracy: 1e-9)
    XCTAssertEqual(snap(file([70]), judged: judged), 100)
    XCTAssertEqual(snap(file([70, 85]), judged: judged), 85, accuracy: 1e-9)
    // The latest one counts, in whatever order they come.
    XCTAssertEqual(snap(file([70, 85]), judged: [(start: 50, end: 90), (start: 60, end: 80)]), 100)
    // One that ends after the ad's start does not lie before it: see the next test.
    XCTAssertEqual(snap(file([70]), judged: [(start: 200, end: 220)]), 70, accuracy: 1e-9)
  }

  func testNoPullWhenAJudgedStretchOverlapsTheStart() {
    XCTAssertEqual(snap(file([70]), judged: [(start: 90, end: 110)]), 100)
    XCTAssertEqual(snap(file([70]), judged: [(start: 99, end: 101)]), 100)
    // Ending exactly at the start it touches: the floor is the start, so nothing to pull to.
    XCTAssertEqual(snap(file([70]), judged: [(start: 90, end: 100)]), 100)
  }

  func testTheFloorIsTheHigherOfThePreviousAdAndTheJudgedStretch() {
    XCTAssertEqual(snap(file([70, 85]), previousEnd: 90, judged: [(start: 60, end: 80)]), 100)
    XCTAssertEqual(snap(file([70, 85, 95]), previousEnd: 90, judged: [(start: 60, end: 80)]), 95,
      accuracy: 1e-9)
  }

  func testTheTrimReachFollowsThePullDistance() {
    XCTAssertEqual(JointSnap.trimReach(pulled: false), JointSnap.startEarlier + 0.5, accuracy: 1e-9)
    XCTAssertEqual(JointSnap.trimReach(pulled: true), JointSnap.pullBack + 0.5, accuracy: 1e-9)
    XCTAssertGreaterThanOrEqual(JointSnap.trimReach(pulled: true), JointSnap.pullBack)
  }
}
