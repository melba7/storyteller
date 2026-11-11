import XCTest
@testable import LofiAtmosphere

final class ScoringProgressTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_794_363_375) // 9:16:15 PM in New York
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func progress(planned: Int = 475, already: Int = 0, probes: Int = 238) -> ScoringProgress {
        ScoringProgress(planned: planned, alreadyScored: already, probeBudget: probes, concurrency: 4, started: start, timeZone: newYork)
    }

    func testTheMainPassGivesScenesDoneAndAFinishTime() throws {
        let progress = progress()
        XCTAssertNil(progress.line(added: 7, now: start.addingTimeInterval(30)))
        // 110 scenes in 7 minutes: 365 left at the same pace is about 23 minutes.
        let line = try XCTUnwrap(progress.line(added: 110, dollars: 3.1, now: start.addingTimeInterval(420)))
        XCTAssertTrue(line.contains("110 of 475 scenes (23%)"), line)
        XCTAssertTrue(line.contains("about $3.10 so far"), line)
        XCTAssertTrue(line.contains("main pass done in about 23 min (9:46 PM)"), line)
        XCTAssertTrue(line.contains("up to 238 in-between checks"), line)
        XCTAssertTrue(line.contains("at the latest"), line)
    }

    func testAResumedRunCountsWhatWasAlreadyThere() throws {
        let progress = progress(already: 401, probes: 0)
        XCTAssertEqual(progress.toScore, 74)
        let line = try XCTUnwrap(progress.line(added: 20, now: start.addingTimeInterval(120)))
        XCTAssertTrue(line.contains("421 of 475 scenes (89%)"), line)
        XCTAssertTrue(line.contains("main pass done in about 5 min"), line)
        XCTAssertFalse(line.contains("in-between"), line)
    }

    func testTheChecksGetTheirOwnCountAndTime() throws {
        let progress = progress(planned: 20, probes: 40)
        XCTAssertNotNil(progress.line(added: 20, now: start.addingTimeInterval(200)))
        let first = try XCTUnwrap(progress.line(added: 21, now: start.addingTimeInterval(210)))
        XCTAssertTrue(first.contains("all 20 scenes done; in-between check 1 of at most 40"), first)
        XCTAssertNil(progress.line(added: 25, now: start.addingTimeInterval(230)))
        // 10 checks in the 100 s since the main pass ended: 30 left is at most 5 minutes.
        let later = try XCTUnwrap(progress.line(added: 30, now: start.addingTimeInterval(310)))
        XCTAssertTrue(later.contains("in-between check 10 of at most 40"), later)
        XCTAssertTrue(later.contains("done in at most 5 min"), later)
    }

    func testFailuresShowAtOnceAndDoNotStallTheCount() throws {
        let progress = progress(planned: 12, probes: 10)
        let first = try XCTUnwrap(progress.failure("ch2:s14: HTTP 429 You've hit your 5-hour limit"))
        XCTAssertTrue(first.contains("1 failed so far"), first)
        XCTAssertTrue(first.contains("5-hour limit"), first)
        XCTAssertNil(progress.failure("again"))
        // 10 of the 12 scenes arrive; the eleventh entry is the first check.
        let last = try XCTUnwrap(progress.line(added: 10, now: start.addingTimeInterval(60)))
        XCTAssertTrue(last.contains("10 of 12 scenes"), last)
        XCTAssertTrue(last.contains("2 failed"), last)
        let check = try XCTUnwrap(progress.line(added: 11, now: start.addingTimeInterval(70)))
        XCTAssertTrue(check.contains("main pass over (2 scenes failed); in-between check 1 of at most 10"), check)
    }
}
