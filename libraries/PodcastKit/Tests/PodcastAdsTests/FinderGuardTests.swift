import XCTest

@testable import PodcastAds

/// The guard's marks, traps and builds. A mark is written before a finder runs and cleared when it
/// returns; a mark found at the next launch means the finder trapped.
final class FinderGuardTests: XCTestCase {
  private func fresh(_ build: String = "100") -> FinderGuard { FinderGuard(appBuild: build) }

  /// What a second launch sees: a guard read from the text the first one left on disk.
  private func relaunch(_ guardian: FinderGuard, build: String = "100") -> FinderGuard {
    FinderGuard.read(guardian.text, appBuild: build)
  }

  func testAFreshGuardLetsEveryFinderSkip() {
    let guardian = fresh()
    for name in ["own-sound", "repeat-sound", "repeat-words", "meaning", "joints"] {
      XCTAssertEqual(guardian.mode(finder: name, show: "s", episode: "e"), .skip)
    }
    XCTAssertEqual(guardian.mode(finder: "never-heard-of", show: "", episode: ""), .skip)
  }

  func testAMarkSurvivesACrashAndSwitchesTheFinderOffForThatEpisode() {
    var first = fresh()
    first.begin(finder: "own-sound", episode: "e1")
    // The app trapped here: the next launch reads what was last written.
    var second = relaunch(first)
    let traps = second.recover()
    XCTAssertEqual(traps.map(\.finder), ["own-sound"])
    XCTAssertEqual(traps.map(\.episode), ["e1"])
    XCTAssertEqual(traps.map(\.offEverywhere), [false])
    XCTAssertEqual(second.mode(finder: "own-sound", show: "s", episode: "e1"), .off)
    XCTAssertEqual(second.mode(finder: "own-sound", show: "s", episode: "e2"), .skip)
    XCTAssertEqual(second.mode(finder: "meaning", show: "s", episode: "e1"), .skip)
  }

  func testTheOffStateOfAnEpisodeStaysOnDisk() {
    var first = fresh()
    first.begin(finder: "meaning", episode: "e1")
    var second = relaunch(first)
    second.recover()
    let third = relaunch(second)
    XCTAssertEqual(third.mode(finder: "meaning", show: "s", episode: "e1"), .off)
  }

