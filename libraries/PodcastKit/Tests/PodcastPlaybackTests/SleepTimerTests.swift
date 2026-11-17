import XCTest

@testable import PodcastPlayback

final class SleepTimerTests: XCTestCase {
  func testCountdownShowsTheTimeLeft() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 15, from: 1000))
    XCTAssertEqual(timer.remaining(at: 1000), 900)
    XCTAssertEqual(timer.remaining(at: 1600), 300)
    XCTAssertFalse(timer.isFinished(at: 1899))
  }

  func testTimeLeftNeverGoesBelowZero() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    XCTAssertEqual(timer.remaining(at: 301), 0)
    XCTAssertTrue(timer.isFinished(at: 300))
    XCTAssertTrue(timer.isFinished(at: 5000))
  }

  func testNoTimerForNothingOrNotANumber() {
    XCTAssertNil(SleepTimer.countdown(minutes: 0, from: 0))
    XCTAssertNil(SleepTimer.countdown(minutes: -5, from: 0))
    XCTAssertNil(SleepTimer.countdown(minutes: .nan, from: 0))
    XCTAssertNil(SleepTimer.countdown(minutes: 5, from: .infinity))
  }

  func testALongTimeIsCutToTwelveHours() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5000, from: 0))
    XCTAssertEqual(timer.remaining(at: 0), 12 * 3600)
  }

  func testAddFiveMinutesWhileRunning() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 10, from: 0))
    let longer = timer.extended(at: 540)
    XCTAssertEqual(longer.remaining(at: 540), 60 + 300)
  }

  func testAddFiveMinutesAfterItRanOutStartsFromNow() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    XCTAssertEqual(timer.extended(at: 400).remaining(at: 400), 300)
  }

  func testExtendingBringsTheVolumeBack() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    XCTAssertEqual(timer.volume(at: 295), 0.5, accuracy: 0.0001)
    XCTAssertEqual(timer.extended(at: 295).volume(at: 295), 1, accuracy: 0.0001)
  }

  func testTheVolumeFadesOverTheLastTenSeconds() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    XCTAssertEqual(timer.volume(at: 0), 1)
    XCTAssertEqual(timer.volume(at: 290), 1, accuracy: 0.0001)
    XCTAssertEqual(timer.volume(at: 292), 0.8, accuracy: 0.0001)
    XCTAssertEqual(timer.volume(at: 295), 0.5, accuracy: 0.0001)
    XCTAssertEqual(timer.volume(at: 299), 0.1, accuracy: 0.0001)
    XCTAssertEqual(timer.volume(at: 300), 0, accuracy: 0.0001)
    XCTAssertEqual(timer.volume(at: 400), 0)
  }

  func testTheFadeStepsOnlyGoDown() throws {
    let timer = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    var last = 1.0
    for half in 570...600 {
      let volume = timer.volume(at: Double(half) / 2)
      XCTAssertLessThanOrEqual(volume, last)
      last = volume
    }
  }

  func testEndOfEpisodeHasNoClockAndNoFade() {
    let timer = SleepTimer.endOfEpisode
    XCTAssertNil(timer.remaining(at: 100))
    XCTAssertFalse(timer.isFinished(at: 1e9))
    XCTAssertEqual(timer.volume(at: 1e9), 1)
    XCTAssertEqual(timer.extended(at: 5), timer)
  }

  func testEndOfEpisodeStopsTheQueueButACountdownDoesNot() throws {
    XCTAssertTrue(SleepTimer.endOfEpisode.stopsBeforeNextEpisode)
    let countdown = try XCTUnwrap(SleepTimer.countdown(minutes: 5, from: 0))
    XCTAssertFalse(countdown.stopsBeforeNextEpisode)
  }

  func testOwnTimeIsWholeMinutesFromOneToTwelveHours() {
    XCTAssertEqual(SleepTimer.customMinutes("20"), 20)
    XCTAssertEqual(SleepTimer.customMinutes(" 90 "), 90)
    XCTAssertEqual(SleepTimer.customMinutes("720"), 720)
    XCTAssertNil(SleepTimer.customMinutes("0"))
    XCTAssertNil(SleepTimer.customMinutes("721"))
    XCTAssertNil(SleepTimer.customMinutes("-3"))
    XCTAssertNil(SleepTimer.customMinutes("1.5"))
    XCTAssertNil(SleepTimer.customMinutes("soon"))
    XCTAssertNil(SleepTimer.customMinutes(""))
  }

  func testThePresetsAreTheSixChoices() {
    XCTAssertEqual(SleepTimer.presetMinutes, [5, 10, 15, 30, 45, 60])
  }
}
