import XCTest

@testable import PodcastDownloads

final class DownloadRulesTests: XCTestCase {
  func testRealIdsAreSafeFolderNames() {
    XCTAssertTrue(DownloadFile.isSafeEpisodeId(UUID().uuidString))
    XCTAssertTrue(DownloadFile.isSafeEpisodeId("episode_1-a"))
  }

  func testIdsThatCouldLeaveTheFolderAreRefused() {
    for bad in ["", "/", "..", ".", "../x", "a/b", "a\\b", ".hidden", "a b", "é", "a\0b",
      String(repeating: "a", count: 101)]
    {
      XCTAssertFalse(DownloadFile.isSafeEpisodeId(bad), "\"\(bad)\"")
    }
  }

  func testTheFileNameIsTheHashAndTheExtension() {
    XCTAssertEqual(DownloadFile.name(sha256: String(repeating: "a", count: 64), fileExtension: "m4a"),
      String(repeating: "a", count: 64) + ".m4a")
    XCTAssertTrue(DownloadFile.isSha256(String(repeating: "0f", count: 32)))
    XCTAssertFalse(DownloadFile.isSha256("../" + String(repeating: "a", count: 61)))
    XCTAssertFalse(DownloadFile.isSha256(String(repeating: "A", count: 64)))
  }

  func testTheExtensionComesFromTheTypeFirst() {
    let url = URL(string: "https://cdn.example.com/ep.mp3")
    XCTAssertEqual(DownloadFile.fileExtension(type: "audio/mpeg", url: url), "mp3")
    XCTAssertEqual(DownloadFile.fileExtension(type: "audio/x-m4a", url: url), "m4a")
    XCTAssertEqual(DownloadFile.fileExtension(type: "Audio/MP4; charset=x", url: url), "m4a")
    XCTAssertEqual(DownloadFile.fileExtension(type: "audio/aac", url: nil), "aac")
  }

  func testTheExtensionFallsBackToTheAddressThenMp3() {
    XCTAssertEqual(
      DownloadFile.fileExtension(
        type: "application/octet-stream", url: URL(string: "https://x.example/a/ep.M4A?token=1")),
      "m4a")
    XCTAssertEqual(
      DownloadFile.fileExtension(type: nil, url: URL(string: "https://x.example/download.php")),
      "mp3")
    XCTAssertEqual(DownloadFile.fileExtension(type: "", url: nil), "mp3")
  }

  func testEveryChosenExtensionIsSafe() {
    for type in ["audio/mpeg", "audio/mp4", "video/mp4", "audio/ogg", "audio/flac", "audio/webm"] {
      XCTAssertTrue(DownloadFile.isSafeExtension(DownloadFile.fileExtension(type: type, url: nil)))
    }
    XCTAssertFalse(DownloadFile.isSafeExtension("../x"))
    XCTAssertFalse(DownloadFile.isSafeExtension(""))
    XCTAssertFalse(DownloadFile.isSafeExtension("MP3"))
  }
}

final class RelaunchTests: XCTestCase {
  private func entry(_ id: String, _ state: DownloadState) -> DownloadEntry {
    DownloadEntry(episodeId: id, url: "https://x.example/\(id).mp3", fileExtension: "mp3", state: state)
  }

  func testAMovingDownloadWithoutATaskFailsWithAReason() {
    XCTAssertEqual(
      Relaunch.action(for: .downloading(bytes: 5, expected: 10), taskIsAlive: false),
      .fail("Stopped, tap to try again"))
  }

  func testAQueuedDownloadWithoutATaskStartsAgain() {
    XCTAssertEqual(Relaunch.action(for: .queued, taskIsAlive: false), .restart)
  }

  func testDownloadsWithATaskCarryOn() {
    XCTAssertEqual(Relaunch.action(for: .downloading(bytes: 5, expected: nil), taskIsAlive: true), .keep)
    XCTAssertEqual(Relaunch.action(for: .queued, taskIsAlive: true), .keep)
  }

  func testFinishedAndFailedEntriesAreLeftAlone() {
    let done = DownloadState.downloaded(file: "f.mp3", sha256: "x", bytes: 1, date: Date())
    XCTAssertEqual(Relaunch.action(for: done, taskIsAlive: false), .keep)
    XCTAssertEqual(Relaunch.action(for: .failed(reason: "no"), taskIsAlive: false), .keep)
  }

