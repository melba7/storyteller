import XCTest

@testable import PodcastPlayback

final class ListeningStatsTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Noon UTC on 2026-11-17 plus a number of days.
  private func date(daysAfter days: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_794_916_800 + Double(days) * 86_400)
  }

  func testTheDayKeyIsTheLocalDay() {
    XCTAssertEqual(ListeningStats.dayKey(date(), calendar: calendar), "2026-11-17")
    var tokyo = calendar
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    // 20:00 UTC is already the next morning in Tokyo.
    let late = date().addingTimeInterval(8 * 3600)
    XCTAssertEqual(ListeningStats.dayKey(late, calendar: calendar), "2026-11-17")
    XCTAssertEqual(ListeningStats.dayKey(late, calendar: tokyo), "2026-11-18")
  }

  func testListenedTimeCountsInTheTotalAndTheDay() {
    var stats = ListeningStats()
    stats.addListened(60, at: date(), calendar: calendar)
    stats.addListened(30, at: date(), calendar: calendar)
    stats.addListened(10, at: date(daysAfter: 1), calendar: calendar)
    XCTAssertEqual(stats.listened, 100)
    XCTAssertEqual(stats.days["2026-11-17"], 90)
    XCTAssertEqual(stats.days["2026-11-18"], 10)
  }

  func testEachSavingHasItsOwnTotal() {
    var stats = ListeningStats()
    for (index, category) in StatsCategory.allCases.enumerated() {
      stats.addSaved(category, Double(index + 1))
    }
    XCTAssertEqual(stats.saved(.speed), 1)
    XCTAssertEqual(stats.saved(.skipping), 2)
    XCTAssertEqual(stats.saved(.trim), 3)
    XCTAssertEqual(stats.saved(.ads), 4)
    XCTAssertEqual(stats.saved(.chapters), 5)
    XCTAssertEqual(stats.totalSaved, 15)
  }

  func testBadNumbersAreIgnored() {
    var stats = ListeningStats()
    for bad in [Double.nan, .infinity, -.infinity, -5, 0] {
      stats.addListened(bad, at: date(), calendar: calendar)
      stats.addSaved(.ads, bad)
    }
    XCTAssertEqual(stats, ListeningStats())
  }

  func testTakingASavingBackNeverGoesBelowZero() {
    var stats = ListeningStats()
    stats.addSaved(.ads, 30)
    stats.removeSaved(.ads, 20)
    XCTAssertEqual(stats.saved(.ads), 10)
    stats.removeSaved(.ads, 50)
    XCTAssertEqual(stats.saved(.ads), 0)
    stats.removeSaved(.ads, .nan)
    XCTAssertEqual(stats.saved(.ads), 0)
  }

  func testOnlyTheLastNinetyDaysAreKept() {
    var stats = ListeningStats()
    stats.addListened(5, at: date(), calendar: calendar)
    stats.addListened(5, at: date(daysAfter: 89), calendar: calendar)
    XCTAssertEqual(stats.days.count, 2)
    stats.addListened(5, at: date(daysAfter: 90), calendar: calendar)
    // Day 0 is now 90 days back, which is outside the 90 kept (today and the 89 before it).
    XCTAssertNil(stats.days["2026-11-17"])
    XCTAssertEqual(stats.days.count, 2)
    // The total is for all time and keeps what the days let go.
    XCTAssertEqual(stats.listened, 15)
  }

  func testMergingAddsEverything() {
    var first = ListeningStats()
    first.addListened(10, at: date(), calendar: calendar)
    first.addSaved(.trim, 4)
    var second = ListeningStats()
    second.addListened(20, at: date(), calendar: calendar)
    second.addListened(7, at: date(daysAfter: 1), calendar: calendar)
    second.addSaved(.trim, 6)
    second.addSaved(.speed, 2)
    first.merge(second, today: date(daysAfter: 1), calendar: calendar)
    XCTAssertEqual(first.listened, 37)
    XCTAssertEqual(first.days["2026-11-17"], 30)
    XCTAssertEqual(first.days["2026-11-18"], 7)
    XCTAssertEqual(first.saved(.trim), 10)
    XCTAssertEqual(first.saved(.speed), 2)
  }

  func testItRoundTripsThroughJSON() throws {
    var stats = ListeningStats()
    stats.addListened(61.5, at: date(), calendar: calendar)
    stats.addSaved(.chapters, 12)
    let back = ListeningStats.decode(try stats.encoded())
    XCTAssertEqual(back, stats)
  }

  func testBadJSONMeansNoStats() {
    XCTAssertEqual(ListeningStats.decode(Data("nonsense".utf8)), ListeningStats())
    XCTAssertEqual(ListeningStats.decode(Data()), ListeningStats())
  }

  func testNumbersAndDaysThatAreWrongAreDroppedWhenReading() {
    let json = """
      {"listened": -4, "savedBySpeed": 9, "savedByAds": 1e999,
       "days": {"2026-11-17": 12, "2026-11-18": -3, "yesterday": 5, "2026-13-01": 4}}
      """
    let stats = ListeningStats.decode(Data(json.utf8))
    XCTAssertEqual(stats.listened, 0)
    XCTAssertEqual(stats.saved(.speed), 9)
    XCTAssertEqual(stats.saved(.ads), 0)
    XCTAssertEqual(stats.days, ["2026-11-17": 12])
  }

  func testTheFileLoadsAndSaves() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stats-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Podcasts/stats.json")
    XCTAssertEqual(ListeningStatsFile.load(from: file), ListeningStats())
    var stats = ListeningStats()
    stats.addSaved(.skipping, 40)
    try ListeningStatsFile.save(stats, to: file)
    XCTAssertEqual(ListeningStatsFile.load(from: file), stats)
  }

  func testTheIntroSavesWhatItMovedTheStart() {
    XCTAssertEqual(
      ListeningStats.introSkipped(savedPosition: 0, duration: 1800, played: false, intro: 30), 30)
    // Resuming past the intro skips nothing.
    XCTAssertEqual(
      ListeningStats.introSkipped(savedPosition: 400, duration: 1800, played: false, intro: 30), 0)
    // Resuming inside the intro only skips the rest of it.
    XCTAssertEqual(
      ListeningStats.introSkipped(savedPosition: 10, duration: 1800, played: false, intro: 30), 20)
    XCTAssertEqual(
      ListeningStats.introSkipped(savedPosition: 0, duration: 1800, played: false, intro: 0), 0)
  }

  // MARK: The clock

  func testTheClockCountsTheTimeBetweenTicksWhilePlaying() {
    var clock = ListenClock()
    // The first tick only starts the clock.
    XCTAssertEqual(clock.tick(at: 100, playing: true, rate: 1).listened, 0)
    let second = clock.tick(at: 100.5, playing: true, rate: 1)
    XCTAssertEqual(second.listened, 0.5, accuracy: 0.0001)
    XCTAssertEqual(second.bySpeed, 0)
  }

  func testTheSpeedSavesTheAudioHeardMinusTheTimeItTook() {
    var clock = ListenClock()
    _ = clock.tick(at: 0, playing: true, rate: 2)
    let tick = clock.tick(at: 1, playing: true, rate: 2)
    XCTAssertEqual(tick.listened, 1, accuracy: 0.0001)
    XCTAssertEqual(tick.bySpeed, 1, accuracy: 0.0001)
    let slow = clock.tick(at: 2, playing: true, rate: 0.8)
    XCTAssertEqual(slow.bySpeed, 0)
  }

  func testNothingCountsWhileNotPlayingAndTheClockRestartsAfter() {
    var clock = ListenClock()
    _ = clock.tick(at: 0, playing: true, rate: 1)
    XCTAssertEqual(clock.tick(at: 0.5, playing: false, rate: 1).listened, 0)
    // The first tick after a pause only starts the clock again.
    XCTAssertEqual(clock.tick(at: 60, playing: true, rate: 1).listened, 0)
    XCTAssertEqual(clock.tick(at: 60.5, playing: true, rate: 1).listened, 0.5, accuracy: 0.0001)
  }

  func testALongGapBetweenTicksIsNotCounted() {
    var clock = ListenClock()
    _ = clock.tick(at: 0, playing: true, rate: 1)
    XCTAssertEqual(clock.tick(at: 30, playing: true, rate: 1).listened, 0)
  }

  func testBadClockValuesCountNothing() {
    var clock = ListenClock()
    _ = clock.tick(at: 0, playing: true, rate: 1)
    XCTAssertEqual(clock.tick(at: .nan, playing: true, rate: 1).listened, 0)
    _ = clock.tick(at: 1, playing: true, rate: 1)
    XCTAssertEqual(clock.tick(at: 1.5, playing: true, rate: .nan).bySpeed, 0)
  }
}
