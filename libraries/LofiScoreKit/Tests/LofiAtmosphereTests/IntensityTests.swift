import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiAudioCore

/// The dial next to the volume (how much of a scene plays, how far the quieter sounds
/// sit back), the trim that keeps a rich scene no louder than one sound, and the small
/// lift in the gaps between sentences. The words stay clear through all of it.
final class IntensityTests: XCTestCase {
    static func track() throws -> AtmosphereTrack {
        try testTrack([
            (0, "p1", [SceneLayer(.fireplace, .full), SceneLayer(.rainIndoors, .soft), SceneLayer(.wind, .faint)], 0.9),
            (40, "p2", [SceneLayer(.rain, .soft)], 0.9),
        ])
    }

    func testTheDialDecidesHowManySoundsPlayAndHowFarTheRestSitBack() throws {
        XCTAssertEqual(AtmosphereConfig.layersKept(intensity: 0), 1)
        XCTAssertEqual(AtmosphereConfig.layersKept(intensity: 1), StoryScene.maxLayers)
        XCTAssertEqual(AtmosphereConfig.layersKept(intensity: 0.5), 3)
        XCTAssertEqual(AtmosphereConfig.layersKept(intensity: .nan), 1)

        var config = AtmosphereConfig()
        config.gapLiftDB = 0
        config.intensity = 0
        let h = PlayerTests.Harness(track: try Self.track(), config: config)
        h.narrate(0)
        XCTAssertEqual(h.audible.count, 1, "at zero, only the scene's main sound")
        let fire = try XCTUnwrap(h.audible.first)
        XCTAssertTrue(fire.hasPrefix("fire-"))
        // fire at full: -18 voice, -24 bed, file at -23: 19 dB down, alone so untrimmed.
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[fire])), pow(10, -19 / 20), accuracy: 0.002)
        XCTAssertEqual(h.snapshot.intensity, 0)

        h.player.setIntensity(1)
        h.scheduler.advance(by: 6)
        XCTAssertEqual(h.audible.count, 3, "turned up, the whole scene")
        XCTAssertEqual(h.snapshot.intensity, 1)
        let indoors = Double(try XCTUnwrap(h.backend.audible["indoors.wav"]))
        let wind = Double(try XCTUnwrap(h.backend.audible["wind.wav"]))
        let full = Double(try XCTUnwrap(h.backend.audible[fire]))
        // The scene is trimmed so that fire + rain (-5) + wind (-10) together are no louder
        // than the fire alone: 10 log10(1 + 0.316 + 0.1) = 1.5 dB off everything.
        let trim = 1 / (1 + pow(10, -0.5) + pow(10, -1.0))
        XCTAssertEqual(full, pow(10, -19 / 20) * trim, accuracy: 0.002)
        XCTAssertEqual(indoors, pow(10, -24 / 20) * trim, accuracy: 0.002)
        XCTAssertEqual(wind, pow(10, -29 / 20) * trim, accuracy: 0.002)

        h.player.setIntensity(0.5)
        h.scheduler.advance(by: 6)
        XCTAssertEqual(h.audible.count, 3, "halfway keeps three sounds")
        let halfIndoors = Double(try XCTUnwrap(h.backend.audible["indoors.wav"]))
        let halfFire = Double(try XCTUnwrap(h.backend.audible[fire]))
        // The rain sits 3 dB further back (half of the 6 dB secondary cut); the fire, being
        // the main sound, only gains from the lighter trim.
        let halfTrim = 1 / (1 + pow(10, -0.8) + pow(10, -1.3))
        XCTAssertEqual(halfFire, pow(10, -19 / 20) * halfTrim, accuracy: 0.002)
        XCTAssertEqual(halfIndoors, pow(10, -27 / 20) * halfTrim, accuracy: 0.002)
        XCTAssertGreaterThan(halfFire, full, "the main sound comes forward as the rest step back")

        h.player.setIntensity(2)
        XCTAssertEqual(h.snapshot.intensity, 1, "clamped")
        h.player.setIntensity(.nan)
        XCTAssertEqual(h.snapshot.intensity, 1, "ignored")
    }

    func testTheTrimKeepsAScenNoLouderThanItsMainSound() {
        XCTAssertEqual(AmbiencePlayer.sceneTrim(for: [], intensity: 1, secondaryCutDB: 6), 1)
        XCTAssertEqual(AmbiencePlayer.sceneTrim(for: [(SceneLayer(.rain), 0)], intensity: 1, secondaryCutDB: 6), 1)
        XCTAssertEqual(AmbiencePlayer.sceneTrim(for: [(SceneLayer(.rain), 0), (SceneLayer(.wind), 1)], intensity: 1, secondaryCutDB: 6), 0.5, accuracy: 0.0001,
                       "two sounds at the same level: 3 dB off")
        let quietSecond = AmbiencePlayer.sceneTrim(for: [(SceneLayer(.rain, .full), 0), (SceneLayer(.wind, .faint), 1)], intensity: 1, secondaryCutDB: 6)
        XCTAssertEqual(quietSecond, 1 / (1 + 0.1), accuracy: 0.0001, "a faint second sound, 10 dB down, costs 0.4 dB")
        XCTAssertGreaterThan(AmbiencePlayer.sceneTrim(for: [(SceneLayer(.rain), 0), (SceneLayer(.wind), 1)], intensity: 0, secondaryCutDB: 6), 0.5,
                             "at low intensity the second sound is already cut, so the trim is lighter")
        XCTAssertEqual(AmbiencePlayer.secondaryCut(rank: 0, intensity: 0, cutDB: 6), 0)
        XCTAssertEqual(AmbiencePlayer.secondaryCut(rank: 1, intensity: 0, cutDB: 6), -6)
        XCTAssertEqual(AmbiencePlayer.secondaryCut(rank: 2, intensity: 0.75, cutDB: 6), -1.5)
    }

    func testTheBedLiftsALittleInTheGapsBetweenSentencesAndDropsWhenTheVoiceReturns() throws {
        let config = AtmosphereConfig()
        XCTAssertEqual(config.bedLevelDB, -24)
        XCTAssertEqual(AtmosphereConfig.levelRange.upperBound, -14, "never louder than 14 dB under the voice")
        XCTAssertEqual(config.gapLiftDB, 4)
        let h = PlayerTests.Harness(track: try Self.track(), config: config)
        // A long first sentence lets the scene fade all the way in with no gap yet.
        h.player.sentenceDidStart(globalSentenceIndex: 0, duration: 20)
        h.scheduler.advance(by: 8)
        let fire = try XCTUnwrap(h.audible.first { $0.hasPrefix("fire-") })
        let bed = Double(try XCTUnwrap(h.backend.audible[fire]))
        XCTAssertFalse(h.snapshot.gapLifting)
        // A 4 s sentence; the lift waits for its end and a short delay, in case the next one follows at once.
        h.player.sentenceDidStart(globalSentenceIndex: 1, duration: 4)
        h.scheduler.advance(by: 4.5)
        XCTAssertFalse(h.snapshot.gapLifting)
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[fire])), bed, accuracy: 0.002)
        h.scheduler.advance(by: 1.5)
        XCTAssertTrue(h.snapshot.gapLifting)
        let lifted = Double(try XCTUnwrap(h.backend.audible[fire]))
        // 4 dB at full intensity, 3 dB at the default 0.75.
        XCTAssertEqual(lifted / bed, pow(10, 3.0 / 20), accuracy: 0.01)
        XCTAssertLessThanOrEqual(h.snapshot.scene?.layers.count ?? 0, 3)

        // The next sentence starts: the lift is gone within a quarter second.
        h.player.sentenceDidStart(globalSentenceIndex: 2, duration: 4)
        h.scheduler.advance(by: 0.3)
        XCTAssertFalse(h.snapshot.gapLifting)
        XCTAssertEqual(Double(try XCTUnwrap(h.backend.audible[fire])), bed, accuracy: 0.002)

        // A sentence that runs long (a slower narrator) gets no lift until it ends.
        h.scheduler.advance(by: 4)
        XCTAssertFalse(h.snapshot.gapLifting)
        h.scheduler.advance(by: 1.5)
        XCTAssertTrue(h.snapshot.gapLifting)

        // Pausing the narrator ends it too: the lift is for gaps in the reading, not for silence.
        h.player.narratorDidPause()
        h.scheduler.advance(by: 0.5)
        XCTAssertFalse(h.snapshot.gapLifting)
    }

    func testNoLiftAtZeroIntensityOrWithoutADurationOrDuringAHold() throws {
        var config = AtmosphereConfig()
        config.intensity = 0
        let still = PlayerTests.Harness(track: try Self.track(), config: config)
        still.narrate(0, then: 10)
        XCTAssertFalse(still.snapshot.gapLifting)

        let reading = PlayerTests.Harness(track: try Self.track(), config: AtmosphereConfig())
        reading.player.sentenceDidStart(globalSentenceIndex: 0, duration: nil)
        reading.scheduler.advance(by: 10)
        XCTAssertFalse(reading.snapshot.gapLifting, "reading on screen has no sentence timing")

        let dialled = PlayerTests.Harness(track: try Self.track(), config: AtmosphereConfig())
        dialled.narrate(0, then: 6)
        XCTAssertTrue(dialled.snapshot.gapLifting)
        dialled.player.setIntensity(0)
        dialled.scheduler.advance(by: 5)
        XCTAssertEqual(dialled.audible.count, 1, "the other sounds have faded out")
        XCTAssertTrue(dialled.snapshot.gapLifting, "a lift already on finishes with the sentence")
        dialled.player.sentenceDidStart(globalSentenceIndex: 1, duration: 4)
        dialled.scheduler.advance(by: 6)
        XCTAssertFalse(dialled.snapshot.gapLifting, "and none starts at zero")
    }
}
