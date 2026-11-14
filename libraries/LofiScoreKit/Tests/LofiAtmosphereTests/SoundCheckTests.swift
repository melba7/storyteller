import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// The sound check: a few spots of a book, picked from its track, for a quick listening test.
final class SoundCheckTests: XCTestCase {
    /// A 100-sentence chapter, with a scene every 10 sentences and a knock at sentence 55.
    private func track(_ scenes: [StoryScene], knockAt knock: Int? = 55) throws -> AtmosphereTrack {
        let guardian = try SpoilerGuard(chapters: [(0..<100).map { "Sentence \($0)." }])
        func at(_ index: Int) throws -> SentencePosition {
            try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
        }
        let entries = try scenes.enumerated().map { i, scene in
            AtmosphereTrack.Entry(position: try at(i * 10), sentence: "Sentence \(i * 10).", scene: scene)
        }
        let cues = try knock.map {
            [AtmosphereTrack.Cue(position: try at($0), sentence: "Sentence \($0).", sound: .doorKnock, wordsBefore: 0, words: 2)]
        } ?? []
        return AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: entries, cues: cues)
    }

    private let scenes: [StoryScene] = [
        .silent,                                                                                       // 0
        StoryScene(placeID: "p1", placeName: "the study", setting: .indoors, layers: [SceneLayer(.roomTone, .soft), SceneLayer(.clock, .faint)]), // 10
        StoryScene(placeID: "p2", placeName: "the hall", setting: .indoors, layers: [SceneLayer(.crowd, .loud)]),       // 20
        StoryScene(placeID: "p3", setting: .outdoors, layers: [SceneLayer(.forest, .full), SceneLayer(.birdsong, .soft)]), // 30
        StoryScene(placeID: "p4", setting: .outdoors, layers: [SceneLayer(.river, .full, variant: "runningTap")]),      // 40
        StoryScene(placeID: "p5", setting: .outdoors, layers: [SceneLayer(.heavyRain, .full)]),                        // 50
        StoryScene(placeID: "p6", setting: .vehicle, layers: [SceneLayer(.train, .full)]),                             // 60
        StoryScene(placeID: "p1", placeName: "the study", setting: .indoors, layers: [SceneLayer(.roomTone, .soft)]),   // 70
        StoryScene(placeID: "p7", setting: .indoors, layers: [SceneLayer(.fireplace, .full)]),                         // 80
        StoryScene(placeID: "p8", setting: .outdoors, layers: [SceneLayer(.seaShore, .full)]),                         // 90
    ]

    func testPicksOneSpotOfEachKindInBookOrder() throws {
        let spots = SoundCheck.spots(in: try track(scenes), count: 7)
        XCTAssertEqual(Set(spots.map(\.kind)), [.quietRoom, .loud, .outdoors, .water, .weather, .travel, .oneOff])
        XCTAssertEqual(spots.map(\.globalIndex), spots.map(\.globalIndex).sorted(), "played in book order")
        XCTAssertFalse(spots.contains { $0.globalIndex == 0 }, "a silent scene is never a spot")
        let loud = try XCTUnwrap(spots.first { $0.kind == .loud })
        XCTAssertEqual(loud.globalIndex, 20)
        XCTAssertEqual(loud.sounds, ["crowd"])
        XCTAssertEqual(loud.placeName, "the hall")
        let knock = try XCTUnwrap(spots.first { $0.kind == .oneOff })
        XCTAssertEqual(knock.globalIndex, 55)
        XCTAssertEqual(knock.sounds, ["doorKnock"])
        let water = try XCTUnwrap(spots.first { $0.kind == .water })
        XCTAssertTrue(water.sounds.contains("river.runningTap") || water.sounds.contains("seaShore"))
    }

    func testStopsAtTheCountAndFillsWithSoundsNotYetHeard() throws {
        XCTAssertEqual(SoundCheck.spots(in: try track(scenes), count: 3).count, 3)
        let many = SoundCheck.spots(in: try track(scenes), count: 9)
        XCTAssertEqual(many.count, 9)
        XCTAssertEqual(Set(many.map(\.globalIndex)).count, 9, "no spot twice")
    }

    func testNeverPicksASpotAtOrPastTheLimit() throws {
        // Spoiler safety: only what the listener has already heard.
        let spots = SoundCheck.spots(in: try track(scenes), before: 45, count: 7)
        XCTAssertFalse(spots.isEmpty)
        XCTAssertTrue(spots.allSatisfy { $0.globalIndex < 45 })
        XCTAssertFalse(spots.contains { $0.kind == .oneOff }, "the knock at 55 is past the limit")
    }

    func testAnEmptyOrSilentTrackHasNoSpots() throws {
        XCTAssertEqual(SoundCheck.spots(in: try track([.silent, .silent], knockAt: nil)), [])
        XCTAssertEqual(SoundCheck.spots(in: try track(scenes), count: 0), [])
    }
}
