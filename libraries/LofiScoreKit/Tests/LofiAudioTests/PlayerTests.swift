import XCTest
import LofiDirector
import LofiScoreCore
@testable import LofiAudio

final class PlayerTests: XCTestCase {
    // MARK: - Starting

    func testMusicNeverStartsBeforeTheNarrator() {
        let h = PlayerHarness()
        h.player.openBook(id: "book")
        h.send(.tense, trigger: .start, index: 0)
        h.send(.tense)
        h.advance(30)
        XCTAssertFalse(h.backend.calls.contains(.startEngine))
        XCTAssertTrue(h.playCalls(.a).isEmpty && h.playCalls(.b).isEmpty)
    }

    func testFirstPlayWaitsForTheFirstReadingAndStartsInItsMood() {
        let h = PlayerHarness()
        h.player.openBook(id: "book")
        h.player.narratorDidPlay()
        h.advance(0.5)
        XCTAssertFalse(h.backend.calls.contains(.startEngine), "waits up to startGrace for a reading")
        h.send(.mysterious, trigger: .start, index: 0)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.mood(on: .a), .mysterious)
        h.advance(2.1)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
        XCTAssertEqual(h.gain(.b), 0)
        XCTAssertTrue(h.crossfades.isEmpty, "started in the right mood instead of crossfading")
    }

    func testWithoutAReadingTheMusicStartsCalmAfterTheGrace() {
        let h = PlayerHarness()
        h.player.openBook(id: "book")
        h.player.narratorDidPlay()
        h.advance(1.4)
        XCTAssertFalse(h.backend.isPlaying(.a))
        h.advance(0.2)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.mood(on: .a), .calm)
    }

    func testFadeInRisesToTheBedLevel() {
        let h = PlayerHarness()
        h.player.openBook(id: "book")
        h.player.narratorDidPlay()
        h.send(.calm, trigger: .start, index: 0)
        h.advance(1)
        let halfway = h.gain(.a)
        XCTAssertGreaterThan(halfway, 0.5 * h.bedGain)
        XCTAssertLessThan(halfway, h.bedGain)
        h.advance(1.05)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    // MARK: - Crossfades

    func testConfirmedChangeCrossfadesGentlyWithEqualPower() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        var waited = 0.0
        while h.decisions.isEmpty, waited < 400 {
            h.advance(20)
            waited += 20
            h.send(.tense)
        }
        XCTAssertEqual(h.decisions.last?.bucket, .tense)
        XCTAssertEqual(h.decisions.last?.transition, .gentle)
        guard let crossfade = h.crossfades.last else { return XCTFail("no crossfade") }
        XCTAssertEqual(crossfade.transition, .gentle)
        XCTAssertEqual(crossfade.duration, 7, accuracy: 1e-9)

        // Sample the whole crossfade: the summed power stays at the bed level.
        var sawBothDecks = false
        for _ in 0..<28 {
            h.advance(0.25)
            let a = h.gain(.a) / h.bedGain
            let b = h.gain(.b) / h.bedGain
            XCTAssertEqual(a * a + b * b, 1, accuracy: 2e-3)
            if a > 0.2, b > 0.2 { sawBothDecks = true }
        }
        XCTAssertTrue(sawBothDecks)
        h.advance(0.1)
        XCTAssertEqual(h.mood(on: .b), .tense)
        XCTAssertFalse(h.backend.isPlaying(.a), "the outgoing deck stops once silent")
        XCTAssertEqual(h.gain(.b), h.bedGain, accuracy: 1e-4)
    }

    func testSeekWaitsForTheNewPlaceAndCrossfadesQuickly() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(30)
        h.player.narratorDidSeek(toGlobalSentenceIndex: 900)
        h.advance(3)
        XCTAssertTrue(h.crossfades.isEmpty, "the music holds until the new place has a reading")
        XCTAssertTrue(h.backend.isPlaying(.a))
        h.send(.tense, trigger: .seek, index: 900)
        guard let crossfade = h.crossfades.last else { return XCTFail("no crossfade") }
        XCTAssertEqual(crossfade.transition, .quick)
        XCTAssertEqual(crossfade.duration, 3.5, accuracy: 1e-9)
        h.advance(3.6)
        XCTAssertEqual(h.mood(on: .b), .tense)
        XCTAssertFalse(h.backend.isPlaying(.a))
    }

    func testSeekToTheSameMoodKeepsTheTrack() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(30)
        h.seek(to: 400, finding: .calm)
        h.advance(10)
        XCTAssertTrue(h.crossfades.isEmpty)
        XCTAssertEqual(h.playCalls(.a).count, 1)
    }

    func testCrossfadeStartsOnTheNextBarLine() {
        // 80 BPM in 4/4: a bar every 3 seconds.
        let h = PlayerHarness(bpm: 80)
        h.startPlaying(in: .calm)  // deck A at position 0 at t = 0.2
        h.advance(4.2 - h.now)  // position 4.0
        h.seek(to: 300, finding: .tense)
        XCTAssertTrue(h.crossfades.isEmpty)
        XCTAssertEqual(h.snapshot().pendingMood, .tense)
        h.advance(1.99)
        XCTAssertTrue(h.crossfades.isEmpty)
        h.advance(0.02)
        XCTAssertEqual(h.crossfades.count, 1)
        XCTAssertEqual(h.crossfades[0].time, 6.2, accuracy: 1e-6)
    }

    func testBarWaitIsCapped() {
        // 30 BPM: an 8-second bar is longer than maxBarWait, so the change starts at once.
        let h = PlayerHarness(bpm: 30)
        h.startPlaying(in: .calm)
        h.advance(1)
        h.seek(to: 300, finding: .tense)
        XCTAssertEqual(h.crossfades.count, 1)
    }

    func testChangingBackBeforeTheBarLineCancelsTheChange() {
        let h = PlayerHarness(bpm: 80)
        h.startPlaying(in: .calm)
        h.advance(4.2 - h.now)
        h.seek(to: 300, finding: .tense)
        h.advance(1)
        h.seek(to: 10, finding: .calm)
        h.advance(5)
        XCTAssertTrue(h.crossfades.isEmpty)
        XCTAssertNil(h.snapshot().pendingMood)
    }

    func testReversingHalfwayKeepsTheGainsContinuous() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(10)
        h.seek(to: 500, finding: .tense)  // A → B over 3.5 s
        h.advance(1.75)
        let before = (a: h.gain(.a), b: h.gain(.b))
        h.seek(to: 20, finding: .calm)
        XCTAssertTrue(h.events.contains { if case .crossfadeReversed(.a) = $0.event { return true } else { return false } })
        XCTAssertEqual(h.gain(.a), before.a, accuracy: 0.02)
        XCTAssertEqual(h.gain(.b), before.b, accuracy: 0.02)
        XCTAssertEqual(h.snapshot().activeDeck, .a)
        // Halfway back takes half the quick crossfade.
        h.advance(1.8)
        XCTAssertFalse(h.backend.isPlaying(.b))
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
        XCTAssertEqual(h.playCalls(.a).count, 1, "deck A kept playing; it was never restarted")
    }

    func testChangeDuringACrossfadeWaitsForItToFinish() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(10)
        h.seek(to: 500, finding: .tense)
        h.advance(1)
        h.seek(to: 900, finding: .somber)
        XCTAssertEqual(h.crossfades.count, 1)
        XCTAssertEqual(h.snapshot().pendingMood, .somber)
        h.advance(2.6)
        XCTAssertEqual(h.crossfades.count, 2)
        XCTAssertEqual(h.mood(on: .a), .somber)
        h.advance(3.6)
        XCTAssertEqual(h.snapshot().musicMood, .somber)
        XCTAssertFalse(h.backend.isPlaying(.b))
    }

    func testMoodChangeDuringARotationHurriesTheRotation() {
        let h = PlayerHarness(duration: 60)
        h.startPlaying(in: .calm)
        h.advance(54.2 - h.now)  // one second into a 7-second rotation
        XCTAssertEqual(h.crossfades.count, 1)
        h.seek(to: 500, finding: .tense)
        XCTAssertEqual(h.snapshot().pendingMood, .tense)
        // The 6 seconds left of the rotation now take 6/7 of the quick 3.5 s.
        h.advance(2.9)
        XCTAssertEqual(h.crossfades.count, 1)
        h.advance(0.2)
        XCTAssertEqual(h.crossfades.count, 2)
        XCTAssertEqual(h.crossfades[1].time, 57.2, accuracy: 0.05)
        XCTAssertEqual(h.crossfades[1].transition, .quick)
        h.advance(3.6)
        XCTAssertEqual(h.snapshot().musicMood, .tense)
    }

    func testGentleChangeDuringAGentleCrossfadeWaitsAtItsOwnPace() {
        let h = PlayerHarness(duration: 300)
        h.startPlaying(in: .calm)
        h.advance(100)
        h.send(.tense, confidence: 0.75)
        h.advance(20)
        h.send(.tense, confidence: 0.75)
        guard let first = h.crossfades.last, first.transition == .gentle else { return XCTFail("no gentle change") }
        h.advance(1)
        // A chapter start may change the mood at once, but its gentle fade waits its turn.
        h.send(.cozy, trigger: .chapterStart, confidence: 0.75)
        XCTAssertEqual(h.decisions.last?.bucket, .cozy)
        XCTAssertEqual(h.snapshot().pendingMood, .cozy)
        h.advance(first.time + first.duration - h.now - 0.05)
        XCTAssertEqual(h.crossfades.count, 1, "the first fade keeps its pace")
        h.advance(0.1)
        XCTAssertEqual(h.crossfades.count, 2)
        XCTAssertEqual(h.crossfades[1].transition, .gentle)
    }

    func testGainsUpdateAtLeast30TimesASecondWhileFading() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(10)
        h.backend.clearLog()
        let start = h.now
        h.seek(to: 500, finding: .tense)
        h.advance(3.5)
        let times = h.backend.gainLog.filter { $0.deck == .b && $0.time >= start }.map(\.time)
        XCTAssertGreaterThan(times.count, 100)
        for (earlier, later) in zip(times, times.dropFirst()) {
            XCTAssertLessThanOrEqual(later - earlier, 1.0 / 30 + 1e-9)
        }
        // Once everything rests, the ticker stops.
        h.advance(1)
        h.backend.clearLog()
        h.advance(5)
        XCTAssertTrue(h.backend.gainLog.isEmpty)
    }

    // MARK: - Track rotation

    func testTrackEndingRotatesToAnotherTrackOfTheSameMood() {
        let h = PlayerHarness(duration: 60)
        h.startPlaying(in: .calm)
        h.advance(53.2 - h.now - 0.01)
        XCTAssertTrue(h.crossfades.isEmpty)
        h.advance(0.02)
        XCTAssertEqual(h.crossfades.count, 1)
        XCTAssertEqual(h.crossfades[0].transition, .rotation)
        XCTAssertEqual(h.crossfades[0].duration, 7, accuracy: 1e-6)

        h.advance(60 * 6)
        let files = h.startedFiles
        XCTAssertGreaterThanOrEqual(files.count, 6)
        XCTAssertTrue(files.allSatisfy { $0.hasPrefix("calm-") })
        for index in files.indices.dropFirst() {
            let recent = files[max(0, index - 3)..<index]
            XCTAssertFalse(recent.contains(files[index]), "\(files[index]) repeated within three tracks: \(files)")
        }
    }

    func testRotationStartsOnABarLine() {
        // 120 BPM: 2-second bars. A 61-second track rotates at the bar before 54 s.
        let h = PlayerHarness(bpm: 120, duration: 61)
        h.startPlaying(in: .calm)
        h.advance(60)
        guard let rotation = h.crossfades.first else { return XCTFail("no rotation") }
        XCTAssertEqual(rotation.time, 0.2 + 54, accuracy: 1e-6)
        XCTAssertEqual(rotation.duration, 7, accuracy: 1e-6)
    }

    func testTrackThatEndsEarlyIsReplaced() {
        let h = PlayerHarness(duration: 300)
        h.startPlaying(in: .calm)
        h.advance(20)
        let first = h.backend.file(on: .a)
        h.backend.finish(.a)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertNotEqual(h.backend.file(on: .a), first)
        XCTAssertEqual(h.mood(on: .a), .calm)
    }

    // MARK: - Ducking

    func testMusicRisesInLongSilencesAndSettlesWhenTheVoiceReturns() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)  // now 2.3
        h.player.sentenceDidStart(globalSentenceIndex: nil, duration: 3)
        h.advance(4.4)  // 6.7: silence for 1.4 s
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
        h.advance(1.7)  // 8.4: lifted fully since 8.3
        XCTAssertEqual(h.gain(.a), h.bedGain * Gain.linear(fromDB: 4), accuracy: 1e-3)
        XCTAssertEqual(h.snapshot().duckOffsetDB, 4, accuracy: 1e-9)
        h.player.sentenceDidStart(globalSentenceIndex: nil, duration: 2)
        h.advance(0.45)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    func testShortPausesBetweenSentencesDoNotLiftTheMusic() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        for _ in 0..<20 {
            h.player.sentenceDidStart(globalSentenceIndex: nil, duration: 3)
            h.advance(3.5)
            XCTAssertEqual(h.snapshot().duckOffsetDB, 0)
        }
    }

    func testHostsThatReportSentenceEndsGetTheLiftToo() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.sentenceDidStart(globalSentenceIndex: nil, duration: nil)
        h.advance(10)
        XCTAssertEqual(h.snapshot().duckOffsetDB, 0, "without a duration or an end, no silence is assumed")
        h.player.sentenceDidEnd()
        h.advance(1.5 + 1.5 + 0.01)
        XCTAssertEqual(h.snapshot().duckOffsetDB, 4, accuracy: 1e-9)
    }

    func testBedLevelFollowsTheSettings() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        var ducking = DuckingSettings()
        ducking.bedLevelDB = -18
        h.player.setDucking(ducking)
        XCTAssertEqual(h.gain(.a), Gain.linear(fromDB: -18 - 18 + 16), accuracy: 1e-4)
        h.player.setMusicVolume(0.5)
        XCTAssertEqual(h.gain(.a), 0.5 * Gain.linear(fromDB: -18 - 18 + 16), accuracy: 1e-4)
    }

    // MARK: - Pause, sleep, close

    func testPauseFadesOutThenStopsTheEngineAfterTwoMinutes() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)  // now 2.3, deck A at position 2.1
        h.player.narratorDidPause()
        h.advance(0.5)
        XCTAssertGreaterThan(h.gain(.a), 0)
        XCTAssertLessThan(h.gain(.a), h.bedGain)
        h.advance(0.6)
        XCTAssertEqual(h.gain(.a), 0)
        XCTAssertFalse(h.backend.isPlaying(.a))
        XCTAssertTrue(h.backend.isEngineRunning)
        h.advance(118)
        XCTAssertTrue(h.backend.isEngineRunning)
        h.advance(2)
        XCTAssertFalse(h.backend.isEngineRunning)

        h.player.narratorDidPlay()
        XCTAssertEqual(h.count(.startEngine), 2)
        XCTAssertEqual(h.playCalls(.a).last ?? -1, 3.1, accuracy: 1e-6, "resumes where the fade-out ended")
        h.advance(2.05)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    func testPlayingAgainDuringTheFadeOutJustFadesBackIn() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.narratorDidPause()
        h.advance(0.5)
        h.player.narratorDidPlay()
        h.advance(3)
        XCTAssertFalse(h.backend.calls.contains(.stop(.a)))
        XCTAssertEqual(h.playCalls(.a).count, 1)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    func testChangeWhilePausedHappensSilently() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.narratorDidPause()
        h.advance(1.1)
        h.seek(to: 700, finding: .tense)
        XCTAssertTrue(h.crossfades.isEmpty)
        XCTAssertEqual(h.mood(on: .a), .tense)
        h.player.narratorDidPlay()
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.playCalls(.a).last, 0, "a new track starts from its beginning")
    }

    func testChangeDuringTheFadeOutHappensOnceSilent() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.narratorDidPause()
        h.advance(0.3)
        h.seek(to: 700, finding: .tense)
        XCTAssertEqual(h.mood(on: .a), .calm)
        h.advance(0.8)
        XCTAssertTrue(h.crossfades.isEmpty)
        XCTAssertEqual(h.mood(on: .a), .tense)
    }

    func testTurningMusicOffAndOn() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.setEnabled(false)
        h.advance(1.1)
        XCTAssertFalse(h.backend.isPlaying(.a))
        h.player.setEnabled(true)
        h.advance(2.1)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    func testClosingTheBookFadesOutAndForgetsIt() {
        let h = PlayerHarness()
        h.startPlaying(in: .tense)
        h.player.closeBook()
        h.advance(1.1)
        let snapshot = h.snapshot()
        XCTAssertNil(snapshot.bookID)
        XCTAssertTrue(snapshot.decks.allSatisfy { $0.trackID == nil })
        XCTAssertEqual(snapshot.director.currentBucket, .calm)
        XCTAssertFalse(h.backend.isPlaying(.a))

        h.send(.somber, trigger: .start, index: 0)
        XCTAssertTrue(h.decisions.allSatisfy { $0.bucket != .somber }, "no book, no readings")

        h.player.openBook(id: "second")
        h.advance(1.6)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.mood(on: .a), .calm, "the new book starts fresh")
    }

    func testOpeningAnotherBookWhilePlayingFadesTheOldMusicFirst() {
        let h = PlayerHarness()
        h.startPlaying(in: .tense)
        h.player.openBook(id: "second")
        h.advance(0.5)
        XCTAssertEqual(h.mood(on: .a), .tense, "still fading out")
        h.send(.cozy, trigger: .start, index: 0)
        h.advance(0.6)
        XCTAssertEqual(h.mood(on: .a), .cozy)
        XCTAssertTrue(h.backend.isPlaying(.a))
    }

    // MARK: - Routes and interruptions

    func testHeadphonesPulledStopsTheMusicAtOnce() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.backend.simulateRouteChange(to: .builtIn, previousOutputLost: true)
        h.advance(0.15)
        XCTAssertEqual(h.gain(.a), 0)
        XCTAssertFalse(h.backend.isPlaying(.a))
        XCTAssertFalse(h.snapshot().narrating)
        h.advance(5)
        XCTAssertFalse(h.backend.isPlaying(.a), "waits for the narrator to play again")
        h.player.narratorDidPlay()
        XCTAssertTrue(h.backend.isPlaying(.a))
    }

    func testMusicStaysOffOnMutedRoutes() {
        var config = ScoreConfig.mechanics
        config.mutedRoutes = [.carPlay]
        let h = PlayerHarness(config: config)
        h.startPlaying(in: .calm)
        h.backend.simulateRouteChange(to: .carPlay, previousOutputLost: false)
        h.advance(1.1)
        XCTAssertFalse(h.backend.isPlaying(.a))
        XCTAssertTrue(h.snapshot().routeMuted)
        h.player.narratorDidPlay()
        XCTAssertFalse(h.backend.isPlaying(.a))
        h.backend.simulateRouteChange(to: .bluetooth, previousOutputLost: false)
        XCTAssertTrue(h.backend.isPlaying(.a))
    }

    func testRestartsAfterAConfigurationChange() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.advance(10)  // position 12.1
        h.backend.simulateRestartNeeded(.configurationChange)
        XCTAssertTrue(h.backend.isEngineRunning)
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.playCalls(.a).last ?? -1, 12.1, accuracy: 1e-6)
        h.advance(0.6)
        XCTAssertEqual(h.gain(.a), h.bedGain, accuracy: 1e-4)
    }

    func testRebuildsAndReloadsAfterAMediaServicesReset() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        let file = h.backend.file(on: .a)
        h.advance(5)
        h.backend.clearLog()
        h.backend.simulateRestartNeeded(.mediaServicesReset)
        XCTAssertTrue(h.backend.calls.contains(.rebuild))
        XCTAssertTrue(h.backend.calls.contains(.load(file: file ?? "", deck: .a)))
        XCTAssertTrue(h.backend.isPlaying(.a))
        XCTAssertEqual(h.backend.file(on: .a), file)
    }

    func testRestartNotNeededWhilePaused() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.narratorDidPause()
        h.advance(2)
        h.backend.clearLog()
        h.backend.simulateRestartNeeded(.interruptionEnded)
        XCTAssertFalse(h.backend.calls.contains(.startEngine))
    }

    func testEngineThatWillNotStartIsRetried() {
        let h = PlayerHarness()
        h.backend.engineStartFails = true
        h.player.openBook(id: "book")
        h.player.narratorDidPlay()
        h.send(.calm, trigger: .start, index: 0)
        XCTAssertFalse(h.backend.isPlaying(.a))
        XCTAssertFalse(h.errors.isEmpty)
        h.backend.engineStartFails = false
        h.advance(1.01)
        XCTAssertTrue(h.backend.isPlaying(.a))
    }

    // MARK: - Library problems

    func testEmptyBucketFallsBackToTheNearestMood() {
        let h = PlayerHarness(buckets: MoodBucket.allCases.filter { $0 != .tense })
        h.startPlaying(in: .calm)
        h.seek(to: 300, finding: .tense)
        let fallback = h.events.compactMap { entry -> (MoodBucket, MoodBucket)? in
            if case let .fallback(requested, used) = entry.event { return (requested, used) }
            return nil
        }.first
        XCTAssertEqual(fallback?.0, .tense)
        XCTAssertNotNil(fallback?.1)
        XCTAssertEqual(h.mood(on: .b), fallback?.1)
        XCTAssertEqual(h.snapshot().musicMood, .tense, "the music stands for the mood it was asked for")
    }

    func testBrokenFilesAreSkipped() {
        let h = PlayerHarness(failingFiles: ["calm-1.wav", "calm-2.wav", "calm-3.wav"])
        h.startPlaying(in: .calm)
        XCTAssertEqual(h.backend.file(on: .a), "calm-4.wav")
        XCTAssertTrue(h.backend.isPlaying(.a))
    }

    // MARK: - Spoilers

    func testReadingsAheadOfTheVoiceNeverChangeTheMusic() {
        let h = PlayerHarness()
        h.startPlaying(in: .calm)
        h.player.sentenceDidStart(globalSentenceIndex: 10, duration: 2)
        for step in 0..<20 {
            h.advance(15)
            h.send(.tense, confidence: 0.95, index: 200 + step * 4)
        }
        XCTAssertTrue(h.decisions.isEmpty)
        XCTAssertTrue(h.crossfades.allSatisfy { $0.transition == .rotation }, "only track rotations, no mood change")
        XCTAssertEqual(h.snapshot().musicMood, .calm)
        XCTAssertGreaterThan(h.snapshot().director.ignoredCounts[.aheadOfPlayhead] ?? 0, 0)
    }
}
