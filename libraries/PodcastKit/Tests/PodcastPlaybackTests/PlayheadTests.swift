import XCTest

@testable import PodcastPlayback

final class PlayheadTests: XCTestCase {
  func testAPendingSeeksTargetIsThePlace() {
    // A resumed stream reports 0 until the bytes up to the place have arrived.
    XCTAssertEqual(Playhead.place(reported: 0, seekPending: true, seekTarget: 2700), 2700)
    // Once the seek has landed, the clock is right.
    XCTAssertEqual(Playhead.place(reported: 812, seekPending: false, seekTarget: 2700), 812)
  }

  func testTwoQuickSkipsAddUp() {
    let duration = 3600.0
    let first = Playhead.place(reported: 600, seekPending: false, seekTarget: 0)
    let firstTarget = Skip.target(from: first, by: 30, duration: duration)
    XCTAssertEqual(firstTarget, 630)
    // The second press comes before the first seek has landed: the clock still says 600.
    let second = Playhead.place(reported: 600, seekPending: true, seekTarget: firstTarget)
    XCTAssertEqual(Skip.target(from: second, by: 30, duration: duration), 660)
  }

  func testATargetThatIsNotANumberIsIgnored() {
    XCTAssertEqual(Playhead.place(reported: 90, seekPending: true, seekTarget: .nan), 90)
    XCTAssertEqual(Playhead.place(reported: 90, seekPending: true, seekTarget: .infinity), 90)
    XCTAssertEqual(Playhead.place(reported: .nan, seekPending: false, seekTarget: 500), 0)
    XCTAssertEqual(Playhead.place(reported: .nan, seekPending: true, seekTarget: .nan), 0)
  }

  func testAPlaceIsNeverNegative() {
    XCTAssertEqual(Playhead.place(reported: -4, seekPending: false, seekTarget: 0), 0)
    XCTAssertEqual(Playhead.place(reported: 10, seekPending: true, seekTarget: -3), 0)
  }
}
