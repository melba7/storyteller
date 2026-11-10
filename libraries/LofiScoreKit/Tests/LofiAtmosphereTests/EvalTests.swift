import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiMood
import LofiText

/// The scene eval set: loading cases, building their memory and window, and scoring an
/// answer against what a case expects.
final class EvalTests: XCTestCase {
    private let sample = """
        # A comment and a blank line are skipped.

        {"id":"inn-stays","book":"demo","tags":["place"],"chapters":[["The fire crackled.","The captain told of storms at sea.","Nobody spoke."]],"memory":{"world":"an English coast inn","current":"p1","places":[{"id":"p1","name":"the Admiral Benbow inn","setting":"indoors","sounds":"murmur soft, fireplace faint","state":"evening"}]},"expect":{"place":"p1","setting":"indoors","main":["murmur","fireplace","roomTone"],"forbidden":["openSea","ship"],"state":["evening","night"],"oneShot":"none","transition":["none"],"since":"none"}}
        {"id":"storm-breaks","book":"demo","tags":["transition"],"chapters":[["We walked in the orchard.","A flash lit the sky.","The rain rushed down."]],"memory":{"current":"p1","places":[{"id":"p1","name":"the orchard","setting":"outdoors","sounds":"nightInsects soft"}]},"expect":{"place":"p1","main":["heavyRain","rain"],"kinds":{"rain":["rainOnLeaves"]},"moment":"swell","transition":["stormBreaks"],"since":"The rain rushed down.","oneShot":"thunderClap"}}
        {"id":"heading","book":"demo","chapters":[["She shut the door."],["CHAPTER II"]],"expect":{"place":"none"}}
        """

