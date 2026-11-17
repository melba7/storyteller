import XCTest

@testable import PodcastPlayback

final class SpeedTests: XCTestCase {
  func testClampsToTheAllowedRange() {
    XCTAssertEqual(Speed.clamped(0.1).value, 0.5, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(7).value, 3.0, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(-2).value, 0.5, accuracy: 0.0001)
  }

  func testRoundsToTheNearestTenth() {
    XCTAssertEqual(Speed.clamped(1.24).value, 1.2, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(1.26).value, 1.3, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(1.0).value, 1.0, accuracy: 0.0001)
  }

  func testNotANumberFallsBackToNormalSpeed() {
    XCTAssertEqual(Speed.clamped(.nan).value, 1.0, accuracy: 0.0001)
  }

  func testStepsByATenthWithinTheRange() {
    XCTAssertEqual(Speed.clamped(1.0).up.value, 1.1, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(1.0).down.value, 0.9, accuracy: 0.0001)
    // Repeated steps do not drift.
    var speed = Speed.clamped(1.0)
    for _ in 0..<7 { speed = speed.up }
    XCTAssertEqual(speed.value, 1.7, accuracy: 0.0001)
  }

  func testStopsAtTheEnds() {
    XCTAssertEqual(Speed.clamped(3.0).up.value, 3.0, accuracy: 0.0001)
    XCTAssertEqual(Speed.clamped(0.5).down.value, 0.5, accuracy: 0.0001)
  }
}

final class SkipTests: XCTestCase {
  func testPocketCastsDefaults() {
    XCTAssertEqual(Skip.back, 10)
    XCTAssertEqual(Skip.ahead, 45)
  }

  func testSeekTargetIsClampedToTheEpisode() {
    XCTAssertEqual(Skip.target(from: 5, by: -10, duration: 100), 0)
    XCTAssertEqual(Skip.target(from: 90, by: 45, duration: 100), 100)
    XCTAssertEqual(Skip.target(from: 50, by: 45, duration: 100), 95)
  }

  func testUnknownDurationOnlyClampsAtZero() {
    XCTAssertEqual(Skip.target(from: 5, by: -10, duration: nil), 0)
    XCTAssertEqual(Skip.target(from: 5, by: 45, duration: nil), 50)
    XCTAssertEqual(Skip.target(from: 5, by: 45, duration: 0), 50)
  }

  func testAbsoluteSeekIsClampedToo() {
    XCTAssertEqual(Skip.clamp(-3, duration: 100), 0)
    XCTAssertEqual(Skip.clamp(300, duration: 100), 100)
    XCTAssertEqual(Skip.clamp(300, duration: nil), 300)
  }
}

final class ResumeRuleTests: XCTestCase {
  func testResumesAtTheSavedPlace() {
    XCTAssertEqual(ResumeRule.start(savedPosition: 120, duration: 600, played: false), 120)
  }

  func testStartsOverWhenPlayed() {
    XCTAssertEqual(ResumeRule.start(savedPosition: 120, duration: 600, played: true), 0)
  }

  func testStartsOverWhenFewerThanTenSecondsWereLeft() {
    XCTAssertEqual(ResumeRule.start(savedPosition: 595, duration: 600, played: false), 0)
    XCTAssertEqual(ResumeRule.start(savedPosition: 591, duration: 600, played: false), 0)
    // Exactly ten seconds left still resumes.
    XCTAssertEqual(ResumeRule.start(savedPosition: 590, duration: 600, played: false), 590)
  }

  func testStartsOverWhenPastTheEnd() {
    XCTAssertEqual(ResumeRule.start(savedPosition: 700, duration: 600, played: false), 0)
  }

  func testUnknownDurationKeepsThePlace() {
    XCTAssertEqual(ResumeRule.start(savedPosition: 120, duration: nil, played: false), 120)
    XCTAssertEqual(ResumeRule.start(savedPosition: 120, duration: 0, played: false), 120)
  }

  func testNegativeOrBrokenPlaceStartsAtZero() {
    XCTAssertEqual(ResumeRule.start(savedPosition: -5, duration: 600, played: false), 0)
    XCTAssertEqual(ResumeRule.start(savedPosition: .nan, duration: 600, played: false), 0)
  }
}

final class PlayedRuleTests: XCTestCase {
  func testPlayingToTheEndCountsAsPlayed() {
    XCTAssertTrue(PlayedRule.isPlayed(position: 100, duration: 600, reachedEnd: true))
  }

  func testStoppingWithinFiveSecondsOfTheEndCountsAsPlayed() {
    XCTAssertTrue(PlayedRule.isPlayed(position: 595, duration: 600, reachedEnd: false))
    XCTAssertTrue(PlayedRule.isPlayed(position: 600, duration: 600, reachedEnd: false))
  }

  func testStoppingEarlierDoesNot() {
    XCTAssertFalse(PlayedRule.isPlayed(position: 594.9, duration: 600, reachedEnd: false))
    XCTAssertFalse(PlayedRule.isPlayed(position: 0, duration: 600, reachedEnd: false))
  }

  func testUnknownDurationNeverCountsWithoutTheEnd() {
    XCTAssertFalse(PlayedRule.isPlayed(position: 595, duration: nil, reachedEnd: false))
    XCTAssertFalse(PlayedRule.isPlayed(position: 595, duration: 0, reachedEnd: false))
  }
}

final class RemoteOwnerTests: XCTestCase {
  func testStartsWithTheBook() {
    XCTAssertEqual(RemoteOwner().current, .book)
  }

  func testAPodcastPlayingTakesTheLockScreen() {
    var owner = RemoteOwner()
    owner.podcastStartedPlaying()
    XCTAssertEqual(owner.current, .podcast)
  }

  func testTheBookPlayingTakesItBack() {
    var owner = RemoteOwner()
    owner.podcastStartedPlaying()
    owner.bookStartedPlaying()
    XCTAssertEqual(owner.current, .book)
  }

  func testPausingChangesNothing() {
    var owner = RemoteOwner()
    owner.podcastStartedPlaying()
    owner.bookPaused()
    XCTAssertEqual(owner.current, .podcast)
    owner.podcastPaused()
    XCTAssertEqual(owner.current, .podcast)
    owner.bookStartedPlaying()
    owner.podcastPaused()
    XCTAssertEqual(owner.current, .book)
    owner.bookPaused()
    XCTAssertEqual(owner.current, .book)
  }
}
