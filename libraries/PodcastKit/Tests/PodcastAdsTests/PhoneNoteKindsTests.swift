import XCTest

@testable import PodcastAds

/// The two note kinds that answers to a question write (`confirmed` and `denied`) and the finder's
/// name (`by`) a note can carry. Notes and lines written before them must still read.
final class PhoneNoteKindsTests: XCTestCase {
  private func object(_ line: String) throws -> [String: Any] {
    try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
  }

  /// A note exactly as the phone's earlier builds wrote it: no `by`.
  private let oldLine =
    #"{"at":1000,"end":60,"episode":"e1","kind":"ad","show":"s1","start":12.5,"v":1,"what":"skipped"}"#

  func testANoteWithoutByIsWrittenExactlyAsBefore() {
    let note = PhoneNote(
      at: 1000, what: .skipped, episode: "e1", show: "s1", start: 12.5, end: 60, kind: .ad)
    XCTAssertNil(note.by)
    XCTAssertEqual(note.line, oldLine)
  }

  func testAnOldLineReadsWithNoFinder() throws {
    let note = try JSONDecoder().decode(PhoneNote.self, from: Data(oldLine.utf8))
    XCTAssertNil(note.by)
    XCTAssertEqual(note.what, .skipped)
    XCTAssertEqual(note.start, 12.5)
  }

  func testTheFinderNameIsWrittenAndReadBack() throws {
    let note = PhoneNote(
      at: 5, what: .undone, episode: "e", show: "s", start: 1, end: 9, kind: .ad, by: "own-sound")
    XCTAssertEqual(try object(note.line)["by"] as? String, "own-sound")
    let back = try JSONDecoder().decode(PhoneNote.self, from: Data(note.line.utf8))
    XCTAssertEqual(back, note)
    XCTAssertEqual(back.by, "own-sound")
  }

  func testConfirmedAndDeniedAreNotesToo() throws {
    XCTAssertEqual(PhoneNote.What.confirmed.rawValue, "confirmed")
    XCTAssertEqual(PhoneNote.What.denied.rawValue, "denied")
    for what in [PhoneNote.What.confirmed, .denied] {
      let note = PhoneNote(
        at: 7, what: what, episode: "e", show: nil, start: 30, end: 70, kind: .ownPlug,
        by: "repeat-words")
      let fields = try object(note.line)
      XCTAssertEqual(fields["what"] as? String, what.rawValue)
      XCTAssertEqual(fields["by"] as? String, "repeat-words")
      XCTAssertEqual(fields["show"] as? String, "")
      let back = try JSONDecoder().decode(PhoneNote.self, from: Data(note.line.utf8))
      XCTAssertEqual(back, note)
    }
  }

  func testANoteWithAnOldKindStillHasItsOldFieldsAlongsideBy() throws {
    let note = PhoneNote(
      at: 1, what: .missed, episode: "e", show: "s", start: 3, end: nil, kind: nil, by: nil)
    let fields = try object(note.line)
    XCTAssertTrue(fields["end"] is NSNull)
    XCTAssertTrue(fields["kind"] is NSNull)
    XCTAssertNil(fields["by"], "no finder, no field")
  }

  /// The one line the Mac's Python test reads as well (`MacFixtures.confirmedNote`): both sides
  /// are tested against the same text.
  func testTheSharedConfirmedLineIsWhatThePhoneWrites() throws {
    let note = PhoneNote(
      at: 1_700_000_000_000, what: .confirmed, episode: "e1", show: "s1", start: 125.5, end: 180,
      kind: .ad, by: "repeat-words")
    XCTAssertEqual(note.line, MacFixtures.confirmedNote)
    let back = try JSONDecoder().decode(
      PhoneNote.self, from: Data(MacFixtures.confirmedNote.utf8))
    XCTAssertEqual(back, note)
    XCTAssertFalse(MacFixtures.confirmedNote.contains("\n"))
  }

  // MARK: A line the reader does not know

  /// A note kind this build does not know, as a newer build or the Mac might add.
  private let strangeLine =
    #"{"at":2000,"by":"x","end":null,"episode":"e","kind":null,"show":"s","start":1,"v":1,"what":"liked"}"#

  func testAnUnknownKindIsAnUnreadableNoteNotACrash() {
    XCTAssertNil(try? JSONDecoder().decode(PhoneNote.self, from: Data(strangeLine.utf8)))
  }

  func testThePendingFileKeepsWorkingAroundALineOfAnUnknownKind() {
    let known = PhoneNote(
      at: 1000, what: .confirmed, episode: "e", show: "s", start: 1, end: 2, kind: .ad,
      by: "meaning"
    ).line
    let text = known + "\n" + strangeLine + "\n"
    let newer = PhoneNote(
      at: 3000, what: .denied, episode: "e", show: "s", start: 5, end: 9, kind: .ad, by: "meaning"
    ).line
    // Adding a note and trimming to a cap treat every line alike.
    let more = PendingNotes.appending(newer, to: text)
    XCTAssertEqual(more.split(separator: "\n").count, 3)
    // The app saved the first two lines (the newest at 2000): the unknown kind goes with them
    // and the line written since stays.
    XCTAssertEqual(PendingNotes.dropping(3, upToAt: 2000, from: more), newer + "\n")
    XCTAssertEqual(PendingNotes.dropping(1, from: text), strangeLine + "\n")
  }
}
