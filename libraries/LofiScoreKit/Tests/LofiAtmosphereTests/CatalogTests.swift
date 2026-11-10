import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiText

/// The built-in sound catalogue: every family's kinds, the place guide, the JSON the fetch
/// script reads, and the prompt the scorer gets.
final class CatalogTests: XCTestCase {
    func testKindsAreUniqueWellFormedAndNeverNamedLikeAFamily() {
        var seen = Set<String>()
        for variant in SoundCatalog.variants {
            XCTAssertTrue(seen.insert(variant.id).inserted, "\(variant.id) twice")
            XCTAssertEqual(SoundVariant.normalizedID(variant.id), variant.id, "\(variant.id) is not a plain camelCase id")
            XCTAssertFalse(variant.about.isEmpty, "\(variant.id) has no description")
            XCTAssertFalse(variant.searches.isEmpty, "\(variant.id) has nothing to search for")
            let sound = variant.variant
            XCTAssertEqual(sound.of, variant.of)
            XCTAssertNil(sound.firstIndex, "a catalogue kind is available from the first sentence")
            XCTAssertEqual(variant.folderName, "\(variant.of.folderName).\(variant.id.prefix(1).uppercased())\(variant.id.dropFirst())")
        }
        XCTAssertGreaterThanOrEqual(SoundCatalog.variants.count, 350)
        for sound in AmbientSound.allCases {
            XCTAssertFalse(SoundCatalog.variants(of: sound).isEmpty, "\(sound.rawValue) has no more specific kinds")
            XCTAssertNil(SoundCatalog.variant(sound.rawValue), "\(sound.rawValue) is a family, not a kind")
        }
        XCTAssertEqual(SoundCatalog.starterVariants.count, SoundCatalog.variants.count)
        XCTAssertEqual(SoundCatalog.variant("schoolCorridor")?.of, .crowd)
        XCTAssertEqual(SoundCatalog.variant("hallwayWhispers")?.of, .murmur)
        XCTAssertEqual(SoundCatalog.variant("office")?.of, .electricHum, "moved from machinery")
    }

    func testThePlaceGuideOnlyNamesSoundsThatExist() throws {
        XCTAssertGreaterThanOrEqual(SoundCatalog.placeGuide.count, 30)
        var places = Set<String>()
        for guide in SoundCatalog.placeGuide {
            XCTAssertTrue(places.insert(guide.place).inserted, "\(guide.place) twice")
            XCTAssertGreaterThanOrEqual(guide.states.count, 2, "\(guide.place) has only one state")
            for state in guide.states {
                XCTAssertFalse(state.when.isEmpty)
                for item in state.sounds.split(separator: ",") {
                    let parts = item.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    XCTAssertEqual(parts.count, 2, "\(guide.place), \(state.when): \"\(item)\" is not \"sound level\"")
                    let name = String(parts[0])
                    let level = parts.count > 1 ? String(parts[1]) : ""
                    XCTAssertNotNil(AmbientLevel(rawValue: level), "\(guide.place): level \(level)")
                    if let dot = name.firstIndex(of: ".") {
                        let family = String(name[..<dot])
                        let kind = String(name[name.index(after: dot)...])
                        XCTAssertNotNil(AmbientSound(rawValue: family), "\(guide.place): family \(family)")
                        XCTAssertEqual(SoundCatalog.variant(kind)?.of.rawValue, family, "\(guide.place): \(name)")
                    } else {
                        XCTAssertNotNil(AmbientSound(rawValue: name), "\(guide.place): sound \(name)")
                    }
                }
            }
        }
        let corridor = try XCTUnwrap(SoundCatalog.placeGuide.first { $0.place == "school corridor" })
        XCTAssertTrue(corridor.states.contains { $0.sounds.contains("crowd.schoolCorridor loud") }, "an uproar")
        XCTAssertTrue(corridor.states.contains { $0.sounds.contains("murmur.hallwayWhispers") }, "everyone whispering")
        XCTAssertTrue(corridor.states.contains { $0.sounds.contains("emptyHall.schoolHallwayEmpty") }, "after hours")
    }