  func testThePlanCoversEveryEntry() {
    let plan = Relaunch.plan(
      entries: [
        entry("a", .downloading(bytes: 1, expected: 2)),
        entry("b", .downloading(bytes: 1, expected: 2)),
        entry("c", .queued),
      ], liveEpisodeIds: ["b"])
    XCTAssertEqual(plan["a"], .fail(Relaunch.stoppedReason))
    XCTAssertEqual(plan["b"], .keep)
    XCTAssertEqual(plan["c"], .restart)
  }
}

final class ProgressThrottleTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000)

  func testTheFirstReadingIsReported() {
    var throttle = ProgressThrottle()
    XCTAssertTrue(throttle.shouldReport(bytes: 1, expected: 1000, at: start))
  }

  func testSmallQuickStepsAreHeldBack() {
    var throttle = ProgressThrottle()
    _ = throttle.shouldReport(bytes: 0, expected: 1000, at: start)
    XCTAssertFalse(throttle.shouldReport(bytes: 5, expected: 1000, at: start.addingTimeInterval(0.1)))
    XCTAssertFalse(throttle.shouldReport(bytes: 9, expected: 1000, at: start.addingTimeInterval(0.4)))
  }

  func testHalfASecondLetsAReadingThrough() {
    var throttle = ProgressThrottle()
    _ = throttle.shouldReport(bytes: 0, expected: 1000, at: start)
    XCTAssertTrue(throttle.shouldReport(bytes: 1, expected: 1000, at: start.addingTimeInterval(0.5)))
  }

  func testAOnePercentStepLetsAReadingThroughAtOnce() {
    var throttle = ProgressThrottle()
    _ = throttle.shouldReport(bytes: 0, expected: 1000, at: start)
    XCTAssertTrue(throttle.shouldReport(bytes: 10, expected: 1000, at: start.addingTimeInterval(0.01)))
    // The step is counted from the last reading reported.
    XCTAssertFalse(throttle.shouldReport(bytes: 15, expected: 1000, at: start.addingTimeInterval(0.02)))
  }

  func testAnUnknownSizeReportsOnTheClockOnly() {
    var throttle = ProgressThrottle()
    _ = throttle.shouldReport(bytes: 0, expected: nil, at: start)
    XCTAssertFalse(throttle.shouldReport(bytes: 999_999, expected: nil, at: start.addingTimeInterval(0.2)))
    XCTAssertTrue(throttle.shouldReport(bytes: 999_999, expected: nil, at: start.addingTimeInterval(0.6)))
  }
}

final class DownloadRecoveryTests: XCTestCase {
  func testASwipeAwayResumesWhenIosLeftResumeData() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(urlErrorCode: -999, hasResumeData: true, forceQuit: true)),
      .resume)
  }

  func testASwipeAwayStartsAgainWithoutResumeData() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(urlErrorCode: -999, forceQuit: true)), .restart)
  }

  func testASwipeAwayCarriesOnNoMatterHowOftenItHappened() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(hasResumeData: true, forceQuit: true, attempts: 9)),
      .resume)
  }

  func testNotFoundAndGoneFailForReal() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(httpStatus: 404)),
      .fail("The episode is no longer there (404)"))
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(httpStatus: 410)),
      .fail("The episode is no longer there (410)"))
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(httpStatus: 503)), .fail("The server answered 503"))
  }

  func testAFullPhoneFailsEvenWithResumeData() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(hasResumeData: true, diskFull: true)),
      .fail("The phone is full"))
  }

  func testADroppedConnectionResumesOrRestartsAFewTimesThenFails() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(urlErrorCode: -1005, hasResumeData: true)), .resume)
    XCTAssertEqual(DownloadRecovery.decide(DownloadFailure(urlErrorCode: -1009)), .restart)
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(urlErrorCode: -1001, hasResumeData: true, attempts: 3)),
      .fail("No connection, tap to try again"))
  }

  func testOtherErrorsFail() {
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(urlErrorCode: -1202)),
      .fail("The download failed, tap to try again"))
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure()), .fail("The download failed, tap to try again"))
  }
}

final class NetworkPolicyTests: XCTestCase {
  func testAutomaticDownloadsAlwaysWaitForWifi() {
    XCTAssertTrue(NetworkPolicy.wifiOnly(automatic: true, setting: false))
    XCTAssertTrue(NetworkPolicy.wifiOnly(automatic: true, setting: true))
  }

  func testTheListenersDownloadsFollowTheSwitch() {
    XCTAssertFalse(NetworkPolicy.wifiOnly(automatic: false, setting: false))
    XCTAssertTrue(NetworkPolicy.wifiOnly(automatic: false, setting: true))
  }
}
