import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// A track built straight from global indices, for tests that do not need real sentences.
func testTrack(
    _ entries: [(index: Int, place: String?, layers: [SceneLayer], confidence: Double)],
    chapterStarts: [Int] = [0],
    sentences: Int = 200
) throws -> AtmosphereTrack {
    let guardian = try SpoilerGuard(chapters: [(0..<sentences).map { "Sentence \($0)." }])
    var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10, chapterStarts: chapterStarts)
    for item in entries {
        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: item.index))
        let scene = StoryScene(placeID: item.place, placeName: item.place, setting: .indoors, layers: item.layers, confidence: item.confidence)
        track.insert(.init(position: position, sentence: "Sentence \(item.index).", scene: scene))
    }
    return track
}

final class DirectorTests: XCTestCase {
    private func director() throws -> AtmosphereDirector {
        var director = AtmosphereDirector()
        director.setTrack(try testTrack([
            (0, "p1", [SceneLayer(.fireplace, .full)], 0.9),
            (10, "p2", [SceneLayer(.oldTown)], 0.9),
            (20, "p3", [SceneLayer(.seaShore)], 0.2),
            (30, "p1", [SceneLayer(.fireplace, .faint)], 0.9),
            (60, "p4", [SceneLayer(.forest)], 0.9),
        ], chapterStarts: [0, 50]))
        return director
    }

    func testTheSceneComesOnlyFromEntriesAtOrBeforeThePlayhead() throws {
        let director = try director()
        XCTAssertEqual(director.target(at: 0).scene.placeID, "p1")
        XCTAssertEqual(director.target(at: 9).scene.placeID, "p1", "the street starts at 10, not before")
        XCTAssertEqual(director.target(at: 10).scene.placeID, "p2")
        XCTAssertEqual(director.target(at: 25).scene.placeID, "p2", "an unsure entry never replaces the scene")
        XCTAssertEqual(director.target(at: 59).scene.placeID, "p1")
        XCTAssertTrue(director.target(at: 59).dipped, "chapter two has not said where it is yet")
        XCTAssertFalse(director.target(at: 60).dipped)
        XCTAssertFalse(director.target(at: 45).dipped)
    }

    func testAnOldSceneFadesOutWhenTheTrackRunsOut() throws {
        var director = AtmosphereDirector()
        director.setTrack(try testTrack([(0, "p1", [SceneLayer(.rain)], 0.9)]))
        XCTAssertEqual(director.target(at: 80).scene.placeID, "p1")
        XCTAssertTrue(director.target(at: 81).scene.isSilent)
        XCTAssertTrue(AtmosphereDirector().target(at: 5).scene.isSilent, "no track, no sound")
    }

    func testChangesWaitForTheDwellUnlessTheListenerSeeks() throws {
        var director = try director()
        guard case let .change(first, fade) = director.step(at: 0, now: 0) else { return XCTFail("expected a change") }
        XCTAssertEqual(first.scene.placeID, "p1")
        XCTAssertEqual(fade, director.config.sceneFade)
        XCTAssertEqual(director.step(at: 5, now: 4), .hold)
        XCTAssertEqual(director.step(at: 10, now: 5), .wait(until: 20))
        guard case let .change(street, quick) = director.step(at: 10, now: 5, seek: true) else { return XCTFail("a seek changes at once") }
        XCTAssertEqual(street.scene.placeID, "p2")
        XCTAssertEqual(quick, director.config.quickFade)
        XCTAssertEqual(director.step(at: 30, now: 10), .wait(until: 25))
        guard case let .change(back, _) = director.step(at: 30, now: 25) else { return XCTFail("expected a change") }
        XCTAssertEqual(back.scene.level(of: .fireplace), .faint)
    }

    func testAChapterStartDipsTheLastScene() throws {
        var director = try director()
        _ = director.step(at: 30, now: 0)
        XCTAssertEqual(director.step(at: 52, now: 1), .dip(true))
        XCTAssertEqual(director.step(at: 53, now: 2), .hold)
        guard case .change = director.step(at: 60, now: 30) else { return XCTFail("the new chapter's scene arrives") }
        XCTAssertFalse(director.applied.dipped)
    }

    func testTheSameSoundsAtANewLevelUseTheShorterFade() throws {
        var director = AtmosphereDirector()
        director.setTrack(try testTrack([
            (0, "p1", [SceneLayer(.rain, .soft)], 0.9),
            (10, "p1", [SceneLayer(.rain, .full)], 0.9),
        ]))
        _ = director.step(at: 0, now: 0)
        guard case let .change(_, fade) = director.step(at: 10, now: 30) else { return XCTFail("expected a change") }
        XCTAssertEqual(fade, director.config.levelFade)
    }
}
