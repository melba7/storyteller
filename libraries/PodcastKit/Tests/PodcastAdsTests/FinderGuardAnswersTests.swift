import XCTest

@testable import PodcastAds

/// The guard's answers (undone skips, "not an ad", yes), its caps and the files it will not read.
final class FinderGuardAnswersTests: XCTestCase {
  /// The moment of every call, so a test says how much later something happens.
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func fresh() -> FinderGuard { FinderGuard(appBuild: "100") }

  private func mode(_ guardian: FinderGuard, _ finder: String = "own-sound", show: String = "s")
    -> FinderMode
  {
    guardian.mode(finder: finder, show: show, episode: "e", now: now)
  }

  // MARK: Two undone out of five make a finder ask

  func testTwoUndoneSkipsMakeTheFinderAskOnThatShowOnly() {
    var guardian = fresh()
    guardian.undone(finder: "own-sound", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .skip, "one undone skip is not a pattern")
    guardian.undone(finder: "own-sound", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .ask)
    XCTAssertEqual(mode(guardian, show: "other"), .skip)
    XCTAssertEqual(mode(guardian, "meaning"), .skip)
  }

  func testOnlyTheLastFiveAnswersCount() {
    var guardian = fresh()
    guardian.undone(finder: "own-sound", show: "s", now: now)
    guardian.undone(finder: "own-sound", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .ask)
    // Answers: [undone, undone, yes, yes, yes] still holds two.
    for _ in 1...3 { guardian.confirmed(finder: "own-sound", show: "s", now: now) }
    XCTAssertEqual(mode(guardian), .ask)
    // A sixth answer pushes the first undone out of the five.
    guardian.confirmed(finder: "own-sound", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .skip)
  }

  func testUndoneSkipsFarApartAreNotTwoOutOfFive() {
    var guardian = fresh()
    guardian.undone(finder: "own-sound", show: "s", now: now)
    for _ in 1...5 { guardian.confirmed(finder: "own-sound", show: "s", now: now) }
    guardian.undone(finder: "own-sound", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .skip)
  }

  func testAFindersAnswersAreKeptApartFromAnotherFindersOnTheSameShow() {
    var guardian = fresh()
    guardian.undone(finder: "own-sound", show: "s", now: now)
    guardian.undone(finder: "meaning", show: "s", now: now)
    XCTAssertEqual(mode(guardian), .skip)
    XCTAssertEqual(mode(guardian, "meaning"), .skip)
  }

  // MARK: Two "not an ad" answers out of five turn a finder off

  func testTwoDeniedAnswersTurnTheFinderOffOnThatShowOnly() {
    var guardian = fresh()
    guardian.denied(finder: "repeat-words", show: "s", now: now)
    XCTAssertEqual(mode(guardian, "repeat-words"), .skip)
    guardian.denied(finder: "repeat-words", show: "s", now: now)
    XCTAssertEqual(mode(guardian, "repeat-words"), .off)
    XCTAssertEqual(mode(guardian, "repeat-words", show: "other"), .skip)
    XCTAssertEqual(mode(guardian, "own-sound"), .skip)
  }

