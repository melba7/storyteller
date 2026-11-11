import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiAudioCore

final class PlayerTests: XCTestCase {
    /// Two fires and two rains to choose between, one of everything else; no sea.
    static let library = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
        AmbienceRecording(id: "fireplace/a", file: "Fireplace/fire-a.wav", sound: .fireplace, loudness: -23),
        AmbienceRecording(id: "fireplace/b", file: "Fireplace/fire-b.wav", sound: .fireplace, loudness: -23),
        AmbienceRecording(id: "fireplace/c", file: "Fireplace/fire-c.wav", sound: .fireplace, loudness: -23),
        AmbienceRecording(id: "rain/a", file: "Rain/rain-a.wav", sound: .rain, loudness: -23),
        AmbienceRecording(id: "rain/b", file: "Rain/rain-b.wav", sound: .rain, loudness: -23),
        AmbienceRecording(id: "rainIndoors/a", file: "RainIndoors/indoors.wav", sound: .rainIndoors, loudness: -23),
        AmbienceRecording(id: "oldTown/a", file: "OldTown/town.wav", sound: .oldTown, loudness: -30),
        AmbienceRecording(id: "crowd/a", file: "Crowd/crowd.wav", sound: .crowd, loudness: -23),
        AmbienceRecording(id: "wind/a", file: "Wind/wind.wav", sound: .wind, loudness: -23),
    ])

    final class Harness {
        let scheduler = ManualScheduler()
        let backend = FakeAmbienceBackend()
        let player: AmbiencePlayer
        var yields: [Bool] = []
        var events: [AmbienceEvent] = []

        /// The steady bed as these tests know it: the whole scene, and no lift in the
        /// gaps between sentences (``IntensityTests`` cover the dial and the lift).
        static var steadyConfig: AtmosphereConfig {
            var config = AtmosphereConfig()
            config.intensity = 1
            config.gapLiftDB = 0
            return config
        }

        init(track: AtmosphereTrack?, config: AtmosphereConfig = Harness.steadyConfig) {
            player = AmbiencePlayer(library: PlayerTests.library, backend: backend, scheduler: scheduler, config: config, seed: 7)
            player.onMusicYieldChanged = { [unowned self] in yields.append($0) }
            player.onEvent = { [unowned self] in events.append($0) }
            player.openBook(id: "book")
            player.setTrack(track, forBook: "book")
            player.narratorDidPlay()
        }

        /// Narrates sentence `index` and lets `seconds` pass.
        func narrate(_ index: Int, then seconds: TimeInterval = 8) {
            player.sentenceDidStart(globalSentenceIndex: index, duration: 4)
            scheduler.advance(by: seconds)
        }

        var snapshot: AmbienceSnapshot {
            var result: AmbienceSnapshot?
            player.snapshot { result = $0 }
            return result!
        }

        var audible: Set<String> { Set(backend.audible.keys) }
    }

    static func track() throws -> AtmosphereTrack {
        try testTrack([
            (0, "p1", [SceneLayer(.fireplace, .full)], 0.9),
            (10, "p2", [SceneLayer(.oldTown), SceneLayer(.rain)], 0.9),
            (20, "p3", [SceneLayer(.crowd), SceneLayer(.fireplace, .faint)], 0.9),
            (30, "p1", [SceneLayer(.fireplace, .full), SceneLayer(.rainIndoors)], 0.9),
            (40, "p4", [SceneLayer(.wind), SceneLayer(.rain)], 0.9),
            (50, "p5", [SceneLayer(.seaShore)], 0.9),
        ])
    }

    func testScenesFollowTheNarrationAndPlacesKeepTheirSounds() throws {
        let h = Harness(track: try Self.track())
        h.narrate(0)
        XCTAssertEqual(h.audible.count, 1)
        let tavernFire = try XCTUnwrap(h.audible.first)
        XCTAssertTrue(tavernFire.hasPrefix("fire-"))
        // fire at full: -18 voice, -16 bed, file at -23 LUFS: 11 dB down.
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[tavernFire])), pow(10, -11 / 20), accuracy: 0.002)

        // The street arrives at 10 but the tavern has only played 8 s: it waits for the dwell.
        h.narrate(10, then: 4)
        XCTAssertEqual(h.audible, [tavernFire])
        h.scheduler.advance(by: 16)
        XCTAssertEqual(h.audible, ["town.wav", h.audible.first { $0.hasPrefix("rain-") } ?? "missing rain"])
        let rain = try XCTUnwrap(h.audible.first { $0.hasPrefix("rain-") })
        // town at soft: -18 voice, -16 bed, -5 soft, file at -30: 9 dB down, then the scene
        // (two sounds at the same level) is trimmed 3 dB so it is no louder than one.
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible["town.wav"])), pow(10, -9 / 20) / 2, accuracy: 0.002,
                       "a quieter file is turned up to the same level")

        // The hall has a crowd: the music steps aside, and comes back when the scene moves on.
        h.narrate(20, then: 25)
        XCTAssertEqual(h.yields, [true])
        XCTAssertTrue(h.snapshot.musicYielding)
        XCTAssertTrue(h.audible.contains("crowd.wav"))
        XCTAssertEqual(h.backend.slots.first { $0.url?.lastPathComponent == "crowd.wav" }?.filter, .speechSafe)

        // Back in the tavern: the same fire as before, with rain on the windows now.
        h.narrate(30, then: 25)
        XCTAssertEqual(h.yields, [true, false])
        XCTAssertEqual(h.audible, [tavernFire, "indoors.wav"])

        // Out on the moor: the book's rain is the same rain as in the street.
        h.narrate(40, then: 25)
        XCTAssertEqual(h.audible, ["wind.wav", rain])

        // A sound the library does not have is reported, and the rest carries on.
        h.narrate(50, then: 25)
        XCTAssertEqual(h.snapshot.missingSounds, [.seaShore])
        XCTAssertTrue(h.events.contains(.missingSound(.seaShore)))
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertNil(h.snapshot.lastError)
    }

    func testPausingFadesOutStopsTheLoopsAndLaterTheEngine() throws {
        let h = Harness(track: try Self.track())
        h.narrate(0)
        XCTAssertTrue(h.backend.isEngineRunning)
        h.player.narratorDidPause()
        h.scheduler.advance(by: 2)
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertFalse(h.backend.slots.contains { $0.playing })
        XCTAssertTrue(h.backend.isEngineRunning)
        h.scheduler.advance(by: 120)
        XCTAssertFalse(h.backend.isEngineRunning)

        h.player.narratorDidPlay()
        h.scheduler.advance(by: 4)
        XCTAssertTrue(h.backend.isEngineRunning)
        XCTAssertEqual(h.audible.count, 1)
    }

    func testSwitchingOffOrAMutedRouteSilencesItAndReleasesTheMusic() throws {
        let h = Harness(track: try Self.track())
        h.narrate(20, then: 8)
        XCTAssertEqual(h.yields, [true])
        h.player.setEnabled(false)
        h.scheduler.advance(by: 2)
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertEqual(h.yields, [true, false])

        h.player.setEnabled(true)
        h.scheduler.advance(by: 4)
        XCTAssertEqual(h.yields, [true, false, true])
        h.player.setMutedRoutes([.carPlay])
        h.backend.simulateRoute(.carPlay, previousOutputLost: false)
        h.scheduler.advance(by: 2)
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertTrue(h.snapshot.routeMuted)
        XCTAssertEqual(h.yields.last, false)
    }

    func testHeadphonesPulledGoesQuietAtOnce() throws {
        let h = Harness(track: try Self.track())
        h.narrate(0)
        h.backend.simulateRoute(.builtIn, previousOutputLost: true)
        h.scheduler.advance(by: 0.2)
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertFalse(h.snapshot.narrating)
    }

    func testAMediaResetReloadsWhatWasPlaying() throws {
        let h = Harness(track: try Self.track())
        h.narrate(0)
        let before = h.audible
        h.backend.simulateRestart(.mediaServicesReset)
        h.scheduler.advance(by: 4)
        XCTAssertTrue(h.backend.log.contains("rebuild"))
        XCTAssertEqual(h.audible, before)
    }

    func testNoTrackMeansSilenceAndALateTrackStartsAtThePlayhead() throws {
        let h = Harness(track: nil)
        h.narrate(12)
        XCTAssertTrue(h.audible.isEmpty)
        XCTAssertFalse(h.snapshot.hasTrack)
        h.player.setTrack(try Self.track(), forBook: "book")
        h.scheduler.advance(by: 4)
        XCTAssertEqual(h.snapshot.scene?.placeID, "p2", "the scene at sentence 12, not the book's first")
        h.player.setTrack(try Self.track(), forBook: "another book")
        h.player.closeBook()
        h.scheduler.advance(by: 2)
        XCTAssertTrue(h.audible.isEmpty)

        // A track that arrives just before its book opens is kept for it.
        h.player.openBook(id: "another book")
        h.narrate(0, then: 4)
        XCTAssertEqual(h.snapshot.scene?.placeID, "p1")
        XCTAssertEqual(h.audible.count, 1)
    }

    func testTheLevelSliderMovesEverySound() throws {
        let h = Harness(track: try Self.track())
        h.narrate(0)
        let fire = try XCTUnwrap(h.audible.first)
        h.player.setLevel(dB: -22)
        h.scheduler.advance(by: 2)
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[fire])), pow(10, -17 / 20), accuracy: 0.002)
        h.player.setLevel(dB: 0)
        h.scheduler.advance(by: 2)
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[fire])), pow(10, 1.0 / 20), accuracy: 0.002, "capped at -4 dB, the file turned up 1 dB to get there")
    }
}
