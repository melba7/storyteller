import XCTest

@testable import PodcastAds

/// The short wait before a never-checked stream starts, so an ad at 0:00 can be skipped first.
final class StartHoldTests: XCTestCase {
  private func wanted(
    skipAds: Bool = true, ownDownload: Bool = true, startsAt: Double = 0, savedAds: Bool = false,
    startsClean: Bool = false
  ) -> Bool {
    StartHold.wanted(
      skipAds: skipAds, playsOwnDownload: ownDownload, startsAt: startsAt, hasSavedAds: savedAds,
      showStartsClean: startsClean)
  }

  func testTheWaitIsWantedOnlyWhenAllFiveThingsHold() {
    XCTAssertTrue(wanted())
    XCTAssertFalse(wanted(skipAds: false), "Skip ads is off")
    XCTAssertFalse(wanted(ownDownload: false), "a plain address or a file, not its own download")
    XCTAssertFalse(wanted(startsAt: 1.0), "it resumes later in the episode")
    XCTAssertFalse(wanted(startsAt: 600))
    XCTAssertFalse(wanted(savedAds: true), "it was checked before")
    XCTAssertFalse(wanted(startsClean: true), "the show starts clean")
  }

  func testAnEpisodeThatStartsInsideTheFirstSecondIsStillHeld() {
    XCTAssertTrue(wanted(startsAt: 0.99))
    XCTAssertTrue(wanted(startsAt: 0.5))
    XCTAssertTrue(wanted(startsAt: -1), "a place before the start is the start")
  }

  func testTheLongestWaitIsThreeSeconds() {
    XCTAssertEqual(StartHold.longest, 3.0)
  }

  func testTheFirstVerdictReleasesTheWaitAtOnce() {
    var hold = StartHold()
    XCTAssertNil(hold.tick(elapsed: 1.0))
    XCTAssertEqual(hold.verdict(), .verdict, "released by the first verdict at 1.4 s")
    XCTAssertEqual(hold.released, .verdict)
  }

  func testWithNoVerdictItIsReleasedAtThreeSecondsAndNotBefore() {
    var hold = StartHold()
    XCTAssertNil(hold.tick(elapsed: 1.4))
    XCTAssertNil(hold.tick(elapsed: 2.99))
    XCTAssertEqual(hold.tick(elapsed: 3.0), .timeout, "released at 3.0 s with no verdict")
    var late = StartHold()
    XCTAssertEqual(late.tick(elapsed: 3.4), .timeout)
  }

  func testTheScanEndingReleasesTheWait() {
    var hold = StartHold()
    XCTAssertEqual(hold.scanEnded(), .scanEnded, "the scan failed or was over before a verdict")
  }

  func testASecondTapOnPlayReleasesTheWaitAtOnce() {
    var hold = StartHold()
    XCTAssertEqual(hold.tappedAgain(), .secondTap)
  }

  func testOnlyTheFirstReasonCountsAndLaterOnesAreIgnored() {
    var hold = StartHold()
    XCTAssertEqual(hold.verdict(), .verdict)
    XCTAssertNil(hold.tick(elapsed: 3.0))
    XCTAssertNil(hold.scanEnded())
    XCTAssertNil(hold.tappedAgain())
    XCTAssertNil(hold.verdict())
    XCTAssertEqual(hold.released, .verdict)
    var tapped = StartHold()
    XCTAssertEqual(tapped.tappedAgain(), .secondTap)
    XCTAssertNil(tapped.verdict())
    XCTAssertEqual(tapped.released, .secondTap)
  }

  func testAWaitThatIsNotOverHasNoReason() {
    XCTAssertNil(StartHold().released)
  }
}