    private func cases() throws -> [SceneEvalCase] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        try sample.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try SceneEvalCase.load(from: url)
    }

    func testCasesLoadWithMemoryAndWindow() throws {
        let cases = try cases()
        XCTAssertEqual(cases.map(\.id), ["inn-stays", "storm-breaks", "heading"])

        let inn = cases[0]
        let window = try inn.window()
        XCTAssertEqual(window.lines.map(\.text), ["The fire crackled.", "The captain told of storms at sea.", "Nobody spoke."])
        let memory = try inn.placeMemory()
        XCTAssertEqual(memory.world, "an English coast inn")
        XCTAssertEqual(memory.current?.placeID, "p1")
        XCTAssertEqual(memory.places["p1"]?.name, "the Admiral Benbow inn")
        XCTAssertEqual(memory.places["p1"]?.layers, [SceneLayer(.murmur, .soft), SceneLayer(.fireplace, .faint)])
        XCTAssertEqual(memory.places["p1"]?.state, "evening")

        let heading = cases[2]
        XCTAssertEqual(try heading.window().lines.last?.text, "CHAPTER II")
        XCTAssertNil(try heading.placeMemory().current?.placeID, "a case without memory starts from nothing")
    }

    func testDuplicateIDsAreRefused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        try """
            {"id":"a","chapters":[["One."]],"expect":{"place":"any"}}
            {"id":"a","chapters":[["Two."]],"expect":{"place":"any"}}
            """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SceneEvalCase.load(from: url))
    }

    func testChecksScoreAnAnswer() throws {
        let cases = try cases()
        let inn = cases[0]
        let window = try inn.window()

        let right = SceneAnswer(
            place: .known("p1"),
            scene: StoryScene(placeID: nil, setting: .indoors, layers: [SceneLayer(.murmur, .soft), SceneLayer(.fireplace, .faint)], confidence: 0.8, state: "evening, the captain drinking"),
            world: nil
        )
        let checks = SceneEvaluator.checks(for: inn, answer: right, window: window)
        XCTAssertEqual(checks.values.filter { !$0 }.count, 0, "\(checks)")
        XCTAssertEqual(Set(checks.keys), ["place", "setting", "main", "forbidden", "state", "oneShot", "transition", "since", "heard"])

        let wrong = SceneAnswer(
            place: .new("the Spanish Main"),
            scene: StoryScene(placeID: nil, setting: .vehicle, layers: [SceneLayer(.ship, .full), SceneLayer(.openSea, .soft)], confidence: 0.2, transition: .boardVehicle),
            world: nil,
            oneShot: OneShotMention(sound: .thunderClap, quote: "storms at sea"),
            since: "The captain told"
        )
        let missed = SceneEvaluator.checks(for: inn, answer: wrong, window: window).filter { !$0.value }.keys
        XCTAssertEqual(Set(missed), ["place", "setting", "main", "forbidden", "state", "oneShot", "transition", "since", "heard"],
                       "a remembered place taken for the scene fails every check")
    }

    func testOneShotAndSinceMustBeFoundInThePassage() throws {
        let storm = try cases()[1]
        let window = try storm.window()
        let scene = StoryScene(
            placeID: nil, setting: .outdoors, layers: [SceneLayer(.heavyRain, .full), SceneLayer(.rain, .soft, variant: "rainOnLeaves")],
            confidence: 0.9, moment: .swell, transition: .stormBreaks
        )
        let placed = SceneAnswer(
            place: .known("p1"), scene: scene, world: nil,
            oneShot: OneShotMention(sound: .thunderClap, quote: "A flash lit the sky"), since: "The rain rushed"
        )
        let good = SceneEvaluator.checks(for: storm, answer: placed, window: window)
        XCTAssertEqual(good.filter { !$0.value }.count, 0, "\(good)")

        let misplaced = SceneAnswer(
            place: .known("p1"), scene: scene, world: nil,
            oneShot: OneShotMention(sound: .thunderClap, quote: "thunder rolled"), since: "A flash lit"
        )
        let bad = SceneEvaluator.checks(for: storm, answer: misplaced, window: window)
        XCTAssertEqual(bad["oneShot"], false, "a quote not in the passage cannot be placed")
        XCTAssertEqual(bad["since"], false, "since names the wrong sentence")

        let plain = SceneAnswer(
            place: .known("p1"),
            scene: StoryScene(placeID: nil, setting: .outdoors, layers: [SceneLayer(.rain, .full)], confidence: 0.9, moment: .swell, transition: .stormBreaks),
            world: nil, oneShot: OneShotMention(sound: .thunderClap, quote: "A flash lit the sky"), since: "The rain rushed down."
        )
        let kinds = SceneEvaluator.checks(for: storm, answer: plain, window: window)
        XCTAssertEqual(kinds["kinds"], false, "the plain family where a kind was expected is a miss")
        XCTAssertEqual(kinds["main"], true)
    }

    func testHeadingWantsNoPlaceAndNoSound() throws {
        let heading = try cases()[2]
        let window = try heading.window()
        let silent = SceneAnswer(place: .none, scene: StoryScene(placeID: nil, layers: [], confidence: 0.2), world: nil)
        XCTAssertEqual(SceneEvaluator.checks(for: heading, answer: silent, window: window), ["place": true])
        let guessed = SceneAnswer(place: .new("a house"), scene: StoryScene(placeID: nil, layers: [SceneLayer(.roomTone)], confidence: 0.6), world: nil)
        XCTAssertEqual(SceneEvaluator.checks(for: heading, answer: guessed, window: window)["place"], false)
    }

    func testRunReplayAndReport() async throws {
        let cases = try cases()
        struct Canned: SceneEngine {
            let id = "canned"
            func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
                if window.lines.last?.text == "CHAPTER II" {
                    return SceneAnswer(place: .none, scene: StoryScene(placeID: nil, layers: [], confidence: 0.1), world: nil)
                }
                if window.lines.last?.text == "The rain rushed down." {
                    throw SceneEngineError.generationFailed("no answer")
                }
                return SceneAnswer(
                    place: .known("p1"),
                    scene: StoryScene(placeID: nil, setting: .indoors, layers: [SceneLayer(.murmur, .soft)], confidence: 0.7, state: "evening"),
                    world: "an inn"
                )
            }
        }
        let results = await SceneEvaluator.run(cases, engine: Canned(), concurrency: 2)
        XCTAssertEqual(results.map(\.id), cases.map(\.id), "results keep the cases' order")
        XCTAssertTrue(results[0].passed)
        XCTAssertNotNil(results[1].error)
        XCTAssertFalse(results[1].passed)
        XCTAssertTrue(results[2].passed)

        let summary = SceneEvaluator.summary(cases, results: results)
        XCTAssertEqual(summary.passed, 2)
        XCTAssertEqual(summary.errors, 1)
        XCTAssertEqual(summary.cases, 3)
        XCTAssertEqual(summary.byCheck["place"]?.passed, 2)
        XCTAssertEqual(summary.byTag["transition"]?.passed, 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try results.map { try encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let saved = try SceneEvalResult.load(from: url)
        let replayed = SceneEvaluator.replay(cases, results: saved)
        XCTAssertEqual(replayed.map(\.passed), results.map(\.passed), "re-checking saved answers gives the same verdicts")

        let report = SceneEvaluator.report(cases, results: results, engineID: "canned", verbose: false)
        XCTAssertTrue(report.contains("2 of 3 cases pass every check"), report)
        XCTAssertTrue(report.contains("storm-breaks"), "the failed case is listed")
        XCTAssertFalse(report.contains("+ inn-stays"), "passing cases are listed only when verbose")
    }
}
