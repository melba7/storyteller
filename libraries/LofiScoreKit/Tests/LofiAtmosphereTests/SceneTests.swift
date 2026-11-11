import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

final class SceneTests: XCTestCase {
    func testLayersAreNormalised() {
        let scene = StoryScene(placeID: "p1", layers: [SceneLayer(.rain, .faint), SceneLayer(.rain, .full), SceneLayer(.fireplace)])
        XCTAssertEqual(scene.layers, [SceneLayer(.rain, .full), SceneLayer(.fireplace, .soft)])
        let crowded = StoryScene(placeID: nil, layers: AmbientSound.allCases.map { SceneLayer($0) })
        XCTAssertEqual(crowded.layers.count, StoryScene.maxLayers)
    }

    func testOnlyACrowdMakesTheMusicStepAside() {
        XCTAssertTrue(StoryScene(placeID: "p1", layers: [SceneLayer(.crowd, .soft)]).replacesMusic)
        XCTAssertFalse(StoryScene(placeID: "p1", layers: [SceneLayer(.crowd, .faint)]).replacesMusic)
        XCTAssertFalse(StoryScene(placeID: "p1", layers: [SceneLayer(.heavyRain, .full)]).replacesMusic)
    }

    func testLenientSoundNames() {
        XCTAssertEqual(AmbientSound(lenient: "HeavyRain"), .heavyRain)
        XCTAssertEqual(AmbientSound(lenient: "heavy rain"), .heavyRain)
        XCTAssertEqual(AmbientSound(lenient: "night_insects"), .nightInsects)
        XCTAssertNil(AmbientSound(lenient: "bagpipes"))
    }

    func testTrackNeverAnswersWithALaterEntry() throws {
        let guardian = try SpoilerGuard(chapters: [["a.", "b.", "c.", "d."], ["e.", "f."]])
        var track = AtmosphereTrack(engineID: "t", bookID: "b", wordsBetweenEntries: 10, chapterStarts: [0, 4])
        for index in [1, 3, 5] {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: index >= 4 ? 1 : 0, sentenceIndex: index >= 4 ? index - 4 : index))
            track.insert(.init(position: position, sentence: "x", scene: StoryScene(placeID: "p\(index)", layers: [SceneLayer(.rain)])))
        }
        XCTAssertNil(track.entry(atOrBefore: 0))
        XCTAssertEqual(track.entry(atOrBefore: 1)?.globalIndex, 1)
        XCTAssertEqual(track.entry(atOrBefore: 2)?.globalIndex, 1)
        XCTAssertEqual(track.entry(atOrBefore: 4)?.globalIndex, 3)
        XCTAssertEqual(track.chapterStart(atOrBefore: 3), 0)
        XCTAssertEqual(track.chapterStart(atOrBefore: 4), 4)
        XCTAssertEqual(track.entries(before: 3).map(\.globalIndex), [1])

        let data = try track.encoded()
        XCTAssertEqual(try AtmosphereTrack.decode(data), track)
    }

    func testPlaceMemoryRemembersTheLastSoundsOfEachPlace() throws {
        let guardian = try SpoilerGuard(chapters: [(0..<10).map { "Sentence \($0)." }])
        var track = AtmosphereTrack(engineID: "t", bookID: "b", wordsBetweenEntries: 10)
        func add(_ index: Int, _ id: String, _ name: String, _ layers: [SceneLayer], world: String? = nil) throws {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
            track.insert(.init(position: position, sentence: "x", scene: StoryScene(placeID: id, placeName: name, setting: .indoors, layers: layers), world: world))
        }
        try add(1, "p1", "the tavern", [SceneLayer(.fireplace, .full)], world: "a fishing town")
        try add(3, "p2", "the harbour", [SceneLayer(.seaShore)])
        try add(5, "p1", "the tavern", [SceneLayer(.fireplace, .faint), SceneLayer(.rainIndoors)])
        try add(7, "p2", "the harbour", [SceneLayer(.seaShore), SceneLayer(.heavyRain)])

        let atSix = PlaceMemory(track: track, before: 6)
        XCTAssertEqual(atSix.places["p1"]?.layers, [SceneLayer(.rainIndoors), SceneLayer(.fireplace, .faint)])
        XCTAssertEqual(atSix.places["p1"]?.visits, 2)
        XCTAssertEqual(atSix.places["p2"]?.layers, [SceneLayer(.seaShore)], "the harbour's storm comes later and is not known yet")
        XCTAssertEqual(atSix.current?.placeID, "p1")
        XCTAssertEqual(atSix.world, "a fishing town")
        XCTAssertEqual(atSix.newPlaceID(), "p3")
        XCTAssertEqual(atSix.place(named: "The Tavern")?.id, "p1")
        XCTAssertEqual(atSix.recent(limit: 1).first?.id, "p1")

        XCTAssertTrue(PlaceMemory.namesMatch("the garden", "the walled garden"))
        XCTAssertFalse(PlaceMemory.namesMatch("the garden", "the kitchen"))
    }
}
