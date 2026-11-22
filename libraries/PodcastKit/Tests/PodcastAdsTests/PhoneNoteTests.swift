import XCTest

@testable import PodcastAds

/// The notes the phone keeps for the Mac, and the rules of the file they wait in.
final class PhoneNoteTests: XCTestCase {
  private func note(_ what: PhoneNote.What = .skipped, at: Double = 1000) -> PhoneNote {
    PhoneNote(
      at: at, what: what, episode: "e1", show: "s1", start: 12.5, end: 60, kind: .ad)
  }

  private func object(_ line: String) throws -> [String: Any] {
    try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
  }

  func testALineHasTheContractsFields() throws {
    let fields = try object(note().line)
    XCTAssertEqual(fields["v"] as? Int, 1)
    XCTAssertEqual(fields["at"] as? Double, 1000)
    XCTAssertEqual(fields["what"] as? String, "skipped")
    XCTAssertEqual(fields["episode"] as? String, "e1")
    XCTAssertEqual(fields["show"] as? String, "s1")
    XCTAssertEqual(fields["start"] as? Double, 12.5)
    XCTAssertEqual(fields["end"] as? Double, 60)
    XCTAssertEqual(fields["kind"] as? String, "ad")
    XCTAssertFalse(note().line.contains("\n"))
  }

  func testAMissingEndOrKindIsNullAndAnUnknownShowIsEmpty() throws {
    let bare = PhoneNote(
      at: 5, what: .missed, episode: "e", show: nil, start: 1, end: nil, kind: nil)
    let fields = try object(bare.line)
    XCTAssertEqual(fields["show"] as? String, "")
    XCTAssertTrue(fields["end"] is NSNull)
    XCTAssertTrue(fields["kind"] is NSNull)
    XCTAssertEqual(fields["what"] as? String, "missed")
  }

  func testALineReadsBack() throws {
    let all: [PhoneNote] = [
      note(.skipped), note(.undone), note(.trimmed),
      PhoneNote(at: 5, what: .missed, episode: "e", show: nil, start: 1, end: nil, kind: nil),
    ]
    for original in all {
      let back = try JSONDecoder().decode(PhoneNote.self, from: Data(original.line.utf8))
      XCTAssertEqual(back, original)
    }
  }

  func testAppendingAddsALineAndKeepsTheNewest2000() {
    XCTAssertEqual(PendingNotes.appending("a", to: ""), "a\n")
    XCTAssertEqual(PendingNotes.appending("b", to: "a\n"), "a\nb\n")
    // A text that lost its final line break still gets a clean join.
    XCTAssertEqual(PendingNotes.appending("b", to: "a"), "a\nb\n")
    var text = ""
    for number in 1...2005 { text = PendingNotes.appending("line \(number)", to: text) }
    let lines = text.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, PendingNotes.maxLines)
    XCTAssertEqual(PendingNotes.maxLines, 2000)
    XCTAssertEqual(lines.first, "line 6")
    XCTAssertEqual(lines.last, "line 2005")
  }

  func testDroppingTakesTheFirstLinesOff() {
    let text = "a\nb\nc\n"
    XCTAssertEqual(PendingNotes.dropping(2, from: text), "c\n")
    XCTAssertEqual(PendingNotes.dropping(0, from: text), text)
    XCTAssertEqual(PendingNotes.dropping(-3, from: text), text)
    XCTAssertEqual(PendingNotes.dropping(3, from: text), "")
    XCTAssertEqual(PendingNotes.dropping(99, from: text), "")
    XCTAssertEqual(PendingNotes.dropping(1, from: ""), "")
    XCTAssertEqual(PendingNotes.dropping(1, from: "a\n\nb\n"), "b\n")
  }

  private func line(at: Double) -> String {
    PhoneNote(at: at, what: .missed, episode: "e", show: nil, start: 1, end: nil, kind: nil).line
  }

  private func text(_ times: [Double]) -> String {
    times.map { line(at: $0) }.joined(separator: "\n") + "\n"
  }

  func testDroppingByTimeKeepsANoteWrittenAfterTheRead() {
    let all = text([10, 20, 30])
    // The app read the first two and saw 20 as the newest: the third came in since.
    XCTAssertEqual(PendingNotes.dropping(3, upToAt: 20, from: all), text([30]))
    XCTAssertEqual(PendingNotes.dropping(1, upToAt: 20, from: all), text([20, 30]))
    XCTAssertEqual(PendingNotes.dropping(3, upToAt: 99, from: all), "")
    XCTAssertEqual(PendingNotes.dropping(3, upToAt: 5, from: all), all)
    XCTAssertEqual(PendingNotes.dropping(0, upToAt: 99, from: all), all)
  }

  func testDroppingByTimeSurvivesTheCapPushingOldLinesOut() {
    // At the cap the oldest line went out when a new one came in: a count alone would eat the new one.
    XCTAssertEqual(PendingNotes.dropping(3, upToAt: 30, from: text([20, 30, 40])), text([40]))
  }
}
