import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// The sound check: a few spots of a book, picked from its track, for a quick listening test.
final class SoundCheckTests: XCTestCase {
    /// One 200-sentence chapter (unless `chapterStarts` says more), a scene every 10
    /// sentences from `scenes`, and the given one-offs.
    private func track(_ scenes: [StoryScene], cues: [Int] = [], chapterStarts: [Int] = [0]) throws -> AtmosphereTrack {
        let guardian = try SpoilerGuard(chapters: [(0..<200).map { "Sentence \($0)." }])
        func at(_ index: Int) throws -> SentencePosition {
            try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
        }
        let entries = try scenes.enumerated().map { i, scene in
            AtmosphereTrack.Entry(position: try at(i * 10), sentence: "Sentence \(i * 10).", scene: scene)
        }
        let made = try cues.map {
            AtmosphereTrack.Cue(position: try at($0), sentence: "Sentence \($0).", sound: .doorKnock, wordsBefore: 0, words: 2)
        }
        return AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, chapterStarts: chapterStarts, entries: entries, cues: made)
    }

    private func scene(_ id: String, _ setting: StoryScene.Setting, _ layers: [SceneLayer], confidence: Double = 0.9, place: String? = nil, transition: SceneTransition? = nil) -> StoryScene {
        StoryScene(placeID: id, placeName: place, setting: setting, layers: layers, confidence: confidence, transition: transition)
    }

    private var scenes: [StoryScene] {
        [
            .silent,                                                                                         // 0
            scene("p1", .indoors, [SceneLayer(.roomTone, .soft), SceneLayer(.clock, .faint)], place: "the study"), // 10
            scene("p2", .indoors, [SceneLayer(.crowd, .loud)], place: "the hall"),                          // 20
            scene("p3", .outdoors, [SceneLayer(.forest, .full), SceneLayer(.birdsong, .soft)]),             // 30
            scene("p4", .outdoors, [SceneLayer(.river, .full, variant: "runningTap")]),                     // 40
            scene("p5", .outdoors, [SceneLayer(.heavyRain, .full)]),                                        // 50
            scene("p6", .vehicle, [SceneLayer(.train, .full)]),                                             // 60
            scene("p1", .indoors, [SceneLayer(.roomTone, .soft)], place: "the study"),                      // 70
            scene("p7", .indoors, [SceneLayer(.fireplace, .full)]),                                         // 80
            scene("p8", .outdoors, [SceneLayer(.seaShore, .full)]),                                         // 90
            .silent,                                                                                        // 100
        ]
    }

    func testPicksOneSpotOfEachKindInBookOrderWithAOneOffOfItsOwn() throws {
        let spots = SoundCheck.spots(in: try track(scenes, cues: [75]), before: 200, count: 7)
        XCTAssertEqual(spots.map(\.kind), [.quietRoom, .loud, .outdoors, .water, .weather, .travel, .oneOff])
        XCTAssertEqual(spots.map(\.globalIndex), spots.map(\.globalIndex).sorted(), "played in book order")
        let loud = try XCTUnwrap(spots.first { $0.kind == .loud })
        XCTAssertEqual(loud.globalIndex, 20)
        XCTAssertEqual(loud.lastIndex, 29, "the stop ends where the scene changes")
        XCTAssertEqual(loud.sounds, [.init(key: "crowd", level: .loud)])
        XCTAssertEqual(loud.placeName, "the hall")
        let knock = try XCTUnwrap(spots.first { $0.kind == .oneOff })
        XCTAssertEqual(knock.cueIndex, 75)
        XCTAssertEqual(knock.sounds, [.init(key: "doorKnock", level: nil)])

        let six = SoundCheck.spots(in: try track(scenes, cues: [75]), before: 200, count: 6)
        XCTAssertTrue(six.contains { $0.kind == .oneOff }, "the one-off keeps its own place")
        XCTAssertEqual(six.count, 6)
        XCTAssertFalse(SoundCheck.spots(in: try track(scenes, cues: [75]), before: 200, count: 6, oneOffs: false).contains { $0.kind == .oneOff })
    }

    func testTheKindComesFromTheMainSoundOnly() throws {
        // Wind is the main sound; the faint waves do not make it a water spot.
        let windy = [scene("p1", .outdoors, [SceneLayer(.wind, .soft), SceneLayer(.seaShore, .faint)])]
        let spots = SoundCheck.spots(in: try track(windy), before: 200, count: 3)
        XCTAssertEqual(spots.map(\.kind), [.weather])
    }

    func testAQuietRoomIsAQuietSound() throws {
        let kitchen = [scene("p1", .indoors, [SceneLayer(.kitchen, .soft)])]
        XCTAssertFalse(SoundCheck.spots(in: try track(kitchen), before: 200, count: 3).contains { $0.kind == .quietRoom })
    }

    func testSkipsScenesThatNeverPlayOrDoNotLast() throws {
        var unsure = scenes
        unsure[2] = scene("p2", .indoors, [SceneLayer(.crowd, .loud)], confidence: 0.2)     // below the director's 0.35
        unsure[4] = scene("p4", .outdoors, [SceneLayer(.river, .full)], transition: .enterThroughDoor)
        let spots = SoundCheck.spots(in: try track(unsure, chapterStarts: [0, 55]), before: 200, count: 9)
        XCTAssertFalse(spots.contains { $0.globalIndex == 20 }, "low confidence never plays")
        for spot in spots where spot.kind != .oneOff {
            XCTAssertFalse(spot.globalIndex < 55 && spot.lastIndex >= 55, "no chapter start inside a stop")
        }
        // The rain (50 to 59) is cut in two by the chapter start at 55: both too short, so
        // the weather falls back to its longest piece, the earlier on a tie.
        let weather = try XCTUnwrap(spots.first { $0.kind == .weather })
        XCTAssertEqual(weather.globalIndex, 50)
        XCTAssertEqual(weather.lastIndex, 54)
    }

    func testRunsOfTheSameMainSoundMakeOneLongerStop() throws {
        let steady = [
            scene("p1", .indoors, [SceneLayer(.fireplace, .full)]),
            scene("p1", .indoors, [SceneLayer(.fireplace, .full), SceneLayer(.clock, .faint)]),
            scene("p2", .outdoors, [SceneLayer(.rain, .full)]),
        ]
        let spots = SoundCheck.spots(in: try track(steady), before: 200, count: 4)
        let fire = try XCTUnwrap(spots.first { $0.sounds.first?.key == "fireplace" })
        XCTAssertEqual(fire.globalIndex, 0)
        XCTAssertEqual(fire.lastIndex, 19)
    }

    func testNeverReachesPastWhatWasHeard() throws {
        // Spoiler safety: the whole stop, not just its start, lies before the limit.
        let spots = SoundCheck.spots(in: try track(scenes, cues: [75]), before: 45, count: 7)
        XCTAssertFalse(spots.isEmpty)
        XCTAssertTrue(spots.allSatisfy { $0.lastIndex < 45 })
        XCTAssertFalse(spots.contains { $0.kind == .oneOff }, "the knock at 75 is past the limit")
        XCTAssertEqual(spots.first { $0.kind == .water }?.lastIndex, 44, "the river is cut short at the limit")
    }

    func testPrefersLevelsNotCoveredAndTheEarliestSpot() throws {
        let rooms = [
            scene("p1", .indoors, [SceneLayer(.roomTone, .soft)]),
            scene("p2", .outdoors, [SceneLayer(.forest, .soft)]),
            scene("p3", .indoors, [SceneLayer(.clock, .faint)]),
            scene("p4", .outdoors, [SceneLayer(.forest, .full)]),
        ]
        let spots = SoundCheck.spots(in: try track(rooms), before: 200, count: 2)
        XCTAssertEqual(spots.map(\.globalIndex), [0, 30], "the outdoors pick is full, a level the room did not cover")
        // The same stops come back on the next run.
        XCTAssertEqual(SoundCheck.spots(in: try track(rooms), before: 200, count: 2), spots)
    }

    func testAnEmptyOrSilentTrackHasNoSpots() throws {
        XCTAssertEqual(SoundCheck.spots(in: try track([.silent, .silent]), before: 200), [])
        XCTAssertEqual(SoundCheck.spots(in: try track(scenes), before: 200, count: 0), [])
    }
}