    func testTheExportIsTheCommittedCatalogueTheFetchScriptReads() throws {
        let data = try SoundCatalog.export()
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(exported["version"] as? Int, SoundCatalog.version)
        XCTAssertEqual(exported["promptVersion"] as? Int, ClaudeScenePrompt.version)
        let sounds = try XCTUnwrap(exported["sounds"] as? [[String: Any]])
        XCTAssertEqual(sounds.count, AmbientSound.allCases.count)
        for sound in sounds {
            XCTAssertFalse(try XCTUnwrap(sound["queries"] as? [String]).isEmpty, "\(sound["id"] ?? "?") has nothing to search for")
            XCTAssertNotNil(sound["folder"] as? String)
            XCTAssertNotNil(sound["levelOffsetDB"] as? Double)
        }
        XCTAssertEqual((exported["variants"] as? [[String: Any]])?.count, SoundCatalog.variants.count)
        XCTAssertEqual((exported["oneShots"] as? [[String: Any]])?.count, OneShotSound.allCases.count)
        XCTAssertEqual((exported["places"] as? [[String: Any]])?.count, SoundCatalog.placeGuide.count)
        XCTAssertEqual((exported["transitions"] as? [[String: Any]])?.count, SceneTransition.allCases.count)
        XCTAssertTrue(sounds.contains { $0["id"] as? String == "crowd" && $0["voices"] as? Bool == true && $0["replacesMusic"] as? Bool == true })

        // Tools/atmosphere/catalog.json is what the fetch script reads on the Mac; it is
        // written by `lofi-atmosphere catalog --out Tools/atmosphere/catalog.json`.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools/atmosphere/catalog.json")
        let committed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? NSDictionary)
        XCTAssertEqual(committed, exported as NSDictionary, "Tools/atmosphere/catalog.json is out of date: run swift run lofi-atmosphere catalog --out Tools/atmosphere/catalog.json")
    }

    func testThePromptCarriesEveryFamilyItsKindsAndThePlaceGuide() {
        let system = ClaudeScenePrompt.system
        XCTAssertEqual(ClaudeScenePrompt.version, 5)
        for sound in AmbientSound.allCases {
            XCTAssertTrue(system.contains("\n- \(sound.rawValue): "), "\(sound.rawValue) is not in the prompt")
        }
        for group in AmbientSound.Group.allCases {
            XCTAssertTrue(system.contains("\(group.title):"), "group \(group.title)")
        }
        XCTAssertTrue(system.contains("crowd.schoolCorridor:"))
        XCTAssertTrue(system.contains("murmur.hallwayWhispers:"))
        for guide in SoundCatalog.placeGuide {
            XCTAssertTrue(system.contains("- \(guide.place): "), "\(guide.place) is not in the prompt")
        }
        XCTAssertTrue(system.contains("roomTone (nobody else heard), hushedRoom"), "the people ladder")
        XCTAssertTrue(system.contains("loud"))
        XCTAssertLessThan(system.count, 60_000, "the system prompt is cached, but it still has to fit a request")

        let levels = (ClaudeScenePrompt.schema["properties"] as? [String: Any])
            .flatMap { $0["sounds"] as? [String: Any] }
            .flatMap { $0["items"] as? [String: Any] }
            .flatMap { $0["properties"] as? [String: Any] }
            .flatMap { $0["level"] as? [String: Any] }
            .flatMap { $0["enum"] as? [String] }
        XCTAssertEqual(levels, AmbientLevel.allCases.map(\.rawValue))
    }

    func testLoudIsALevelAndAnUnknownLevelReadsAsSoft() throws {
        XCTAssertEqual(AmbientLevel.loud.offsetDB, 4)
        XCTAssertGreaterThan(AmbientLevel.loud, .full)
        XCTAssertEqual(AmbientLevel.loud.quieter, .full)
        XCTAssertEqual(AmbientLevel.faint.quieter, .faint)
        XCTAssertEqual(AmbientLevel(lenient: " Loud "), .loud)
        XCTAssertNil(AmbientLevel(lenient: "deafening"))

        let scene = StoryScene(placeID: "p1", placeName: "the corridor", setting: .indoors,
                               layers: [SceneLayer(.crowd, .loud, variant: "schoolCorridor")], confidence: 0.9, state: "uproar after the fight")
        let data = try JSONEncoder().encode(scene)
        let back = try JSONDecoder().decode(StoryScene.self, from: data)
        XCTAssertEqual(back, scene)
        XCTAssertEqual(back.state, "uproar after the fight")
        XCTAssertTrue(scene.description.contains("uproar after the fight"))

        let older = try JSONDecoder().decode(StoryScene.self, from: Data("""
            {"placeID":"p1","placeName":"x","setting":"indoors","layers":[{"sound":"rain","level":"deafening"}],"confidence":0.5}
            """.utf8))
        XCTAssertEqual(older.layers, [SceneLayer(.rain, .soft)], "a level this build does not know plays soft")
        XCTAssertNil(older.state)
    }

    func testAMovedKindStillFindsItsOldRecording() {
        let library = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
            AmbienceRecording(id: "machinery.office/a", file: "Machinery.Office/office-a.wav", sound: .machinery, variant: "office", loudness: -23),
            AmbienceRecording(id: "electricHum/a", file: "ElectricHum/hum-a.wav", sound: .electricHum, loudness: -23),
        ])
        XCTAssertEqual(library.recording(for: SceneLayer(.electricHum, .soft, variant: "office"), key: "k")?.id, "machinery.office/a",
                       "the kind's recording, wherever an older catalogue filed it")
        XCTAssertEqual(library.recording(for: SceneLayer(.electricHum, .soft), key: "k")?.id, "electricHum/a")
        XCTAssertEqual(library.recording(for: SceneLayer(.electricHum, .soft, variant: "serverRoom"), key: "k")?.id, "electricHum/a",
                       "a kind with no recording plays its family")
    }

    func testTheBuilderOffersTheWholeCatalogueAndOtherBooksKinds() throws {
        let guardian = try SpoilerGuard(chapters: [["One.", "Two."]])
        let other = SoundVariant(id: "zeppelinHangar", of: .machinery, about: "a zeppelin hangar", search: "hangar ambience")
        let duplicate = SoundVariant(id: "cafe", of: .crowd, about: "another cafe", search: "cafe")
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, offeredVariants: [duplicate, other])
        XCTAssertEqual(builder.offeredVariants.count, SoundCatalog.variants.count + 1)
        XCTAssertEqual(builder.offeredVariants.last, other)
        XCTAssertEqual(builder.offeredVariants.first { $0.id == "cafe" }?.about, SoundCatalog.variant("cafe")?.about, "the catalogue's wording wins")
        XCTAssertEqual(AtmosphereTrackBuilder(spoilerGuard: guardian).offeredVariants.count, SoundCatalog.variants.count)
    }

    func testEveryNewSoundHasGuidanceAGroupAndStandInSearches() {
        for sound in AmbientSound.allCases {
            XCTAssertFalse(sound.guidance.isEmpty, sound.rawValue)
            XCTAssertFalse(sound.searchQueries.isEmpty, sound.rawValue)
            XCTAssertTrue(sound.levelOffsetDB <= 1 && sound.levelOffsetDB >= -8, "\(sound.rawValue): \(sound.levelOffsetDB)")
        }
        XCTAssertEqual(Set(AmbientSound.allCases.filter(\.isVoices)), [.crowd, .murmur])
        XCTAssertEqual(AmbientSound.murmur.group, .people)
        XCTAssertEqual(AmbientSound.spaceship.group, .travel)
        XCTAssertEqual(AmbientSound.deepDrone.group, .elsewhere)
        XCTAssertEqual(AmbientSound.allCases.count, 48)
        XCTAssertTrue(AmbientSound.allCases.firstIndex(of: .roomTone)! > AmbientSound.allCases.firstIndex(of: .clock)!,
                      "new families go after the old ones, so older tracks and recordings keep their order")
        XCTAssertEqual(OneShotSound.schoolBell.search.longestSeconds > 0, true)
    }
}
