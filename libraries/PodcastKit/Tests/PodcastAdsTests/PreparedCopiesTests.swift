import XCTest

@testable import PodcastAds

/// Which of the Mac's copies the phone takes and which it gives back.
final class PreparedCopiesTests: XCTestCase {
  private func aCopy(_ tag: String = "a") -> PreparedCopy {
    PreparedCopy(
      file: "prepared/\(tag).mp3", sha256: String(repeating: tag == "a" ? "a" : "b", count: 64),
      bytes: 10)
  }

  private func candidate(
    _ id: String, place: Int? = nil, download: PreparedCopies.Download = .none,
    started: Bool = false, playing: Bool = false, forList: Bool = false,
    listed: PreparedCopy? = nil, stillListed: Bool = false
  ) -> PreparedCopies.Candidate {
    PreparedCopies.Candidate(
      id: id, listPlace: place, download: download, started: started, inPlayer: playing,
      copyForListOnly: forList, listed: listed ?? aCopy(),
      stillListed: stillListed)
  }

  private func plan(_ candidates: [PreparedCopies.Candidate], most: Int = 3) -> PreparedCopies.Plan {
    PreparedCopies.plan(candidates, most: most)
  }

  private let other = String(repeating: "c", count: 64)

  // MARK: What is taken

  func testAnEpisodeOnTheListIsTaken() {
    XCTAssertEqual(plan([candidate("a", place: 0)]).take, ["a"])
  }

  func testADownloadedEpisodeOffTheListIsTaken() {
    XCTAssertEqual(plan([candidate("a", download: .downloaded(sha256: other))]).take, ["a"])
  }

  func testAnEpisodeOnNoListAndWithNoDownloadIsLeftToStream() {
    XCTAssertEqual(plan([candidate("a")]), PreparedCopies.Plan())
  }

  func testNothingIsTakenWhenThereIsNoListedCopy() {
    var one = candidate("a", place: 0)
    one.listed = nil
    XCTAssertEqual(plan([one]), PreparedCopies.Plan())
  }

  func testAStartedEpisodeIsNeverTaken() {
    XCTAssertEqual(plan([candidate("a", place: 0, started: true)]).take, [])
    XCTAssertEqual(plan([candidate("a", download: .downloaded(sha256: other), started: true)]).take, [])
  }

  func testTheEpisodeInThePlayerIsNeverTaken() {
    XCTAssertEqual(plan([candidate("a", place: 0, playing: true)]).take, [])
  }

  func testAnEpisodeDownloadingRightNowIsNotTaken() {
    XCTAssertEqual(plan([candidate("a", place: 0, download: .moving)]).take, [])
  }

  func testAnEpisodeThatHasThatVeryCopyIsNotTakenAgain() {
    let same = aCopy().sha256
    XCTAssertEqual(plan([candidate("a", place: 0, download: .downloaded(sha256: same))]).take, [])
    XCTAssertEqual(
      plan([candidate("a", place: 0, download: .downloaded(sha256: same.uppercased()))]).take, [])
    XCTAssertEqual(
      plan([candidate("a", place: 0, download: .downloaded(sha256: other))]).take, ["a"],
      "another copy of the file is swapped")
  }

  func testTheListGoesFirstInItsOwnOrderThenTheOthers() {
    let downloaded = PreparedCopies.Download.downloaded(sha256: other)
    let taken = plan(
      [
        candidate("x", download: downloaded), candidate("l2", place: 2),
        candidate("l0", place: 0), candidate("y", download: downloaded), candidate("l1", place: 1),
      ], most: 10
    ).take
    XCTAssertEqual(taken, ["l0", "l1", "l2", "x", "y"])
  }

  func testAtMostTheWholeListARunUnlessToldOtherwise() {
    let list = (0..<15).map { (n: Int) in candidate("e\(n)", place: n) }
    XCTAssertEqual(PreparedCopies.most, 12)
    XCTAssertEqual(PreparedCopies.plan(list).take, (0..<12).map { "e\($0)" })
    XCTAssertEqual(plan(list, most: 5).take.count, 5)
    XCTAssertEqual(plan(list, most: 0).take, [])
    XCTAssertEqual(plan(list, most: -2).take, [])
  }

  func testTheCapCutsTheOthersBeforeTheList() {
    let downloaded = PreparedCopies.Download.downloaded(sha256: other)
    let taken = plan(
      [candidate("d", download: downloaded), candidate("l1", place: 1), candidate("l0", place: 0)],
      most: 2
    ).take
    XCTAssertEqual(taken, ["l0", "l1"])
  }

  func testAnEpisodeIsNamedOnceAndAnEmptyIdNever() {
    let taken = plan([candidate("a", place: 1), candidate("a", place: 0), candidate("", place: 2)]).take
    XCTAssertEqual(taken, ["a"])
  }

  // MARK: What is given back

  func testACopyTakenForTheListIsGivenBackOnceTheEpisodeLeavesIt() {
    let held = PreparedCopies.Download.downloaded(sha256: aCopy().sha256)
    XCTAssertEqual(plan([candidate("a", download: held, forList: true)]).giveBack, ["a"])
  }

  func testItStaysWhileTheEpisodeIsOnTheListStartedOrInThePlayer() {
    let held = PreparedCopies.Download.downloaded(sha256: aCopy().sha256)
    XCTAssertEqual(plan([candidate("a", place: 3, download: held, forList: true)]).giveBack, [])
    XCTAssertEqual(plan([candidate("a", download: held, started: true, forList: true)]).giveBack, [])
    XCTAssertEqual(plan([candidate("a", download: held, playing: true, forList: true)]).giveBack, [])
  }

  func testACopyNotTakenForTheListIsNeverGivenBack() {
    let held = PreparedCopies.Download.downloaded(sha256: aCopy().sha256)
    XCTAssertEqual(plan([candidate("a", download: held, forList: false)]).giveBack, [])
    XCTAssertEqual(plan([candidate("a", download: .none, forList: true)]).giveBack, [])
    XCTAssertEqual(plan([candidate("a", download: .moving, forList: true)]).giveBack, [])
  }

  func testACopyIsKeptWhileItsEpisodeIsStillInTheWholeList() {
    let held = PreparedCopies.Download.downloaded(sha256: aCopy().sha256)
    // Past the places that are taken, but still in the listener's list: not given back.
    XCTAssertEqual(
      plan([candidate("a", download: held, forList: true, stillListed: true)]).giveBack, [])
    // Out of the whole list: given back.
    XCTAssertEqual(
      plan([candidate("a", download: held, forList: true, stillListed: false)]).giveBack, ["a"])
  }

  func testAnEpisodeOnlyStillListedIsNotTaken() {
    XCTAssertEqual(plan([candidate("a", stillListed: true)]).take, [])
  }

  func testGivingBackIsNotCappedAndKeepsTheOrder() {
    let held = PreparedCopies.Download.downloaded(sha256: aCopy().sha256)
    let back = plan((0..<5).map { candidate("e\($0)", download: held, forList: true) }).giveBack
    XCTAssertEqual(back, ["e0", "e1", "e2", "e3", "e4"])
  }

  func testWhatIsGivenBackIsNotTakenInTheSameRun() {
    let plain = plan([candidate("a", download: .downloaded(sha256: other), forList: true)])
    XCTAssertEqual(plain.giveBack, ["a"])
    XCTAssertEqual(plain.take, [])
  }

  func testAnEmptyListGivesAnEmptyPlan() {
    XCTAssertEqual(plan([]), PreparedCopies.Plan())
  }
}
