import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// A stand-in for Claude: reads the scene from markers in the window's last sentences, like
/// "[tavern]", and checks that it is never shown anything past the window's own sentence.
final class MarkerSceneEngine: SceneEngine, @unchecked Sendable {
    let id = "marker/1"
    private let lock = NSLock()
    private(set) var calls: [(position: Int, knownPlaces: [String], newestMemory: Int?)] = []

    static let places: [String: (name: String, layers: [SceneLayer])] = [
        "tavern": ("the tavern", [SceneLayer(.fireplace, .full)]),
        "street": ("the high street", [SceneLayer(.oldTown)]),
        "hall": ("the great hall", [SceneLayer(.crowd), SceneLayer(.fireplace, .faint)]),
        "rain": ("", []),
    ]

    func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
        lock.withLock {
            calls.append((window.position.globalIndex, memory.places.keys.sorted(), memory.places.values.map(\.lastSeen).max()))
        }
        // The newest marker in the window decides the place; "[rain]" adds rain until "[dry]".
        var place: String?
        var raining = false
        for line in window.lines {
            for key in ["tavern", "street", "hall"] where line.text.contains("[\(key)]") { place = key }
            if line.text.contains("[rain]") { raining = true }
            if line.text.contains("[dry]") { raining = false }
        }
        guard let key = place, let info = Self.places[key] else {
            return SceneAnswer(place: .none, scene: StoryScene(placeID: nil, layers: [], confidence: 0.9), world: nil)
        }
        var layers = info.layers
        if raining { layers.append(SceneLayer(key == "street" ? .rain : .rainIndoors, .soft)) }
        let scene = StoryScene(placeID: nil, placeName: info.name, setting: key == "street" ? .outdoors : .indoors, layers: layers, confidence: 0.9)
        if let known = memory.place(named: info.name) {
            return SceneAnswer(place: .known(known.id), scene: scene, world: "a market town")
        }
        return SceneAnswer(place: .new(info.name), scene: scene, world: "a market town")
    }
}

final class BuilderTests: XCTestCase {
    /// Two chapters: street, then the tavern (rain starts), back to the street, then the hall.
    static func book() throws -> SpoilerGuard {
        var one = (0..<60).map { "Plain sentence number \($0) with a few more words in it." }
        one[2] = "They walked down the cobbles. [street]"
        one[25] = "They pushed into the warm room. [tavern]"
        one[40] = "Outside, it began to pour. [rain]"
        var two = (0..<60).map { "Another plain sentence, number \($0), with some words." }
        two[2] = "Back out on the cobbles they went. [street]"
        two[30] = "The doors of the hall swung open. [hall]"
        return try SpoilerGuard(chapters: [one, two])
    }

    func testBuildsInOrderWithOnlyEarlierPlacesAndPinsChanges() async throws {
        let guardian = try Self.book()
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "marker/1", bookID: "test", wordsBetweenEntries: 60))
        let engine = MarkerSceneEngine()
        let report = try await builder.build(into: store, engine: engine, concurrency: 3)
        XCTAssertEqual(report.failed, 0)
        XCTAssertGreaterThan(report.probes, 0)

        // Spoiler property: every request saw only places from entries before its sentence.
        for call in engine.calls {
            if let newest = call.newestMemory { XCTAssertLessThan(newest, call.position) }
        }

        let track = store.snapshot
        XCTAssertEqual(track.chapterStarts, [0, 60])
        func scene(at chapter: Int, _ sentence: Int) throws -> StoryScene? {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: chapter, sentenceIndex: sentence))
            return track.entry(atOrBefore: position.globalIndex)?.scene
        }
        // The street returns with the same id; the tavern keeps its own.
        let street = try XCTUnwrap(try scene(at: 0, 10)?.placeID)
        let tavern = try XCTUnwrap(try scene(at: 0, 30)?.placeID)
        XCTAssertNotEqual(street, tavern)
        XCTAssertEqual(try scene(at: 1, 10)?.placeID, street)
        XCTAssertEqual(try scene(at: 1, 50)?.layers.first?.sound, .crowd)
        // Rain is heard indoors once it starts, and not before.
        XCTAssertEqual(try scene(at: 0, 45)?.level(of: .rainIndoors), .soft)
        XCTAssertNil(try scene(at: 0, 39)?.level(of: .rainIndoors))

        // Each change is pinned to within the resolution, never before its sentence.
        for (marker, chapter) in [(25, 0), (40, 0), (30, 1)] {
            let turn = try XCTUnwrap(try guardian.position(chapterOrdinal: chapter, sentenceIndex: marker)).globalIndex
            let before = track.entry(atOrBefore: turn - 1)?.scene
            let at = track.entries.first { $0.globalIndex >= turn }
            XCTAssertNotNil(before)
            let first = try XCTUnwrap(at)
            XCTAssertLessThanOrEqual(first.globalIndex - turn, 3, "change at \(turn) pinned at \(first.globalIndex)")
        }
    }

    func testResumesWithoutRescoring() async throws {
        let guardian = try Self.book()
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60, refinement: nil))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "marker/1", bookID: "test", wordsBetweenEntries: 60))
        let first = try await builder.build(into: store, engine: MarkerSceneEngine())
        XCTAssertGreaterThan(first.scored, 0)
        let again = MarkerSceneEngine()
        let second = try await builder.build(into: store, engine: again)
        XCTAssertEqual(second.scored, 0)
        XCTAssertEqual(second.alreadyScored, first.planned)
        XCTAssertTrue(again.calls.isEmpty)
    }

    func testSpendingCapStopsTheRun() async throws {
        let guardian = try Self.book()
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "marker/1", bookID: "test", wordsBetweenEntries: 60))
        let counter = Counter()
        let report = try await builder.build(into: store, engine: MarkerSceneEngine(), continueIf: { counter.next() < 3 })
        XCTAssertTrue(report.stoppedEarly)
        XCTAssertEqual(report.scored, 3)
    }

    func testAProbeAtTheStartOfANewPlaceTakesItsId() throws {
        let guardian = try SpoilerGuard(chapters: [(0..<20).map { "S\($0)." }])
        var track = AtmosphereTrack(engineID: "t", bookID: "b", wordsBetweenEntries: 10)
        let p5 = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 5))
        let p15 = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 15))
        track.insert(.init(position: p5, sentence: "S5.", scene: StoryScene(placeID: "p1", placeName: "the kitchen", layers: [])))
        let garden = AtmosphereTrack.Entry(position: p15, sentence: "S15.", scene: StoryScene(placeID: "p2", placeName: "the walled garden", layers: [SceneLayer(.birdsong)]))
        track.insert(garden)
        XCTAssertEqual(AtmosphereTrackBuilder.idForNewPlace(named: "the garden", before: 10, nextEntry: garden, in: track), "p2")
        XCTAssertEqual(AtmosphereTrackBuilder.idForNewPlace(named: "the hallway", before: 10, nextEntry: garden, in: track), "p3")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
