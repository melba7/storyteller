import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// The marker engine, which also says where its scene began: the first words of the
/// passage's sentence with the newest marker, when the scene is not the one before the
/// passage. `hints` off makes it the plain marker engine.
final class HintingSceneEngine: SceneEngine, @unchecked Sendable {
    let id = "hinting/1"
    let inner = MarkerSceneEngine()
    let hints: Bool

    init(hints: Bool = true) {
        self.hints = hints
    }

    func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
        var answer = try await inner.scene(for: window, memory: memory)
        guard hints else { return answer }
        let before = memory.current ?? .silent
        let sameSounds = Set(before.layers.map(\.key)) == Set(answer.scene.layers.map(\.key))
        let samePlace: Bool
        switch answer.place {
        case let .known(id): samePlace = before.placeID == id
        case .new: samePlace = false
        case .none: samePlace = before.placeID == nil
        }
        guard !(samePlace && sameSounds),
              let line = window.lines.last(where: { $0.text.contains("[") })
        else { return answer }
        answer.since = line.text.split(separator: " ").prefix(4).joined(separator: " ")
        return answer
    }
}

final class SceneChangeTests: XCTestCase {
    static let tavern = StoryScene(placeID: "p1", layers: [SceneLayer(.fireplace, .full), SceneLayer(.crowd, .soft)])
    static let street = StoryScene(placeID: "p2", layers: [SceneLayer(.oldTown)])

    /// One chapter of short sentences, so a sentence's index is its global index.
    static let guardian = try! SpoilerGuard(chapters: [(0..<120).map { "S\($0)." }])

    static func entry(_ globalIndex: Int, _ scene: StoryScene, confidence: Double = 0.9, start: Int? = nil) -> AtmosphereTrack.Entry {
        var scene = scene
        scene.confidence = confidence
        let position = try! guardian.position(chapterOrdinal: 0, sentenceIndex: globalIndex)!
        return .init(position: position, sentence: "S\(globalIndex).", scene: scene, sceneStart: start)
    }

    // MARK: - How different two scenes sound

    func testDifferenceIsZeroForTheSameSoundAndOneForNothingShared() {
        XCTAssertEqual(Self.tavern.difference(from: Self.tavern), 0)
        XCTAssertEqual(Self.tavern.difference(from: Self.street), 1)
        XCTAssertEqual(Self.street.difference(from: Self.tavern), 1)
        // No sound in either: nothing to hear, whatever the places.
        XCTAssertEqual(StoryScene(placeID: "p1", layers: []).difference(from: StoryScene(placeID: "p2", layers: [])), 0)
        // Sound against silence is a full change.
        XCTAssertEqual(Self.tavern.difference(from: .silent), 1)
    }

    func testSmallChangesAreSmallDifferences() {
        let otherRoom = StoryScene(placeID: "p9", layers: Self.tavern.layers)
        XCTAssertEqual(Self.tavern.difference(from: otherRoom), StoryScene.otherPlaceDifference, accuracy: 1e-9)

        let louder = StoryScene(placeID: "p1", layers: [SceneLayer(.fireplace, .full), SceneLayer(.crowd, .full)])
        let withRain = StoryScene(placeID: "p1", layers: Self.tavern.layers + [SceneLayer(.rainIndoors, .soft)])
        let cafe = StoryScene(placeID: "p1", layers: [SceneLayer(.fireplace, .full), SceneLayer(.crowd, .soft, variant: "cafe")])
        for near in [louder, withRain, cafe] {
            let d = Self.tavern.difference(from: near)
            XCTAssertGreaterThan(d, 0)
            XCTAssertLessThan(d, 0.5, "\(near)")
            XCTAssertEqual(d, near.difference(from: Self.tavern), accuracy: 1e-9)
        }
        // A kind of the same family is nearer than another sound altogether.
        let other = StoryScene(placeID: "p1", layers: [SceneLayer(.fireplace, .full), SceneLayer(.birdsong, .soft)])
        XCTAssertLessThan(Self.tavern.difference(from: cafe), Self.tavern.difference(from: other))
    }

    // MARK: - Which changes are heard

    func testAnUnsureEntryIsNotAChange() {
        let finder = SceneChangeFinder()
        let unsure = StoryScene(placeID: nil, layers: [])
        // Sure of the tavern, unsure, sure of the tavern again: the tavern never stops.
        let held = [Self.entry(0, Self.tavern), Self.entry(15, unsure, confidence: 0.2), Self.entry(30, Self.tavern)]
        XCTAssertTrue(finder.changes(in: held).isEmpty)

        // Sure of the tavern, unsure, sure of the street: one change, at the street, and
        // it is the gap after the unsure entry that is worth narrowing.
        let moved = [Self.entry(0, Self.tavern), Self.entry(15, unsure, confidence: 0.2), Self.entry(30, Self.street)]
        let changes = finder.changes(in: moved)
        XCTAssertEqual(changes.map(\.at), [30])
        XCTAssertEqual(changes[0].from, 15)
        XCTAssertEqual(changes[0].before.placeID, "p1")
        XCTAssertEqual(changes[0].difference, 1)
        XCTAssertEqual(changes[0].probe, 22)
        XCTAssertFalse(changes[0].hinted)
    }

