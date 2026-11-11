import XCTest
import LofiScoreCore
@testable import LofiDirector

final class DirectorTests: XCTestCase {
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
    }

    /// A config whose evidence fades almost at once, so each test sees the rules,
    /// not the smoothing.
    private func sharpConfig() -> DirectorConfig {
        var config = DirectorConfig()
        config.evidenceTimeConstant = 2
        return config
    }

    private func reading(_ bucket: MoodBucket, confidence: Double = 0.7) -> MoodReading {
        MoodReading(
            bucket: bucket,
            valence: bucket.anchor.valence,
            arousal: bucket.anchor.arousal,
            confidence: confidence,
            engineID: "test"
        )
    }

    private func observation(
        _ bucket: MoodBucket,
        index: Int,
        confidence: Double = 0.7,
        trigger: ReadingTrigger = .cadence
    ) -> MoodObservation {
        MoodObservation(
            reading: reading(bucket, confidence: confidence),
            chapterOrdinal: 0,
            sentenceIndex: index,
            globalSentenceIndex: index,
            trigger: trigger
        )
    }

    func testStartsNeutralAndFirstReadingDecidesAtOnce() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        XCTAssertEqual(director.currentBucket, .calm)
        XCTAssertEqual(director.phase, .awaitingFirstReading)

        clock.advance(by: 1)
        let decision = director.receive(observation(.mysterious, index: 3, trigger: .start))
        XCTAssertEqual(decision?.bucket, .mysterious)
        XCTAssertEqual(decision?.previous, .calm)
        XCTAssertEqual(decision?.reason, .firstReading)
        XCTAssertEqual(decision?.transition, .quick)
        XCTAssertEqual(director.phase, .following)
    }

    func testFirstReadingThatAgreesWithNeutralChangesNothing() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        XCTAssertNil(director.receive(observation(.calm, index: 1, trigger: .start)))
        XCTAssertEqual(director.currentBucket, .calm)
    }

    func testNewMoodMustWinTwoReadingsInARow() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.calm, index: 1, trigger: .start))

        clock.advance(by: 20)
        XCTAssertNil(director.receive(observation(.somber, index: 5)), "one reading is not enough")
        XCTAssertEqual(director.snapshot.pendingBucket, .somber)
        XCTAssertEqual(director.snapshot.pendingCount, 1)

        clock.advance(by: 20)
        XCTAssertNil(director.receive(observation(.calm, index: 9)), "the run is broken")
        XCTAssertNil(director.snapshot.pendingBucket)

        clock.advance(by: 20)
        XCTAssertNil(director.receive(observation(.somber, index: 13)))
        clock.advance(by: 20)
        let decision = director.receive(observation(.somber, index: 17))
        XCTAssertEqual(decision?.bucket, .somber)
        XCTAssertEqual(decision?.reason, .confirmed)
        XCTAssertEqual(decision?.transition, .gentle)
    }

    func testMinimumDwellHoldsAChangeAndReleasesItAtTheDeadline() {
        let director = MoodDirector(clock: clock)
        clock.advance(by: 2)
        XCTAssertEqual(director.receive(observation(.tense, index: 2, confidence: 0.5, trigger: .start))?.bucket, .tense)

        // Cozy takes the lead at t = 22 and has held it for 20 s by t = 42: confirmed, but
        // the music changed to tense at t = 2.
        for (time, index) in [(12.0, 4), (22.0, 6), (32.0, 8), (42.0, 10)] {
            clock.advance(to: time)
            XCTAssertNil(director.receive(observation(.cozy, index: index, confidence: 0.75)), "t = \(time)")
        }
        XCTAssertEqual(director.currentBucket, .tense)
        XCTAssertEqual(director.snapshot.pendingBucket, .cozy)
        XCTAssertEqual(director.nextDeadline, 62)
        XCTAssertEqual(director.snapshot.dwellRemaining, 20, accuracy: 1e-9)

        clock.advance(to: 52)
        XCTAssertNil(director.receive(observation(.cozy, index: 12, confidence: 0.75)))
        clock.advance(to: 61)
        XCTAssertNil(director.tick(), "still inside the dwell")
        clock.advance(to: 62)
        let decision = director.tick()
        XCTAssertEqual(decision?.bucket, .cozy)
        XCTAssertEqual(decision?.reason, .dwellElapsed)
        XCTAssertNil(director.nextDeadline)
    }

    func testHeldChangeIsDroppedIfTheStoryMovesOn() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.tense, index: 2, trigger: .start))
        clock.advance(by: 20)
        director.receive(observation(.cozy, index: 6))
        clock.advance(by: 20)
        director.receive(observation(.cozy, index: 10))
        XCTAssertNotNil(director.nextDeadline)
        clock.advance(by: 20)
        director.receive(observation(.tense, index: 14))
        XCTAssertNil(director.nextDeadline, "tense is back in the lead, nothing waits")
        clock.advance(by: 60)
        XCTAssertNil(director.tick())
        XCTAssertEqual(director.currentBucket, .tense)
    }

    func testBigJumpSwitchesAtOnceButNotRightAfterAChange() {
        let director = MoodDirector(clock: clock)
        director.receive(observation(.cozy, index: 2, trigger: .start))
        XCTAssertEqual(director.currentBucket, .cozy)

        clock.advance(by: 10)
        let early = director.receive(observation(.tense, index: 4, confidence: 0.95))
        XCTAssertNil(early, "10 s after a change is too soon even for a big jump")

        clock.advance(by: 25)
        let decision = director.receive(observation(.tense, index: 8, confidence: 0.95))
        XCTAssertEqual(decision?.bucket, .tense)
        XCTAssertEqual(decision?.reason, .bigJump)
        XCTAssertEqual(decision?.transition, .quick)
    }

    func testConfidentReadingNearTheCurrentMoodIsNotABigJump() {
        let director = MoodDirector(clock: clock)
        director.receive(observation(.calm, index: 2, trigger: .start))
        clock.advance(by: 120)
        // Cozy sits next to Calm on the map: confident, but not a jump.
        XCTAssertNil(director.receive(observation(.cozy, index: 6, confidence: 0.95)))
    }

    func testSeekIgnoresStaleReadingsAndTheNewPlaceDecides() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.hopeful, index: 10, trigger: .start))
        clock.advance(by: 20)
        director.noteSeek(toGlobalSentenceIndex: 800)
        XCTAssertEqual(director.phase, .awaitingSeekReading(target: 800, since: 20))

        clock.advance(by: 1)
        XCTAssertNil(director.receive(observation(.tense, index: 14, confidence: 0.95)))
        XCTAssertEqual(director.ignoredCounts[.beforeSeek], 1)

        clock.advance(by: 1)
        let decision = director.receive(observation(.somber, index: 800, trigger: .seek))
        XCTAssertEqual(decision?.bucket, .somber)
        XCTAssertEqual(decision?.reason, .seek)
        XCTAssertEqual(decision?.transition, .quick)
        XCTAssertTrue(decision?.dwellWaived ?? false, "a seek ignores the dwell")
    }

    func testSeekReadingWaitIsBounded() {
        var config = sharpConfig()
        config.seekReadingTimeout = 30
        let director = MoodDirector(config: config, clock: clock)
        director.receive(observation(.calm, index: 1, trigger: .start))
        director.noteSeek(toGlobalSentenceIndex: nil)
        clock.advance(by: 10)
        XCTAssertNil(director.receive(observation(.tense, index: 40)))
        clock.advance(by: 25)
        let decision = director.receive(observation(.tense, index: 44))
        XCTAssertEqual(decision?.bucket, .tense, "after the timeout any reading decides")
        XCTAssertEqual(decision?.reason, .seek)
    }

    func testChapterStartDecidesWithoutDwellOrConfirmation() {
        let director = MoodDirector(clock: clock)
        director.receive(observation(.tense, index: 2, confidence: 0.8, trigger: .start))
        for step in 1...3 {
            clock.advance(by: 20)
            director.receive(observation(.tense, index: 2 + 4 * step, confidence: 0.8))
        }
        clock.advance(by: 15)
        let decision = director.receive(observation(.cozy, index: 20, confidence: 0.75, trigger: .chapterStart))
        XCTAssertEqual(decision?.bucket, .cozy)
        XCTAssertEqual(decision?.reason, .chapterStart)
        XCTAssertEqual(decision?.transition, .gentle)
    }

    func testChapterStartThatKeepsTheMoodStillWaivesTheDwellUntilTheNextChange() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.tense, index: 2, trigger: .start))
        clock.advance(by: 10)
        XCTAssertNil(director.receive(observation(.tense, index: 6, trigger: .chapterStart)))
        XCTAssertTrue(director.dwellWaived)
        clock.advance(by: 10)
        director.receive(observation(.calm, index: 10))
        clock.advance(by: 20)
        let decision = director.receive(observation(.calm, index: 14))
        XCTAssertEqual(decision?.bucket, .calm, "40 s after the last change, allowed because of the chapter start")
        XCTAssertTrue(decision?.dwellWaived ?? false)
        XCTAssertFalse(director.dwellWaived, "the next change uses the dwell again")
    }

    func testWeakBoundaryReadingIsProvisional() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        let first = director.receive(observation(.somber, index: 2, confidence: 0.6, trigger: .start))
        XCTAssertEqual(first?.bucket, .somber)
        director.noteSeek(toGlobalSentenceIndex: 500)
        clock.advance(by: 5)
        // A very unsure reading at the new place: the neutral prior wins, provisionally.
        let seek = director.receive(observation(.tense, index: 500, confidence: 0.1, trigger: .seek))
        XCTAssertEqual(seek?.bucket, .calm)
        XCTAssertEqual(seek?.provisional, true)
        XCTAssertTrue(director.dwellWaived)
        clock.advance(by: 20)
        director.receive(observation(.tense, index: 504))
        clock.advance(by: 20)
        let decision = director.receive(observation(.tense, index: 508))
        XCTAssertEqual(decision?.bucket, .tense, "a provisional mood does not hold the music for the dwell")
    }

    func testReadingsAheadOfThePlayheadAreRefused() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.notePlayhead(globalSentenceIndex: 10)
        XCTAssertNil(director.receive(observation(.tense, index: 11, confidence: 0.95, trigger: .start)))
        XCTAssertEqual(director.ignoredCounts[.aheadOfPlayhead], 1)
        XCTAssertEqual(director.phase, .awaitingFirstReading, "the refused reading left no trace")
        XCTAssertEqual(director.evidence.total, 0)
        XCTAssertEqual(director.receive(observation(.tense, index: 10, trigger: .start))?.bucket, .tense)
    }

    func testOutOfOrderReadingsAreIgnored() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.calm, index: 20, trigger: .start))
        clock.advance(by: 20)
        XCTAssertNil(director.receive(observation(.tense, index: 12)))
        XCTAssertEqual(director.ignoredCounts[.outOfOrder], 1)
    }

    func testResumeReadingContinuesInsteadOfResetting() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.melancholy, index: 10, trigger: .start))
        clock.advance(by: 300)
        // Pause and resume at the same place: the text side sends .start again.
        XCTAssertNil(director.receive(observation(.playful, index: 12, trigger: .start)), "treated as one regular reading")
        // Resuming far away is a jump, and decides at once.
        clock.advance(by: 5)
        XCTAssertEqual(director.receive(observation(.playful, index: 400, trigger: .start))?.reason, .seek)
    }

    func testPausedTimeDoesNotFadeEvidence() {
        let director = MoodDirector(clock: clock)
        director.receive(observation(.melancholy, index: 2, trigger: .start))
        let before = director.evidence.weight(of: .melancholy)
        director.setNarrationPlaying(false)
        clock.advance(by: 3600)
        director.setNarrationPlaying(true)
        director.receive(observation(.melancholy, index: 6))
        let expectedAdd = reading(.melancholy).evidence(config: director.config)[.melancholy] ?? 0
        XCTAssertEqual(director.evidence.weight(of: .melancholy), before + expectedAdd, accuracy: 1e-9)
    }

    func testEvidenceFadesWithListeningTime() {
        var evidence = MoodEvidence()
        evidence.add([.tense: 1], at: 0, timeConstant: 60)
        evidence.decay(to: 60, timeConstant: 60)
        XCTAssertEqual(evidence.weight(of: .tense), exp(-1), accuracy: 1e-12)
        evidence.decay(to: 30, timeConstant: 60)
        XCTAssertEqual(evidence.weight(of: .tense), exp(-1), accuracy: 1e-12, "time never runs backwards")
    }

    func testPerBucketScoresAreUsedWhenPresent() {
        let config = DirectorConfig()
        let scored = MoodReading(
            bucket: .mysterious,
            valence: 0,
            arousal: 0.5,
            confidence: 0.5,
            scores: [.mysterious: 0.6, .tense: 0.4],
            engineID: "test"
        )
        let shares = scored.evidence(config: config)
        XCTAssertEqual(shares[.mysterious] ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(shares[.tense] ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(shares[.calm] ?? 0, 0, accuracy: 1e-9)
    }

    func testMovingFromTenseToCalmNeverDetoursThroughMysterious() {
        // Mysterious sits between Tense and Calm on the valence/arousal map. Smoothing a
        // single point would drift through it; smoothing per-bucket evidence must not.
        let director = MoodDirector(clock: clock)
        director.receive(observation(.tense, index: 2, trigger: .start))
        var index = 2
        for _ in 0..<15 {
            clock.advance(by: 20)
            index += 4
            director.receive(observation(.tense, index: index))
        }
        var visited: [MoodBucket] = []
        for _ in 0..<30 {
            clock.advance(by: 20)
            index += 4
            if let decision = director.receive(observation(.calm, index: index)) {
                visited.append(decision.bucket)
            }
            if let decision = director.tick() { visited.append(decision.bucket) }
        }
        XCTAssertEqual(visited, [.calm])
    }

    func testNeutralPriorSettlesUnsureTextOnCalm() {
        let director = MoodDirector(clock: clock)
        director.receive(observation(.tense, index: 2, confidence: 0.8, trigger: .start))
        var index = 2
        var decisions: [MoodDecision] = []
        // Mixed, unsure readings that never agree.
        let mixed: [MoodBucket] = [.mysterious, .playful, .somber, .hopeful, .cozy, .melancholy]
        for step in 0..<40 {
            clock.advance(by: 20)
            index += 4
            if let decision = director.receive(observation(mixed[step % mixed.count], index: index, confidence: 0.2)) {
                decisions.append(decision)
            }
            if let decision = director.tick() { decisions.append(decision) }
        }
        XCTAssertEqual(director.currentBucket, .calm)
        XCTAssertLessThanOrEqual(decisions.count, 2)
    }

    func testResetForgetsTheBook() {
        let director = MoodDirector(config: sharpConfig(), clock: clock)
        director.receive(observation(.tense, index: 2, trigger: .start))
        director.notePlayhead(globalSentenceIndex: 2)
        director.reset()
        XCTAssertEqual(director.currentBucket, .calm)
        XCTAssertEqual(director.phase, .awaitingFirstReading)
        XCTAssertNil(director.playheadIndex)
        XCTAssertEqual(director.evidence.total, 0)
        XCTAssertTrue(director.recentDecisions.isEmpty)
    }

    func testConfigDecodesPartialOverrides() throws {
        let json = Data(#"{"minimumDwell": 45, "confirmationReadings": 3}"#.utf8)
        let config = try JSONDecoder().decode(DirectorConfig.self, from: json)
        XCTAssertEqual(config.minimumDwell, 45)
        XCTAssertEqual(config.confirmationReadings, 3)
        XCTAssertEqual(config.evidenceTimeConstant, DirectorConfig().evidenceTimeConstant)
        let roundTrip = try JSONDecoder().decode(DirectorConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(roundTrip, config)
    }
}
