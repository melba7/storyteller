import XCTest
import LofiScoreCore
@testable import LofiDirector

/// Replays recorded and generated timelines through the director, the way the plan asks:
/// pure logic, an injected clock, a whole book of readings in a fraction of a second.
final class ReplayTests: XCTestCase {
    func testHandWrittenReplaysMeetTheirExpectations() throws {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Replays", withExtension: nil))
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(urls.count, 8)
        for url in urls {
            let script = try ReplayScript.load(from: url)
            let result = ReplayRunner.run(script)
            XCTAssertTrue(
                result.passed,
                "\(url.lastPathComponent): " + result.failures.map { $0.description }.joined(separator: "; ")
            )
        }
    }

    func testTenHourBooksStayCalmAndFollowTheStory() {
        let config = DirectorConfig()
        var options = SyntheticBook.Options()
        options.hours = 10
        var rates: [Double] = []
        for seed in UInt64(1)...6 {
            let book = SyntheticBook.generate(seed: seed, options: options)
            let result = ReplayRunner.run(book.script, config: config)
            rates.append(result.changesPerHour)
            XCTAssertTrue(result.dwellViolations(minimumDwell: config.minimumDwell).isEmpty, "seed \(seed)")
            XCTAssertGreaterThan(result.agreement(with: book, lag: 120), 0.9, "seed \(seed)")
            let follow = result.followDelay(in: book)
            XCTAssertLessThan(follow.missed, 0.05, "seed \(seed)")
            XCTAssertLessThan(follow.median ?? .infinity, 180, "seed \(seed)")
        }
        // The plan's bar for the listening test: about eight changes an hour at most.
        let mean = rates.reduce(0, +) / Double(rates.count)
        XCTAssertLessThanOrEqual(mean, 8, "changes per hour: \(rates)")
    }

    func testReplaysAreDeterministic() {
        let book = SyntheticBook.generate(seed: 42, options: SyntheticBook.Options())
        let first = ReplayRunner.run(book.script)
        let second = ReplayRunner.run(book.script)
        XCTAssertEqual(first.decisions, second.decisions)
        XCTAssertFalse(first.decisions.isEmpty)
    }

    /// No lookahead, at the director level: what the music does up to time T depends only on
    /// events up to T. Rewriting everything after T must leave every earlier decision unchanged.
    func testDecisionsNeverDependOnLaterEvents() {
        var rng = SplitMix64(seed: 7)
        for seed in UInt64(100)..<110 {
            var options = SyntheticBook.Options()
            options.hours = 2
            let book = SyntheticBook.generate(seed: seed, options: options)
            let original = ReplayRunner.run(book.script)
            let cut = rng.nextUnit() * (book.script.duration ?? 3600)

            var rewritten = book.script
            rewritten.events = rewritten.events.map { event in
                guard event.t > cut else { return event }
                var changed = event
                if changed.reading != nil {
                    let bucket = MoodBucket.allCases.randomElement(using: &rng) ?? .tense
                    changed.reading = ReplayReading(bucket: bucket, confidence: rng.nextUnit())
                }
                return changed
            }
            // Delete a random share of the later events as well.
            rewritten.events.removeAll { $0.t > cut && rng.nextUnit() < 0.3 }

            let replayed = ReplayRunner.run(rewritten)
            let before = original.decisions.filter { $0.time <= cut }
            let after = replayed.decisions.filter { $0.time <= cut }
            XCTAssertEqual(before, after, "seed \(seed), cut at \(cut)")
        }
    }

    func testScriptsRoundTripThroughJSON() throws {
        let book = SyntheticBook.generate(seed: 3, options: SyntheticBook.Options())
        let data = try book.script.jsonData()
        let decoded = try JSONDecoder().decode(ReplayScript.self, from: data)
        XCTAssertEqual(decoded, book.script)
    }
}