    func testSilentPlacesAreNotChanges() {
        let hall = StoryScene(placeID: "p3", layers: [])
        let stairs = StoryScene(placeID: "p4", layers: [])
        let entries = [Self.entry(0, hall), Self.entry(15, stairs), Self.entry(30, Self.street), Self.entry(45, hall)]
        // Hall to stairs is silent both sides; the street starting and stopping is heard.
        XCTAssertEqual(SceneChangeFinder().changes(in: entries).map(\.at), [30, 45])
    }

    func testASceneTooOldHasAlreadyFaded() {
        let finder = SceneChangeFinder(maxLagSentences: 80)
        let unsure = StoryScene(placeID: nil, layers: [])
        var entries = [Self.entry(0, Self.tavern)]
        entries += stride(from: 15, through: 90, by: 15).map { Self.entry($0, unsure, confidence: 0.1) }
        entries.append(Self.entry(105, Self.tavern))
        // The tavern faded to silence after 80 sentences, so its return is heard.
        let changes = finder.changes(in: entries)
        XCTAssertEqual(changes.map(\.at), [105])
        XCTAssertTrue(changes[0].before.isSilent)
    }

    func testLevelsAloneAreNotNarrowed() {
        let louder = StoryScene(placeID: "p1", layers: [SceneLayer(.fireplace, .full), SceneLayer(.crowd, .full)])
        XCTAssertTrue(SceneChangeFinder().changes(in: [Self.entry(0, Self.tavern), Self.entry(15, louder)]).isEmpty)
    }

    // MARK: - Where to score next