  func testAMarkIsClearedWhenTheFinderReturns() {
    var first = fresh()
    first.begin(finder: "own-sound", episode: "e1")
    first.end(finder: "own-sound", episode: "e1")
    var second = relaunch(first)
    XCTAssertEqual(second.recover(), [])
    XCTAssertEqual(second.mode(finder: "own-sound", show: "s", episode: "e1"), .skip)
    XCTAssertTrue(first.text.contains(#""marks":[]"#))
  }

  func testEndOnlyClearsItsOwnMark() {
    var first = fresh()
    first.begin(finder: "own-sound", episode: "e1")
    first.begin(finder: "meaning", episode: "e1")
    first.end(finder: "own-sound", episode: "e1")
    var second = relaunch(first)
    XCTAssertEqual(second.recover().map(\.finder), ["meaning"])
    // An end with no mark does nothing.
    var third = fresh()
    third.end(finder: "meaning", episode: "e9")
    XCTAssertEqual(third, fresh())
  }

  func testBeginningTwiceLeavesOneMark() {
    var first = fresh()
    first.begin(finder: "own-sound", episode: "e1")
    first.begin(finder: "own-sound", episode: "e1")
    XCTAssertEqual(first.marks.count, 1)
  }

  func testRecoverClearsTheMarksSoALaterLaunchDoesNotCountThemAgain() {
    var first = fresh()
    first.begin(finder: "own-sound", episode: "e1")
    var second = relaunch(first)
    XCTAssertEqual(second.recover().count, 1)
    var third = relaunch(second)
    XCTAssertEqual(third.recover(), [])
    XCTAssertEqual(third.mode(finder: "own-sound", show: "s", episode: "e2"), .skip)
  }

  func testASecondTrapByTheSameFinderSwitchesItOffEverywhere() {
    var guardian = fresh()
    guardian.begin(finder: "own-sound", episode: "e1")
    guardian = relaunch(guardian)
    XCTAssertEqual(guardian.recover().map(\.offEverywhere), [false])
    guardian.begin(finder: "own-sound", episode: "e2")
    guardian = relaunch(guardian)
    XCTAssertEqual(guardian.recover().map(\.offEverywhere), [true])
    for (show, episode) in [("s", "e3"), ("other", "e4"), ("", "")] {
      XCTAssertEqual(guardian.mode(finder: "own-sound", show: show, episode: episode), .off)
    }
    XCTAssertEqual(guardian.mode(finder: "meaning", show: "s", episode: "e3"), .skip)
    XCTAssertEqual(relaunch(guardian).mode(finder: "own-sound", show: "s", episode: "e9"), .off)
  }

  func testTwoMarksOfOneFinderInOneCrashAreOneTrap() {
    var guardian = fresh()
    guardian.begin(finder: "repeat-words", episode: "e1")
    guardian.begin(finder: "repeat-words", episode: "e2")
    guardian = relaunch(guardian)
    let traps = guardian.recover()
    XCTAssertEqual(traps.count, 2)
    XCTAssertEqual(traps.map(\.offEverywhere), [false, false])
    XCTAssertEqual(guardian.mode(finder: "repeat-words", show: "s", episode: "e1"), .off)
    XCTAssertEqual(guardian.mode(finder: "repeat-words", show: "s", episode: "e2"), .off)
    XCTAssertEqual(guardian.mode(finder: "repeat-words", show: "s", episode: "e3"), .skip)
  }

  func testANewBuildResetsWhatTheCrashesSwitchedOff() {
    var guardian = fresh("100")
    for episode in ["e1", "e2"] {
      guardian.begin(finder: "own-sound", episode: episode)
      guardian = relaunch(guardian)
      guardian.recover()
    }
    guardian.begin(finder: "meaning", episode: "e5")
    XCTAssertEqual(guardian.mode(finder: "own-sound", show: "s", episode: "e3"), .off)
    // The same build keeps it off. A new build starts clean: no trap, no mark, no episode off.
    XCTAssertEqual(relaunch(guardian, build: "100").mode(finder: "own-sound", show: "s", episode: "e3"), .off)
    var newer = relaunch(guardian, build: "101")
    XCTAssertEqual(newer.appBuild, "101")
    XCTAssertEqual(newer.mode(finder: "own-sound", show: "s", episode: "e3"), .skip)
    XCTAssertEqual(newer.mode(finder: "own-sound", show: "s", episode: "e1"), .skip)
    XCTAssertEqual(newer.recover(), [], "a mark of the old build is not a trap of the new one")
    // The new build is written down, so the next launch of it is not "new" again.
    newer.begin(finder: "own-sound", episode: "e7")
    var again = relaunch(newer, build: "101")
    XCTAssertEqual(again.recover().map(\.finder), ["own-sound"])
  }

  func testAnswersOutliveANewBuild() {
    var guardian = fresh("100")
    guardian.undone(finder: "own-sound", show: "s")
    guardian.undone(finder: "own-sound", show: "s")
    XCTAssertEqual(guardian.mode(finder: "own-sound", show: "s", episode: "e"), .ask)
    let newer = relaunch(guardian, build: "101")
    XCTAssertEqual(newer.mode(finder: "own-sound", show: "s", episode: "e"), .ask)
  }

  // MARK: Names that are not names

  func testABlankFinderIsNotTracked() {
    var guardian = fresh()
    guardian.begin(finder: "", episode: "e1")
    guardian.begin(finder: "  \n", episode: "e1")
    XCTAssertEqual(guardian, fresh())
    XCTAssertEqual(guardian.mode(finder: "", show: "s", episode: "e1"), .skip)
  }

  func testATrapWithNoEpisodeStillCountsForTheFinder() {
    var guardian = fresh()
    for _ in 1...2 {
      guardian.begin(finder: "joints", episode: "")
      guardian = relaunch(guardian)
      guardian.recover()
    }
    XCTAssertEqual(guardian.mode(finder: "joints", show: "s", episode: "anything"), .off)
  }

  func testNamesAreCutToTheirLimitSoALongNameStillMatches() {
    var guardian = fresh()
    let long = String(repeating: "x", count: 5000)
    guardian.begin(finder: long, episode: long)
    guardian = relaunch(guardian)
    XCTAssertLessThan(guardian.text.utf8.count, 1000)
    guardian.recover()
    XCTAssertEqual(guardian.mode(finder: long, show: "s", episode: long), .off)
  }

  // MARK: The file

  func testSaveAndLoadThroughAPath() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Podcasts").appendingPathComponent(FinderGuard.fileName)
    XCTAssertEqual(FinderGuard.fileName, "finder-guard.json")
    XCTAssertEqual(FinderGuard.load(from: url, appBuild: "100"), fresh(), "a missing file is empty")
    var guardian = fresh()
    guardian.begin(finder: "meaning", episode: "e1")
    guardian.undone(finder: "own-sound", show: "s")
    try guardian.save(to: url)
    XCTAssertEqual(FinderGuard.load(from: url, appBuild: "100"), guardian)
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), guardian.text)
  }

  func testAFileThatIsTooBigIsNotRead() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 0x20, count: FinderGuard.maxFileBytes + 1).write(to: url)
    XCTAssertEqual(FinderGuard.load(from: url, appBuild: "100"), fresh())
  }

  func testTheGuardIsAPlainSendableValue() {
    func needsSendable<T: Sendable>(_: T) {}
    needsSendable(fresh())
    needsSendable(FinderMode.ask)
  }
}
