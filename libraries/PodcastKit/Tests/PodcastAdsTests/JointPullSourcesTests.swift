import XCTest

@testable import PodcastAds

/// Which ads the pull-back of a late start may apply to: only those found from the transcript's
/// words, and only by a finder the rule knows by name.
final class JointPullSourcesTests: XCTestCase {
  func testTheWordFindersMayPull() {
    for name in [ShowTuning.repeatWords, ShowTuning.meaning, "word-model"] {
      XCTAssertTrue(JointPull.allows(source: name), name)
    }
  }

  func testNothingElseMayPull() {
    // Sound finders, the listener's answers, and a name the rule does not know.
    for name in [
      ShowTuning.ownSound, ShowTuning.repeatSound, AdAsking.source, "known-ad", "apple", "chapter",
      "", "something-new",
    ] {
      XCTAssertFalse(JointPull.allows(source: name), name)
    }
  }

  func testAnAdWithNoSourceMayNotPullBecauseApplesModelChaptersAndMemoryHaveNoneEither() {
    XCTAssertFalse(JointPull.allows(source: nil))
  }

  private func ad(_ start: Double, _ source: String?) -> FoundAd {
    var one = foundAd(start, start + 30)
    one.source = source
    return one
  }

  func testTheScorerHandsTheSaySoToTheMoveOfEachSpan() {
    var byStart: [Double: Bool] = [:]
    _ = ScoreAds.moved([ad(300, nil), ad(100, ShowTuning.repeatWords), ad(200, ShowTuning.ownSound)]) {
      spans in
      for span in spans { byStart[span.start] = span.mayPull }
      return spans
    }
    XCTAssertEqual(byStart, [100: true, 200: false, 300: false])
  }
}
