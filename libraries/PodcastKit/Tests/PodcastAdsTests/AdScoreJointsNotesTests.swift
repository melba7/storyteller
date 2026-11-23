import XCTest

@testable import PodcastAds

/// The lines the scorecard prints about the two joints rows, which follow the Mac's rule for them
/// (`over_joints` in teach_settings.py).
final class AdScoreJointsNotesTests: XCTestCase {
  private func row(
    _ name: String, ad: Double = 300, heard: Double, cut: Double, episodes: Int = 3
  ) -> ScorecardRow {
    var total = ScoreTotals()
    total.episodes = episodes
    total.adSeconds = ad
    total.heardSeconds = heard
    total.cutSeconds = cut
    return ScorecardRow(name: name, total: total, shows: [])
  }

  // The Mac's rule (`over_joints` in teach_settings.py): a joints row pays against the row BEFORE
  // "Plus joints" when it finds more right seconds and cuts at most 101 percent of that row's
  // wrong seconds. Joints stay on when either row pays; steady files are used too when the steady
  // row pays and, if the plain row pays as well, beats it by the same test.

  /// The row before the joints (right 100 s, wrong 100 s), the plain joints row and the steady one.
  private func joints(
    plain: (heard: Double, cut: Double), steady: (heard: Double, cut: Double), ad: Double = 300,
    before: (heard: Double, cut: Double) = (200, 100), episodes: Int = 3
  ) -> [String] {
    AdScoreNotes.rowLines([
      row("Plus repeated words", ad: ad, heard: before.heard, cut: before.cut, episodes: episodes),
      row(ScoreRows.joints, ad: ad, heard: plain.heard, cut: plain.cut, episodes: episodes),
      row(ScoreRows.steadyJoints, ad: ad, heard: steady.heard, cut: steady.cut, episodes: episodes),
    ])
  }

  func testTheSteadyRowIsJudgedAgainstTheRowBeforeThePlainJointsRow() {
    let lines = AdScoreNotes.rowLines([
      row("Plus repeated words", heard: 100, cut: 50), row(ScoreRows.joints, heard: 80, cut: 50),
      row(ScoreRows.steadyJoints, heard: 70, cut: 50),
    ])
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[1].hasPrefix("Joints in steady files too: right seconds 3 min 50 s (3 min 20 s before)"), lines[1])
    XCTAssertTrue(lines[1].hasSuffix("Steady files should be used too."), lines[1])
  }

  func testPlainJointsPayAndSteadyFilesAddNothing() {
    let lines = joints(plain: (160, 100), steady: (160, 100))
    XCTAssertTrue(lines[0].hasSuffix("Joints pay."), lines[0])
    XCTAssertTrue(
      lines[1].hasSuffix(
        "Steady files should not be used too: no more of the ad time is skipped than with the plain joints row."),
      lines[1])
  }

  func testWhenOnlyTheSteadyRowPaysTheJointsStayOnBecauseOfIt() {
    // On steady files the plain row is flat and the steady row finds 60 s more.
    let lines = joints(plain: (200, 100), steady: (140, 100))
    XCTAssertTrue(
      lines[0].hasSuffix("The plain row does not pay by itself; joints stay on because the steady row pays."), lines[0])
    XCTAssertFalse(lines[0].contains("Joints do not pay"), lines[0])
    XCTAssertTrue(lines[1].hasSuffix("Steady files should be used too."), lines[1])
  }

  func testTheSteadyRowIsJudgedAgainstTheRowBeforeTheJointsNotAgainstThePlainRow() {
    // Plain (440, 110) cuts too much show; steady (440, 100) does not. The Mac switches steady files on.
    let lines = joints(plain: (560, 110), steady: (560, 100), ad: 1000, before: (600, 100))
    XCTAssertTrue(
      lines[0].hasSuffix("The plain row does not pay by itself; joints stay on because the steady row pays."), lines[0])
    XCTAssertTrue(lines[1].hasSuffix("Steady files should be used too."), lines[1])
  }

  func testWhenBothPayTheSteadyRowMustBeatThePlainRowByTheSameTest() {
    // It finds 20 s more and cuts exactly 101 percent of the plain row's wrong seconds: used.
    var lines = joints(plain: (160, 100), steady: (140, 101))
    XCTAssertTrue(lines[0].hasSuffix("Joints pay."), lines[0])
    XCTAssertTrue(lines[1].hasSuffix("Steady files should be used too."), lines[1])
    // It finds more, but cuts more than 101 percent of the plain row's wrong seconds (it still
    // pays against the row before, which cuts more): not used.
    lines = joints(plain: (160, 90), steady: (140, 100))
    XCTAssertTrue(lines[0].hasSuffix("Joints pay."), lines[0])
    XCTAssertTrue(
      lines[1].hasSuffix(
        "Steady files should not be used too: show time cut by mistake rose by more than one in a hundred over the plain joints row."),
      lines[1])
  }

  func testWhenNeitherRowPaysTheJointsAreOffAndSaidSo() {
    let lines = joints(plain: (200, 100), steady: (200, 100))
    XCTAssertTrue(lines[0].hasSuffix("Joints do not pay: no more of the ad time is skipped."), lines[0])
    XCTAssertTrue(
      lines[1].hasSuffix("Steady files should not be used too: no more of the ad time is skipped."), lines[1])
  }

  func testASteadyRowThatFindsMoreButCutsTooMuchDoesNotPay() {
    // The plain row is flat, and the steady row cuts 102 against 100: it does not pay.
    var lines = joints(plain: (200, 100), steady: (140, 102))
    XCTAssertTrue(lines[0].hasSuffix("Joints do not pay: no more of the ad time is skipped."), lines[0])
    XCTAssertTrue(
      lines[1].hasSuffix(
        "Steady files should not be used too: show time cut by mistake rose by more than one in a hundred."),
      lines[1])
    // The plain row pays: the joints stay on and steady files are not used.
    lines = joints(plain: (160, 100), steady: (120, 102))
    XCTAssertTrue(lines[0].hasSuffix("Joints pay."), lines[0])
    XCTAssertTrue(lines[1].contains("Steady files should not be used too: show time cut by mistake rose"), lines[1])
  }

  func testTheMacJudgesJointsOnlyOverThreeEpisodes() {
    let lines = joints(plain: (160, 100), steady: (140, 100), episodes: 2)
    for line in lines {
      XCTAssertTrue(
        line.hasSuffix("The Mac judges joints only over 3 or more marked episodes, so it leaves them as they are."), line)
    }
  }
}
