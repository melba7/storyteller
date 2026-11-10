import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiAudioCore
import LofiText

/// Scene transitions (a door opened on a party and shut behind them, a car boarded) and
/// the sounds of what the characters are doing (footsteps, a meal).
final class TransitionTests: XCTestCase {
    static func scene(_ id: String, _ setting: StoryScene.Setting, _ layers: [SceneLayer], transition: SceneTransition? = nil) -> StoryScene {
        StoryScene(placeID: id, placeName: id, setting: setting, layers: layers, confidence: 0.9, transition: transition)
    }

    static let party = scene("p1", .indoors, [SceneLayer(.crowd, .full), SceneLayer(.rain, .faint)])
    static let street = scene("p2", .outdoors, [SceneLayer(.oldTown, .full), SceneLayer(.rain, .faint)])
    static let quietRoom = scene("p3", .indoors, [SceneLayer(.roomTone, .soft)])
    static let car = scene("p4", .vehicle, [SceneLayer(.motorVehicle, .full)])
    static let train = scene("p5", .vehicle, [SceneLayer(.train, .full)])
    static let market = scene("p6", .outdoors, [SceneLayer(.crowd, .full, variant: "marketDay")])

    // MARK: - The transitions

    func testEveryTransitionHasGuidanceATimelineAndSoundsThatFitTheScenes() {
        for transition in SceneTransition.allCases {
            XCTAssertFalse(transition.guidance.isEmpty, transition.rawValue)
            XCTAssertGreaterThanOrEqual(transition.timeline.seconds, 0, transition.rawValue)
            XCTAssertLessThanOrEqual(transition.timeline.seconds, 30, "\(transition.rawValue) runs too long")
            for timed in transition.sounds(from: Self.party, to: Self.street) {
                XCTAssertGreaterThanOrEqual(timed.at, 0, transition.rawValue)
            }
        }
        XCTAssertEqual(SceneTransition(lenient: "Leave Through Door"), .leaveThroughDoor)
        XCTAssertEqual(SceneTransition(lenient: "board_vehicle"), .boardVehicle)
        XCTAssertNil(SceneTransition(lenient: "teleport"))

        XCTAssertEqual(SceneTransition.leaveThroughDoor.sounds(from: nil, to: .silent).map(\.sound), [.doorOpen, .doorClose])
        XCTAssertEqual(SceneTransition.boardVehicle.sounds(from: Self.street, to: Self.car).map(\.sound), [.carDoor, .engineStart])
        XCTAssertEqual(SceneTransition.boardVehicle.sounds(from: Self.street, to: Self.train).map(\.sound), [.doorClose, .trainWhistle])
        XCTAssertEqual(SceneTransition.leaveVehicle.sounds(from: Self.car, to: Self.street).map(\.sound), [.engineStop, .carDoor])
        XCTAssertEqual(SceneTransition.vehicleDeparts.sounds(from: Self.train, to: Self.street).map(\.sound), [.trainWhistle, .trainPullsAway])
        XCTAssertEqual(SceneTransition.vehicleDeparts.sounds(from: Self.street, to: Self.street).map(\.sound), [.hoovesAway], "the era says what left")
        XCTAssertEqual(SceneTransition.diveUnder.sounds(from: Self.street, to: .silent).map(\.sound), [.splash])
        XCTAssertEqual(SceneTransition.walkAway.sounds(from: Self.market, to: Self.street), [])
    }

    func testAPlainTransitionIsInferredFromTheTwoScenes() {
        XCTAssertEqual(SceneTransition.inferred(from: Self.party, to: Self.street), .leaveThroughDoor)
        XCTAssertEqual(SceneTransition.inferred(from: Self.quietRoom, to: Self.street), .stepOutside)
        XCTAssertEqual(SceneTransition.inferred(from: Self.street, to: Self.party), .enterThroughDoor)
        XCTAssertEqual(SceneTransition.inferred(from: Self.street, to: Self.quietRoom), .stepInside)
        XCTAssertEqual(SceneTransition.inferred(from: Self.street, to: Self.car), .boardVehicle)
        XCTAssertEqual(SceneTransition.inferred(from: Self.car, to: Self.street), .leaveVehicle)
        XCTAssertEqual(SceneTransition.inferred(from: Self.market, to: Self.street), .walkAway)
        XCTAssertEqual(SceneTransition.inferred(from: Self.street, to: Self.market), .approach)
        XCTAssertEqual(SceneTransition.inferred(from: Self.party, to: Self.quietRoom), .leaveThroughDoor)
        XCTAssertNil(SceneTransition.inferred(from: Self.quietRoom, to: Self.scene("p9", .indoors, [SceneLayer(.clock)])), "two quiet rooms crossfade")
        XCTAssertNil(SceneTransition.inferred(from: Self.car, to: Self.train))
        XCTAssertNil(SceneTransition.inferred(from: Self.party, to: Self.party), "the same place")
        XCTAssertNil(SceneTransition.inferred(from: .silent, to: Self.street))
        XCTAssertNil(SceneTransition.inferred(from: Self.street, to: .silent))
        XCTAssertNil(SceneTransition.inferred(from: Self.scene("p7", .unclear, [SceneLayer(.wind)]), to: Self.street))
    }