    func testPinnedWithinTheResolutionOrByItsOwnAnswer() {
        let finder = SceneChangeFinder(resolutionSentences: 3)
        XCTAssertEqual(finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(3, Self.street)]).map(\.isPinned), [true])
        XCTAssertEqual(finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(4, Self.street)]).map(\.probe), [2])

        // The street's answer, made from the text up to sentence 15, says it starts there.
        let own = finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(15, Self.street, start: 15)])
        XCTAssertEqual(own.map(\.isPinned), [true])
        XCTAssertEqual(own.map(\.pinnedByAnswer), [true])

        // A swell is pinned to its sentence, not to within three.
        var swell = Self.street
        swell.moment = .swell
        XCTAssertEqual(finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(3, swell)]).map(\.probe), [1])
        // So is a transition, whose door or engine plays on that sentence.
        var throughADoor = Self.street
        throughADoor.transition = SceneTransition.allCases.first
        XCTAssertNotNil(throughADoor.transition)
        XCTAssertEqual(finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(3, throughADoor)]).map(\.probe), [1])
        // And a change the player gives a door by itself: out of a room with voices.
        var indoors = Self.tavern
        indoors.setting = .indoors
        var outdoors = Self.street
        outdoors.setting = .outdoors
        XCTAssertNotNil(SceneTransition.inferred(from: indoors, to: outdoors))
        XCTAssertEqual(finder.changes(in: [Self.entry(0, indoors), Self.entry(3, outdoors)]).map(\.probe), [1])
    }

    func testAHintInsideTheGapIsScoredFirst() {
        let finder = SceneChangeFinder()
        let hinted = finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(15, Self.street, start: 11)])
        XCTAssertEqual(hinted.map(\.probe), [11])
        XCTAssertEqual(hinted.map(\.hinted), [true])
        // A hint at or before the earlier entry, which did not hear the street yet, is no
        // help: back to halving.
        for start in [0, -4] {
            let stale = finder.changes(in: [Self.entry(0, Self.tavern), Self.entry(15, Self.street, start: start)])
            XCTAssertEqual(stale.map(\.probe), [7])
            XCTAssertEqual(stale.map(\.hinted), [false])
        }
    }

    func testTheMostAudibleAndWidestChangesComeFirst() throws {
        let narrated = try AtmosphereTrackBuilder(spoilerGuard: Self.guardian).narratedPositions()
        let withRain = StoryScene(placeID: "p1", layers: Self.tavern.layers + [SceneLayer(.rainIndoors, .soft)])
        let unsure = StoryScene(placeID: "p7", layers: [SceneLayer(.wind)])
        let entries = [
            Self.entry(0, Self.tavern),
            Self.entry(16, withRain),                      // a little different, 16 apart
            Self.entry(32, Self.street),                   // all different, 16 apart
            Self.entry(48, unsure, confidence: 0.2),       // not played
            Self.entry(60, Self.tavern),                   // all different, 12 apart
        ]
        let probes = AtmosphereTrackBuilder.refinableChanges(in: entries, narrated: narrated, finder: SceneChangeFinder(), excluding: [])
        XCTAssertEqual(probes.map(\.globalIndex), [24, 54, 8])
        let skipping = AtmosphereTrackBuilder.refinableChanges(in: entries, narrated: narrated, finder: SceneChangeFinder(), excluding: [24])
        XCTAssertEqual(skipping.map(\.globalIndex), [54, 8])
    }

    func testFindingTheQuotedSentence() throws {
        let guardian = try SpoilerGuard(chapters: [[
            "They walked down the hill.", "The door was open.", "They walked into the warm room.", "It was loud inside, and they walked on.",
        ]])
        let last = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 3))
        let window = try guardian.window(at: last)
        XCTAssertEqual(SceneChangeFinder.line(startingWith: "They walked into the warm", in: window), 2)
        XCTAssertEqual(SceneChangeFinder.line(startingWith: "“They walked down—the hill”", in: window), 0)
        // Words from inside a sentence still find it; the newest sentence that starts with them wins.
        XCTAssertEqual(SceneChangeFinder.line(startingWith: "loud inside", in: window), 3)
        XCTAssertEqual(SceneChangeFinder.line(startingWith: "They walked", in: window), 2)
        XCTAssertNil(SceneChangeFinder.line(startingWith: "They", in: window))
        XCTAssertNil(SceneChangeFinder.line(startingWith: "not in the passage", in: window))
        // An answer that ran on into the next sentence still finds the first.
        XCTAssertEqual(SceneChangeFinder.line(startingWith: "The door was open. They walked into the warm room.", in: window), 1)
    }

    // MARK: - Building with hints

    func testHintsPinEveryChangeToItsSentenceWithFewerRequests() async throws {
        let guardian = try BuilderTests.book()
        func build(hints: Bool) async throws -> (track: AtmosphereTrack, report: AtmosphereTrackBuilder.Report, engine: HintingSceneEngine) {
            let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
            let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "hinting/1", bookID: "test", wordsBetweenEntries: 60))
            let engine = HintingSceneEngine(hints: hints)
            let report = try await builder.build(into: store, engine: engine, concurrency: 3)
            return (store.snapshot, report, engine)
        }
        let plain = try await build(hints: false)
        let hinted = try await build(hints: true)
        XCTAssertEqual(hinted.report.failed, 0)

        // Spoiler property, as without hints: every request saw only places from entries
        // before its sentence, and a sound is in the track only from its marker on.
        for call in hinted.engine.inner.calls {
            if let newest = call.newestMemory { XCTAssertLessThan(newest, call.position) }
        }
        // (The book's first sound, on sentence 2, has no entry before it to change from.)
        let turns = try [(25, 0), (40, 0), (2, 1), (30, 1)].map { marker, chapter in
            try XCTUnwrap(try guardian.position(chapterOrdinal: chapter, sentenceIndex: marker)).globalIndex
        }
        for turn in turns {
            // The new sound starts exactly on its sentence, not a sentence later or sooner.
            let before = try XCTUnwrap(hinted.track.entry(atOrBefore: turn - 1)?.scene)
            let at = try XCTUnwrap(hinted.track.entries.first { $0.globalIndex == turn }, "no entry on \(turn)")
            XCTAssertTrue(SceneChangeFinder.differ(before, at.scene), "nothing changes at \(turn)")
            XCTAssertEqual(at.sceneStart, turn)
        }
        // One more change is heard: the marker engine's rain stops once its sentence has
        // left the window. Its hint (the newest marker, from before the last entry) is no
        // help, so that one is found by halving.
        XCTAssertEqual(hinted.report.changes, turns.count + 1)
        XCTAssertEqual(hinted.report.pinnedChanges, turns.count + 1)
        XCTAssertEqual(hinted.report.unrefinedChanges, 0)
        // Without hints the same changes are found by halving: more requests, each change
        // within three sentences, and the budget runs out before the ones that play a
        // door are all on their own sentence.
        XCTAssertEqual(plain.report.changes, turns.count + 1)
        XCTAssertLessThan(plain.report.pinnedChanges, hinted.report.pinnedChanges)
        for turn in turns {
            let first = try XCTUnwrap(plain.track.entries.first { $0.globalIndex >= turn })
            XCTAssertLessThanOrEqual(first.globalIndex - turn, 3, "change at \(turn) pinned at \(first.globalIndex)")
        }
        XCTAssertLessThan(hinted.report.probes, plain.report.probes)
    }

    func testOldTracksWithoutHintsStillLoad() throws {
        let track = AtmosphereTrack(
            engineID: "t", bookID: "b", wordsBetweenEntries: 250,
            entries: [Self.entry(0, Self.tavern), Self.entry(15, Self.street, start: 11)]
        )
        let data = try track.encoded()
        XCTAssertEqual(try AtmosphereTrack.decode(data).entries.map(\.sceneStart), [nil, 11])
        // A file written before the field existed has no such key.
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).replacingOccurrences(of: "\"sceneStart\":11,", with: "")
        XCTAssertFalse(json.contains("sceneStart"))
        XCTAssertEqual(try AtmosphereTrack.decode(Data(json.utf8)).entries.map(\.sceneStart), [nil, nil])
    }
}
