import XCTest

@testable import PodcastAds

/// The row names of the scorecard are a contract with the Mac's `teach_settings.py`, which reads
/// them by name and ignores a row it does not know. Two tools that share a file are tested against
/// the same text (docs/LESSONS.md): this reads the Python file itself.
final class ScoreRowsTests: XCTestCase {
  private func teachSettingsSource() throws -> String {
    // .../Tests/PodcastAdsTests/ScoreRowsTests.swift -> .../Tools/mac/teach_settings.py
    let kit = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let file = kit.appendingPathComponent("Tools/mac/teach_settings.py")
    return try String(contentsOf: file, encoding: .utf8)
  }

  func testEveryFinderRowNameIsInTheMacsRowTable() throws {
    let text = try teachSettingsSource()
    for name in [
      ScoreRows.ownSounds, ScoreRows.repeatedSounds, ScoreRows.repeatedWords, ScoreRows.meaning,
      ScoreRows.joints, ScoreRows.steadyJoints,
    ] {
      XCTAssertTrue(text.contains("\"\(name)\":"), "teach_settings.py has no row \"\(name)\"")
    }
  }

  func testTheNamesAreThoseTheTaskSetOutWordForWord() {
    XCTAssertEqual(ScoreRows.ownSounds, "Plus the phone's own sounds")
    XCTAssertEqual(ScoreRows.repeatedSounds, "Plus repeated sounds")
    XCTAssertEqual(ScoreRows.repeatedWords, "Plus repeated words")
    XCTAssertEqual(ScoreRows.meaning, "Plus the meaning model")
    XCTAssertEqual(ScoreRows.joints, "Plus joints")
    XCTAssertEqual(ScoreRows.steadyJoints, "Plus joints (steady files too)")
    XCTAssertEqual(ScoreRows.settings, "Plus per-show settings")
  }

  func testTheFindersNamesInTheAdsAreTheOnesTheSettingsFileUses() {
    // The ads' `source` strings come from ShowTuning and the finders' own constants.
    XCTAssertEqual(RepeatedWords.source, ShowTuning.repeatWords)
    XCTAssertEqual(MeaningAds.source, ShowTuning.meaning)
  }
}