    func testScenesCarryTheirTransitionAndOlderTracksStillRead() throws {
        let scene = Self.scene("p2", .outdoors, [SceneLayer(.oldTown)], transition: .leaveThroughDoor)
        let data = try JSONEncoder().encode(scene)
        XCTAssertEqual(try JSONDecoder().decode(StoryScene.self, from: data), scene)
        XCTAssertTrue(scene.description.contains(">leaveThroughDoor"))
        var plain = scene
        plain.transition = nil
        XCTAssertTrue(scene.soundsLike(plain), "a transition is not a change of sound")

        let older = try JSONDecoder().decode(StoryScene.self, from: Data("""
            {"placeID":"p1","placeName":"x","setting":"indoors","layers":[],"confidence":0.5,"transition":"teleport"}
            """.utf8))
        XCTAssertNil(older.transition, "a transition this build does not know plays as a plain change")
        XCTAssertNil(try JSONDecoder().decode(StoryScene.self, from: Data(#"{"placeID":"p1","setting":"indoors","layers":[],"confidence":0.5}"#.utf8)).transition)
    }

    func testAnswersMayNameATransition() throws {
        let memory = PlaceMemory(entries: [])
        func answer(_ transition: String, place: String = "new") throws -> SceneAnswer {
            try ClaudeSceneEngine.answer(fromJSON: """
                {"place":"\(place)","placeName":"the street","setting":"outdoors",
                 "sounds":[{"sound":"oldTown","level":"soft","variant":""}],"newSounds":[],"moment":"none",
                 "transition":"\(transition)","oneShot":{"sound":"none","quote":""},"world":"","cue":"","confidence":0.8}
                """, memory: memory)
        }
        XCTAssertEqual(try answer("leaveThroughDoor").scene.transition, .leaveThroughDoor)
        XCTAssertEqual(try answer("Leave through door").scene.transition, .leaveThroughDoor)
        XCTAssertNil(try answer("none").scene.transition)
        XCTAssertNil(try answer("teleport").scene.transition)
        XCTAssertNil(try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"new","placeName":"the street","setting":"outdoors","sounds":[],"newSounds":[],"moment":"none",
             "oneShot":{"sound":"none","quote":""},"world":"","cue":"","confidence":0.8}
            """, memory: memory).scene.transition, "answers in the older shape still read")

        let system = ClaudeScenePrompt.system
        XCTAssertEqual(ClaudeScenePrompt.version, 6)
        for transition in SceneTransition.allCases {
            XCTAssertTrue(system.contains("- \(transition.rawValue): "), "\(transition.rawValue) is not in the prompt")
        }
        XCTAssertTrue(system.contains("Transitions:"))
        XCTAssertTrue(system.contains("\(AmbientSound.Group.doing.title):"))
        XCTAssertTrue(system.contains("footsteps.walkingGravel:"))
        let properties = try XCTUnwrap(ClaudeScenePrompt.schema["properties"] as? [String: Any])
        let field = try XCTUnwrap(properties["transition"] as? [String: Any])
        XCTAssertEqual((field["enum"] as? [String])?.first, "none")
        XCTAssertEqual((field["enum"] as? [String])?.count, SceneTransition.allCases.count + 1)
        XCTAssertTrue((ClaudeScenePrompt.schema["required"] as? [String])?.contains("transition") == true)
    }

    func testTheCatalogueExportsTheTransitionsAndEachSoundsScope() throws {
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: try SoundCatalog.export()) as? [String: Any])
        let transitions = try XCTUnwrap(exported["transitions"] as? [[String: Any]])
        XCTAssertEqual(transitions.count, SceneTransition.allCases.count)
        XCTAssertTrue(transitions.contains { $0["id"] as? String == "leaveThroughDoor" && ($0["seconds"] as? Double ?? 0) > 10 })
        let sounds = try XCTUnwrap(exported["sounds"] as? [[String: Any]])
        XCTAssertTrue(sounds.contains { $0["id"] as? String == "footsteps" && $0["scope"] as? String == "activity" })
        XCTAssertTrue(sounds.contains { $0["id"] as? String == "rain" && $0["scope"] as? String == "weather" })
        let oneShots = try XCTUnwrap(exported["oneShots"] as? [[String: Any]])
        XCTAssertTrue(oneShots.contains { $0["id"] as? String == "doorOpen" })
    }

    // MARK: - Activities

    func testActivitiesFollowTheCharactersNotThePlace() throws {
        for sound in [AmbientSound.footsteps, .running, .breathing, .heartbeat, .swimming, .climbing, .fighting, .writing, .meal, .work] {
            XCTAssertEqual(sound.scope, .activity, sound.rawValue)
            XCTAssertEqual(sound.group, .doing, sound.rawValue)
            XCTAssertFalse(SoundCatalog.variants(of: sound).isEmpty, "\(sound.rawValue) has no kinds")
        }
        XCTAssertEqual(SoundCatalog.variant("walkingGravel")?.of, .footsteps)
        XCTAssertEqual(SoundCatalog.variant("chase")?.of, .running)
        XCTAssertEqual(SoundCatalog.variant("trot")?.of, .horses)

        let guardian = try SpoilerGuard(chapters: [["One.", "Two.", "Three."]])
        var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10, chapterStarts: [0])
        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 0))
        track.insert(.init(position: position, sentence: "One.", scene: StoryScene(
            placeID: "p1", placeName: "the lane", setting: .outdoors,
            layers: [SceneLayer(.birdsong, .soft), SceneLayer(.footsteps, .faint, variant: "walkingGravel")], confidence: 0.9
        )))
        let memory = PlaceMemory(track: track, before: 1)
        XCTAssertEqual(memory.places["p1"]?.layers, [SceneLayer(.birdsong, .soft)], "the lane is remembered without the walking")
        XCTAssertEqual(memory.current?.sounds.contains(.footsteps), true, "the current scene still has it, so the scorer can drop it")
    }

    // MARK: - Playback

    final class Harness {
        let scheduler = ManualScheduler()
        let backend = FakeAmbienceBackend()
        let player: AmbiencePlayer
        var events: [AmbienceEvent] = []

        static let library = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
            AmbienceRecording(id: "crowd/a", file: "Crowd/party.wav", sound: .crowd, loudness: -23),
            AmbienceRecording(id: "oldTown/a", file: "OldTown/street.wav", sound: .oldTown, loudness: -23),
            AmbienceRecording(id: "rain/a", file: "Rain/rain.wav", sound: .rain, loudness: -23),
            AmbienceRecording(id: "roomTone/a", file: "RoomTone/room.wav", sound: .roomTone, loudness: -23),
            AmbienceRecording(id: "motorVehicle/a", file: "MotorVehicle/car.wav", sound: .motorVehicle, loudness: -23),
            AmbienceRecording(id: "footsteps/a", file: "Footsteps/steps.wav", sound: .footsteps, loudness: -23),
        ])
        static let oneShots = OneShotLibrary(folder: URL(fileURLWithPath: "/sounds/OneShots"), recordings: [
            OneShotRecording(id: "doorOpen/a", file: "DoorOpen/open.wav", sound: .doorOpen, loudness: -20),
            OneShotRecording(id: "doorClose/a", file: "DoorClose/close.wav", sound: .doorClose, loudness: -20),
            OneShotRecording(id: "carDoor/a", file: "CarDoor/cardoor.wav", sound: .carDoor, loudness: -20),
            OneShotRecording(id: "engineStart/a", file: "EngineStart/start.wav", sound: .engineStart, loudness: -20),
        ])

        init(_ entries: [(index: Int, scene: StoryScene)], oneShotsOn: Bool = true, config: AtmosphereConfig = PlayerTests.Harness.steadyConfig) throws {
            let guardian = try SpoilerGuard(chapters: [(0..<200).map { "Sentence \($0)." }])
            var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10, chapterStarts: [0])
            for entry in entries {
                let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: entry.index))
                track.insert(.init(position: position, sentence: "Sentence \(entry.index).", scene: entry.scene))
            }
            player = AmbiencePlayer(library: Self.library, oneShots: Self.oneShots, backend: backend, scheduler: scheduler, config: config, seed: 5)
            player.onEvent = { [unowned self] in events.append($0) }
            player.setOneShotsEnabled(oneShotsOn)
            player.openBook(id: "book")
            player.setTrack(track, forBook: "book")
            player.narratorDidPlay()
        }

        /// Narrates sentence `index` and lets `seconds` pass.
        func narrate(_ index: Int, then seconds: TimeInterval) {
            player.sentenceDidStart(globalSentenceIndex: index, duration: 4)
            scheduler.advance(by: seconds)
        }

        /// Settles into the first scene, then reads up to the sentence before `index`.
        func settle(upTo index: Int) {
            narrate(0, then: 30)
            for sentence in 1..<index { narrate(sentence, then: 4) }
        }

        func gain(_ file: String) -> Float { backend.audible[file] ?? 0 }
        func muffle(_ file: String) -> Float { backend.muffles[file] ?? 0 }
        var played: [String] { backend.oneShots.map(\.file) }

        var snapshot: AmbienceSnapshot {
            var result: AmbienceSnapshot!
            player.snapshot { result = $0 }
            return result
        }
    }

    func testLeavingAPartyTheDoorOpensTheNoiseFollowsThemOutAndTheDoorShutsOnIt() throws {
        let h = try Harness([(0, Self.party), (10, Self.scene("p2", .outdoors, Self.street.layers, transition: .leaveThroughDoor))])
        h.settle(upTo: 10)
        let partyGain = h.gain("party.wav")
        XCTAssertGreaterThan(partyGain, 0)
        XCTAssertEqual(h.muffle("party.wav"), 0)

        h.narrate(10, then: 0.1)
        XCTAssertEqual(h.played, ["open.wav"], "the door opens as they go out")
        XCTAssertTrue(h.events.contains(.transition(.leaveThroughDoor)))
        XCTAssertEqual(h.snapshot.transition, .leaveThroughDoor)
        h.scheduler.advance(by: 2)
        XCTAssertEqual(h.gain("party.wav"), partyGain, accuracy: 0.01, "the party follows them out of the open door")
        XCTAssertEqual(h.muffle("party.wav"), 0)
        XCTAssertGreaterThan(h.gain("street.wav"), 0, "the street has begun")

        h.scheduler.advance(by: 1.5)
        XCTAssertEqual(h.played, ["open.wav", "close.wav"], "the door shuts behind them")
        XCTAssertEqual(h.muffle("party.wav"), 1, accuracy: 0.01)
        let muffled = h.gain("party.wav")
        XCTAssertGreaterThan(muffled, 0)
        XCTAssertLessThan(muffled, partyGain * 0.5, "muffled and quieter behind the door")
        XCTAssertEqual(h.snapshot.voices.first { $0.recording == "Crowd/party.wav" }?.muffle ?? 0, 1, accuracy: 0.01)

        h.scheduler.advance(by: 12)
        XCTAssertFalse(h.backend.audible.keys.contains("party.wav"), "and fades away behind them")
        XCTAssertGreaterThan(h.gain("rain.wav"), 0, "the rain carried over")
        XCTAssertEqual(h.muffle("rain.wav"), 0, "and is not behind the door")
        XCTAssertGreaterThan(h.gain("street.wav"), 0)
    }

    func testBoardingACarShutsTheDoorAndStartsTheEngineBeforeTheRideBegins() throws {
        // No transition in the track: boarding is inferred from the street to the car.
        let h = try Harness([(0, Self.street), (10, Self.car)])
        h.settle(upTo: 10)
        h.narrate(10, then: 0.1)
        XCTAssertEqual(h.played, ["cardoor.wav"])
        XCTAssertEqual(h.snapshot.transition, .boardVehicle)
        XCTAssertEqual(h.gain("car.wav"), 0, "the ride has not begun")
        h.scheduler.advance(by: 2)
        XCTAssertEqual(h.played, ["cardoor.wav", "start.wav"], "the engine starts")
        h.scheduler.advance(by: 6)
        XCTAssertGreaterThan(h.gain("car.wav"), 0, "and the ride begins")
        XCTAssertFalse(h.backend.audible.keys.contains("street.wav"), "the street is shut out")
        XCTAssertFalse(h.backend.audible.keys.contains("rain.wav"))
    }

    func testAJumpByTheListenerIsAPlainChange() throws {
        let h = try Harness([(0, Self.party), (10, Self.scene("p2", .outdoors, Self.street.layers, transition: .leaveThroughDoor))])
        h.narrate(0, then: 30)
        h.player.narratorDidSeek(toGlobalSentenceIndex: 12)
        h.scheduler.advance(by: 4)
        XCTAssertEqual(h.played, [])
        XCTAssertNil(h.snapshot.transition)
        XCTAssertFalse(h.events.contains(.transition(.leaveThroughDoor)))
        XCTAssertEqual(h.muffle("party.wav"), 0)
    }

    func testPausingBeforeTheDoorShutsDropsIt() throws {
        let h = try Harness([(0, Self.party), (10, Self.scene("p2", .outdoors, Self.street.layers, transition: .leaveThroughDoor))])
        h.settle(upTo: 10)
        h.narrate(10, then: 1)
        XCTAssertEqual(h.played, ["open.wav"])
        h.player.narratorDidPause()
        h.scheduler.advance(by: 5)
        XCTAssertEqual(h.played, ["open.wav"], "no door shuts in the silence")
    }

    func testWithOneOffSoundsOffTheTimelineStillPlaysWithoutTheDoor() throws {
        let h = try Harness([(0, Self.party), (10, Self.scene("p2", .outdoors, Self.street.layers, transition: .leaveThroughDoor))], oneShotsOn: false)
        h.settle(upTo: 10)
        h.narrate(10, then: 3.6)
        XCTAssertEqual(h.played, [])
        XCTAssertEqual(h.muffle("party.wav"), 1, accuracy: 0.01)
        XCTAssertTrue(h.events.contains(.transition(.leaveThroughDoor)))
    }

    func testADoorShutOnANoiseKeepsItMuffledWhileTheStoryStays() throws {
        let hall = Self.scene("p1", .indoors, [SceneLayer(.crowd, .full)])
        let shut = Self.scene("p1", .indoors, [SceneLayer(.crowd, .faint)], transition: .doorClosesOnNoise)
        let ajar = Self.scene("p1", .indoors, [SceneLayer(.crowd, .soft)])
        let h = try Harness([(0, hall), (10, shut), (20, ajar), (30, Self.street)], oneShotsOn: false)
        h.settle(upTo: 10)
        h.narrate(10, then: 1.5)
        XCTAssertEqual(h.muffle("party.wav"), 1, accuracy: 0.01)
        for index in 11..<20 { h.narrate(index, then: 4) }
        h.narrate(20, then: 6)
        XCTAssertEqual(h.muffle("party.wav"), 1, accuracy: 0.01, "still behind the door")
        XCTAssertGreaterThan(h.gain("party.wav"), 0)
        for index in 21..<30 { h.narrate(index, then: 4) }
        // Out to the street: a door is inferred, so the hall holds for 3 s and fades over 10.
        h.narrate(30, then: 14)
        XCTAssertEqual(h.snapshot.transition, .leaveThroughDoor)
        XCTAssertFalse(h.backend.audible.keys.contains("party.wav"), "left behind with its place")
        XCTAssertGreaterThan(h.gain("street.wav"), 0)
    }

    func testFootstepsAreTheSameFootstepsInEveryPlace() throws {
        let lane = Self.scene("p1", .outdoors, [SceneLayer(.rain, .soft), SceneLayer(.footsteps, .faint)])
        let yard = Self.scene("p2", .outdoors, [SceneLayer(.rain, .soft), SceneLayer(.footsteps, .faint)])
        let h = try Harness([(0, lane), (10, yard)])
        h.settle(upTo: 10)
        XCTAssertGreaterThan(h.gain("steps.wav"), 0)
        let loads = h.backend.log.filter { $0.contains("steps.wav") }.count
        h.narrate(10, then: 10)
        XCTAssertEqual(h.backend.log.filter { $0.contains("steps.wav") }.count, loads, "the same recording keeps walking")
        XCTAssertGreaterThan(h.gain("steps.wav"), 0)
    }
}