  func testDeniedAndUndoneAreCountedApart() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    guardian.undone(finder: "meaning", show: "s", now: now)
    XCTAssertEqual(mode(guardian, "meaning"), .skip, "one of each is not two of a kind")
    guardian.undone(finder: "meaning", show: "s", now: now)
    XCTAssertEqual(mode(guardian, "meaning"), .ask)
  }

  func testOffWinsOverAsk() {
    var guardian = fresh()
    for _ in 1...2 { guardian.undone(finder: "meaning", show: "s", now: now) }
    XCTAssertEqual(mode(guardian, "meaning"), .ask)
    for _ in 1...2 { guardian.denied(finder: "meaning", show: "s", now: now) }
    XCTAssertEqual(mode(guardian, "meaning"), .off)
  }

  func testTheFiveCountsAnswersOfBothKinds() {
    var guardian = fresh()
    guardian.denied(finder: "meaning", show: "s", now: now)
    for _ in 1...4 { guardian.confirmed(finder: "meaning", show: "s", now: now) }
    guardian.denied(finder: "meaning", show: "s", now: now)
    // [denied, yes, yes, yes, yes, denied] keeps the last five: one denied.
    XCTAssertEqual(mode(guardian, "meaning"), .skip)
  }

  func testAnswersWithNoShowOrNoFinderAreNotKept() {
    var guardian = fresh()
    for _ in 1...3 {
      guardian.undone(finder: "own-sound", show: "", now: now)
      guardian.denied(finder: "", show: "s", now: now)
    }
    XCTAssertEqual(guardian, fresh())
    XCTAssertEqual(guardian.mode(finder: "own-sound", show: "", episode: "e", now: now), .skip)
  }

  func testAnswersSurviveAFileRoundTrip() {
    var guardian = fresh()
    for _ in 1...2 { guardian.undone(finder: "joints", show: "show-1", now: now) }
    for _ in 1...2 { guardian.denied(finder: "repeat-sound", show: "show-2", now: now) }
    let back = FinderGuard.read(guardian.text(now: now), appBuild: "100")
    XCTAssertEqual(back, guardian)
    XCTAssertEqual(back.mode(finder: "joints", show: "show-1", episode: "e", now: now), .ask)
    XCTAssertEqual(back.mode(finder: "repeat-sound", show: "show-2", episode: "e", now: now), .off)
  }

  // MARK: A file that cannot be read is an empty one

  func testADamagedOrUnknownFileReadsAsEmpty() {
    let valid = #"{"version":1,"appBuild":"100","marks":[],"traps":{},"trapped":[],"shows":[]}"#
    XCTAssertEqual(FinderGuard.read(valid, appBuild: "100"), fresh())
    let bad: [String?] = [
      nil, "", "   ", "{", "[]", "null", "5", "not json at all", #"{"version":1}"#,
      #"{"version":99,"appBuild":"100","marks":[],"traps":{},"trapped":[],"shows":[]}"#,
      #"{"version":0,"appBuild":"100","marks":[],"traps":{},"trapped":[],"shows":[]}"#,
      #"{"version":1,"appBuild":"100","marks":"x","traps":{},"trapped":[],"shows":[]}"#,
      #"{"version":1,"appBuild":"100","marks":[],"traps":{"a":"two"},"trapped":[],"shows":[]}"#,
      #"{"version":1,"appBuild":"100","marks":[],"traps":{},"trapped":[],"shows":[{"show":"s","finders":[{"finder":"a","last":[{"answer":"maybe","at":0}]}]}]}"#,
      String(String(repeating: "[", count: 5000)),
      String(decoding: [0xff, 0xfe, 0x00, 0x7b], as: UTF8.self),
    ]
    for text in bad {
      let read = FinderGuard.read(text, appBuild: "100")
      XCTAssertEqual(read, fresh(), "\(String(describing: text).prefix(40))")
      XCTAssertEqual(read.mode(finder: "own-sound", show: "s", episode: "e", now: now), .skip)
    }
  }

  func testATextOverTheFileLimitReadsAsEmpty() {
    let filler = String(repeating: " ", count: FinderGuard.maxFileBytes)
    let text = #"{"version":1,"appBuild":"100","marks":[],"traps":{"own-sound":2},"trapped":[],"shows":[]}"# + filler
    XCTAssertEqual(FinderGuard.read(text, appBuild: "100"), fresh())
  }

  func testNegativeOrHugeTrapCountsDoNotTrap() {
    let text = #"{"version":1,"appBuild":"100","marks":[],"traps":{"a":-5,"b":9223372036854775807},"trapped":[],"shows":[]}"#
    let read = FinderGuard.read(text, appBuild: "100")
    XCTAssertEqual(read.mode(finder: "a", show: "s", episode: "e", now: now), .skip)
    XCTAssertEqual(read.mode(finder: "b", show: "s", episode: "e", now: now), .off)
    var more = read
    more.begin(finder: "b", episode: "e")
    more = FinderGuard.read(more.text(now: now), appBuild: "100")
    XCTAssertEqual(more.recover().count, 1, "adding one to a huge count does not overflow")
  }

  // MARK: The file stays small

  func testMarksAreCapped() {
    var guardian = fresh()
    for number in 1...1000 { guardian.begin(finder: "own-sound", episode: "e\(number)") }
    XCTAssertEqual(guardian.marks.count, FinderGuard.maxMarks)
    XCTAssertEqual(guardian.marks.last?.episode, "e1000", "the newest marks stay")
  }

  func testTheEpisodesSwitchedOffAreCappedAndTheNewestStay() {
    var guardian = fresh()
    for number in 1...(FinderGuard.maxTrappedEpisodes + 50) {
      guardian.begin(finder: "meaning", episode: "e\(number)")
      guardian = FinderGuard.read(guardian.text(now: now), appBuild: "100")
      guardian.recover()
      // One trap a launch would switch the finder off everywhere: keep the test on the episodes.
      guardian.traps = [:]
    }
    XCTAssertEqual(guardian.trapped.count, FinderGuard.maxTrappedEpisodes)
    let last = FinderGuard.maxTrappedEpisodes + 50
    XCTAssertEqual(guardian.mode(finder: "meaning", show: "s", episode: "e\(last)", now: now), .off)
    XCTAssertEqual(guardian.mode(finder: "meaning", show: "s", episode: "e1", now: now), .skip)
  }

  func testShowsAreCappedAndTheLeastRecentlyAnsweredGoesFirst() {
    var guardian = fresh()
    for number in 1...(FinderGuard.maxShows + 30) {
      guardian.undone(finder: "own-sound", show: "show-\(number)", now: now)
      guardian.undone(finder: "own-sound", show: "show-\(number)", now: now)
    }
    XCTAssertEqual(guardian.shows.count, FinderGuard.maxShows)
    XCTAssertEqual(mode(guardian, show: "show-1"), .skip, "forgotten")
    XCTAssertEqual(mode(guardian, show: "show-\(FinderGuard.maxShows + 30)"), .ask)
    // Answering for an old show moves it to the back of the line.
    var kept = fresh()
    for number in 1...FinderGuard.maxShows {
      for _ in 1...2 { kept.undone(finder: "own-sound", show: "show-\(number)", now: now) }
    }
    kept.undone(finder: "own-sound", show: "show-1", now: now)
    kept.undone(finder: "own-sound", show: "extra", now: now)
    XCTAssertEqual(mode(kept, show: "show-1"), .ask, "show-1 was answered again, so it stayed")
    XCTAssertEqual(mode(kept, show: "show-2"), .skip, "show-2 was the oldest and went")
    XCTAssertEqual(mode(kept, show: "show-3"), .ask)
  }

  func testTheFindersOfOneShowAreCapped() {
    var guardian = fresh()
    for number in 1...100 { guardian.undone(finder: "finder-\(number)", show: "s", now: now) }
    XCTAssertEqual(guardian.shows.first?.finders.count, FinderGuard.maxFindersPerShow)
    XCTAssertEqual(guardian.shows.first?.finders.last?.finder, "finder-100", "the newest stay")
  }

  func testTheAnswersOfOneFinderAreCappedAtFive() {
    var guardian = fresh()
    for _ in 1...500 { guardian.confirmed(finder: "own-sound", show: "s", now: now) }
    XCTAssertEqual(guardian.shows.first?.finders.first?.last.count, FinderGuard.answerWindow)
    XCTAssertEqual(FinderGuard.answerWindow, 5)
  }

  func testAFullGuardIsStillASmallFile() {
    var guardian = fresh()
    let names = ["own-sound", "repeat-sound", "repeat-words", "meaning", "joints"]
    for number in 1...(FinderGuard.maxShows * 2) {
      for name in names {
        for _ in 1...6 { guardian.undone(finder: name, show: "\(number)" + String(repeating: "s", count: 300), now: now) }
      }
    }
    for number in 1...(FinderGuard.maxMarks * 2) {
      guardian.begin(finder: names[number % 5], episode: "\(number)" + String(repeating: "e", count: 300))
    }
    XCTAssertEqual(guardian.shows.count, FinderGuard.maxShows)
    XCTAssertLessThan(guardian.text(now: now).utf8.count, 128 * 1024)
    XCTAssertLessThan(guardian.text(now: now).utf8.count, FinderGuard.maxFileBytes)
  }

  func testAHandMadeFileOverTheCapsIsTrimmedOnRead() throws {
    let marks = (1...500).map { #"{"finder":"a","episode":"e\#($0)"}"# }.joined(separator: ",")
    let text = #"{"version":1,"appBuild":"100","marks":[\#(marks)],"traps":{},"trapped":[],"shows":[]}"#
    let read = FinderGuard.read(text, appBuild: "100")
    XCTAssertEqual(read.marks.count, FinderGuard.maxMarks)
    let answers = (1...50).map { _ in #"{"answer":"undone","at":0}"# }.joined(separator: ",")
    let long = #"{"version":1,"appBuild":"100","marks":[],"traps":{},"trapped":[],"shows":[{"show":"s","finders":[{"finder":"a","last":[\#(answers)]}]}]}"#
    XCTAssertEqual(FinderGuard.read(long, appBuild: "100").shows.first?.finders.first?.last.count, 5)
  }
}
