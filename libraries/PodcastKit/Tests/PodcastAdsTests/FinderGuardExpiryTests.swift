import XCTest

@testable import PodcastAds

/// Answers older than 30 days do not count and are not written, and the guard does not trap on
/// a count or a date that cannot be right.
final class FinderGuardExpiryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)
  private let day: TimeInterval = 24 * 3600

  private func fresh() -> FinderGuard { FinderGuard(appBuild: "100") }

  private func mode(
    _ guardian: FinderGuard, _ finder: String = "meaning", at time: Date
  ) -> FinderMode {
    guardian.mode(finder: finder, show: "s", episode: "e", now: time)
  }

  func testTwoDeniedAnswersWithin30DaysTurnTheFinderOff() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    guardian.denied(finder: "meaning", show: "s", now: now.addingTimeInterval(10 * day))
    XCTAssertEqual(mode(guardian, at: now.addingTimeInterval(20 * day)), .off)
  }

  func testTheSameTwoAnswers31DaysLaterDoNotCount() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    guardian.denied(finder: "meaning", show: "s", now: now)
    XCTAssertEqual(mode(guardian, at: now), .off)
    XCTAssertEqual(mode(guardian, at: now.addingTimeInterval(30 * day)), .off, "30 days still count")
    XCTAssertEqual(mode(guardian, at: now.addingTimeInterval(31 * day)), .skip, "it comes back")
  }

  func testAnAnswer31DaysOldIsIgnoredAndOneNewAnswerIsNotEnough() {
    var guardian = fresh()
    guardian.undone(finder: "own-sound", show: "s", now: now)
    guardian.undone(finder: "own-sound", show: "s", now: now.addingTimeInterval(31 * day))
    let later = now.addingTimeInterval(31 * day)
    XCTAssertEqual(mode(guardian, "own-sound", at: later), .skip)
    guardian.undone(finder: "own-sound", show: "s", now: later)
    XCTAssertEqual(mode(guardian, "own-sound", at: later), .ask)
  }

  func testAnOldAnswerDoesNotTakeAPlaceInTheLastFive() {
    var guardian = fresh()
    // Two old undone skips, then two fresh "yes" and one fresh undone skip. The old ones are out
    // of the five, so only one undone skip counts. Counted, they would make three.
    for _ in 1...2 { guardian.undone(finder: "own-sound", show: "s", now: now) }
    let later = now.addingTimeInterval(40 * day)
    for _ in 1...2 { guardian.confirmed(finder: "own-sound", show: "s", now: later) }
    guardian.undone(finder: "own-sound", show: "s", now: later)
    XCTAssertEqual(mode(guardian, "own-sound", at: later), .skip)
    guardian.undone(finder: "own-sound", show: "s", now: later)
    XCTAssertEqual(mode(guardian, "own-sound", at: later), .ask)
  }

  func testAnAnswerFromMoreThan30DaysAheadIsIgnoredToo() {
    var guardian = fresh()
    let ahead = now.addingTimeInterval(400 * day)
    for _ in 1...2 { guardian.denied(finder: "meaning", show: "s", now: ahead) }
    XCTAssertEqual(mode(guardian, at: now), .skip, "a clock set far ahead does not last for years")
  }

  func testOldAnswersAreNotWrittenToTheFile() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    guardian.undone(finder: "own-sound", show: "t", now: now.addingTimeInterval(35 * day))
    let later = now.addingTimeInterval(36 * day)
    let back = FinderGuard.read(guardian.text(now: later), appBuild: "100")
    XCTAssertEqual(back.shows.map(\.show), ["t"], "the show with only an old answer is gone")
    XCTAssertEqual(back.shows.first?.finders.map(\.finder), ["own-sound"])
    // A guard with nothing fresh is an empty guard.
    XCTAssertEqual(FinderGuard.read(guardian.text(now: now.addingTimeInterval(90 * day)), appBuild: "100"), fresh())
  }

  func testSavingDropsTheOldAnswersToo() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    try guardian.save(to: url, now: now.addingTimeInterval(31 * day))
    XCTAssertEqual(FinderGuard.load(from: url, appBuild: "100"), fresh())
  }

  func testRecordingAnAnswerDropsTheOldOnesOfThatFinder() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    guardian.denied(finder: "meaning", show: "s", now: now.addingTimeInterval(31 * day))
    XCTAssertEqual(guardian.shows.first?.finders.first?.last.count, 1)
  }

  func testADateThatIsNotANumberOrAHugeOneDoesNotTrap() {
    var guardian = fresh()
    let odd = [
      Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: -.infinity),
      Date(timeIntervalSince1970: .nan), Date.distantFuture, Date.distantPast,
      Date(timeIntervalSince1970: .greatestFiniteMagnitude),
    ]
    for date in odd {
      guardian.undone(finder: "meaning", show: "s", now: date)
      guardian.denied(finder: "meaning", show: "s", now: date)
      guardian.confirmed(finder: "meaning", show: "s", now: date)
      _ = guardian.mode(finder: "meaning", show: "s", episode: "e", now: date)
      _ = guardian.text(now: date)
    }
    // A date that is not a number counts as no time at all, and nothing is switched off by it.
    let nothing = Date(timeIntervalSince1970: .nan)
    XCTAssertEqual(fresh().mode(finder: "meaning", show: "s", episode: "e", now: nothing), .skip)
    XCTAssertEqual(FinderGuard.read(guardian.text(now: nothing), appBuild: "100").appBuild, "100")
  }

  // MARK: A guard that was not made by `read`

  func testAHugeTrapCountDecodedDirectlyDoesNotOverflow() throws {
    let text = #"{"version":1,"appBuild":"100","marks":[],"traps":{"a":9223372036854775807,"b":-9223372036854775808},"trapped":[],"shows":[]}"#
    var guardian = try JSONDecoder().decode(FinderGuard.self, from: Data(text.utf8))
    guardian.begin(finder: "a", episode: "e1")
    guardian.begin(finder: "b", episode: "e2")
    let traps = guardian.recover()
    XCTAssertEqual(traps.map(\.finder).sorted(), ["a", "b"])
    XCTAssertEqual(traps.first { $0.finder == "a" }?.offEverywhere, true)
    XCTAssertEqual(guardian.mode(finder: "a", show: "s", episode: "x", now: now), .off)
    XCTAssertEqual(guardian.traps["b"], 1, "a count that cannot be right starts again from this trap")
  }
}
