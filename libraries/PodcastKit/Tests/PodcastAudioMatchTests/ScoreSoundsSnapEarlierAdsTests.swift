import XCTest

@testable import PodcastAudioMatch

/// `ScoreSounds.snap` keeps a pulled start out of every earlier ad, not only the one just before.
final class ScoreSoundsSnapEarlierAdsTests: XCTestCase {
  func testAStartNeverPullsIntoAnEarlierAdThatCoversTheOneBefore() {
    let joints = Joints(times: [100], seconds: 1000, steady: true)
    let spans = [
      SoundSpan(start: 30, end: 120, mayPull: true), SoundSpan(start: 40, end: 60, mayPull: true),
      SoundSpan(start: 150, end: 210, mayPull: true),
    ]
    let moved = ScoreSounds.snap(spans, joints: joints, steadyToo: true)
    XCTAssertEqual(moved[2].start, 150, accuracy: 1e-9)
  }

  func testOnlyASpanThatMayPullIsPulled() {
    let joints = Joints(times: [100], seconds: 1000, steady: true)
    let spans = [
      SoundSpan(start: 130, end: 180, mayPull: true), SoundSpan(start: 300, end: 350),
    ]
    let moved = ScoreSounds.snap(spans, joints: joints, steadyToo: true)
    XCTAssertEqual(moved[0].start, 100, accuracy: 1e-9)
    XCTAssertEqual(moved[1].start, 300, accuracy: 1e-9)
    XCTAssertFalse(SoundSpan(start: 1, end: 2).mayPull)
  }
}
