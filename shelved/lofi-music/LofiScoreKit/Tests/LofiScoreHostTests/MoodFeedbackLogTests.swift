import Foundation
import XCTest
@testable import LofiScoreHost

final class MoodFeedbackLogTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func entry(_ book: String, correction: Bool = false) -> MoodFeedbackLog.Entry {
        MoodFeedbackLog.Entry(
            bookID: book, sentence: 120, rejected: "tense", chosen: "mysterious", how: correction ? "picked" : "guess",
            correction: correction, readingSource: "track", engine: nil, track: "tense/Night Run - X"
        )
    }

    func testCountsChangesAndMissesPerBookAndKeepsThem() throws {
        let log = MoodFeedbackLog(folder: folder)
        XCTAssertNil(log.exportText())
        for _ in 0..<5 { log.noteChange(bookID: "a") }
        log.noteChange(bookID: "b")
        try log.record(entry("a"))
        try log.record(entry("a", correction: true))
        XCTAssertEqual(log.counts(bookID: "a"), .init(changes: 5, wrong: 1), "a correction is the same miss")
        XCTAssertEqual(log.counts(bookID: nil), .init(changes: 6, wrong: 1))

        let reopened = MoodFeedbackLog(folder: folder)
        XCTAssertEqual(reopened.counts(bookID: "a"), .init(changes: 5, wrong: 1))
        let text = try XCTUnwrap(reopened.exportText())
        XCTAssertTrue(text.hasPrefix("# Storyteller Lofi wrong-mood log: 1 of 6 mood changes marked wrong"))
        let lines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(MoodFeedbackLog.Entry.self, from: Data(lines[0].utf8))
        XCTAssertEqual(first.sentence, 120)
        XCTAssertEqual(first.how, "guess")
    }
}
