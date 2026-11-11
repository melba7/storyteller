import XCTest
import LofiScoreCore
@testable import LofiDirector

/// The director with a book's mood track, and with live readings taken every sentence.
final class TrackDirectorTests: XCTestCase {
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
    }

    private func observation(
        _ bucket: MoodBucket,
        index: Int,
        confidence: Double = 0.7,
        trigger: ReadingTrigger = .cadence,
        source: ReadingSource = .track
    ) -> MoodObservation {
        MoodObservation(
            reading: MoodReading(
                bucket: bucket,
                valence: bucket.anchor.valence,
                arousal: bucket.anchor.arousal,
                confidence: confidence,
                engineID: source == .track ? "track" : "live"
            ),
            chapterOrdinal: 0,
            sentenceIndex: index,
            globalSentenceIndex: index,
            trigger: trigger,
            source: source
        )
    }

    /// A director that opened on `bucket` at t = 2 (sentence 2), from the track.
    private func opened(on bucket: MoodBucket) -> MoodDirector {
        let director = MoodDirector(clock: clock)
        clock.advance(to: 2)
        XCTAssertEqual(director.receive(observation(bucket, index: 2, trigger: .start))?.bucket, bucket)
        return director
    }

    // MARK: - Mood track

    func testTrackTurnIsFollowedAtTheSentenceWhereItHappens() {
        let director = opened(on: .mysterious)
        var index = 2
        // The track says mysterious, sentence after sentence: nothing changes.
        while clock.now < 60 {
            clock.advance(by: 4)
            index += 1
            XCTAssertNil(director.receive(observation(.mysterious, index: index)))
        }
        // It turns to cozy at this sentence: the music follows now, not a minute later.
        clock.advance(by: 4)
        index += 1
        let decision = director.receive(observation(.cozy, index: index))
        XCTAssertEqual(decision?.bucket, .cozy)
        XCTAssertEqual(decision?.previous, .mysterious)
        XCTAssertEqual(decision?.reason, .trackTurn)
        XCTAssertEqual(decision?.transition, .gentle)
        XCTAssertEqual(decision?.globalSentenceIndex, index)
        XCTAssertNil(director.nextDeadline)

        // The next sentences agree with the new mood: nothing more happens.
        for _ in 0..<5 {
            clock.advance(by: 4)
            index += 1
            XCTAssertNil(director.receive(observation(.cozy, index: index)))
        }
        XCTAssertEqual(director.currentBucket, .cozy)
    }

    func testTrackTurnSoonAfterAChangeWaitsForTheTrackDwell() {
        let director = opened(on: .mysterious)
        clock.advance(to: 20)
        XCTAssertNil(director.receive(observation(.cozy, index: 6)), "18 s after a change")
        XCTAssertEqual(director.snapshot.pendingBucket, .cozy)
        XCTAssertEqual(director.nextDeadline, 47)
        XCTAssertEqual(director.snapshot.dwellRemaining, 27, accuracy: 1e-9)

        clock.advance(to: 30)
        XCTAssertNil(director.receive(observation(.cozy, index: 8)))
        clock.advance(to: 46)
        XCTAssertNil(director.tick(), "still inside the dwell")
        clock.advance(to: 47)
        let decision = director.tick()
        XCTAssertEqual(decision?.bucket, .cozy)
        XCTAssertEqual(decision?.reason, .dwellElapsed)
        XCTAssertEqual(decision?.globalSentenceIndex, 8, "the latest track reading")
        XCTAssertNil(director.nextDeadline)
    }

    func testHeldTrackTurnIsDroppedWhenTheTrackTurnsBack() {
        let director = opened(on: .mysterious)
        clock.advance(to: 20)
        XCTAssertNil(director.receive(observation(.cozy, index: 6)))
        XCTAssertNotNil(director.nextDeadline)
        clock.advance(to: 30)
        XCTAssertNil(director.receive(observation(.mysterious, index: 8)))
        XCTAssertNil(director.nextDeadline, "nothing waits any more")
        clock.advance(to: 60)
        XCTAssertNil(director.tick())
        XCTAssertEqual(director.currentBucket, .mysterious)
    }

    func testHeldTrackTurnGoesToWhereTheTrackIsWhenTheDwellEnds() {
        let director = opened(on: .mysterious)
        clock.advance(to: 20)
        XCTAssertNil(director.receive(observation(.cozy, index: 6)))
        clock.advance(to: 30)
        XCTAssertNil(director.receive(observation(.hopeful, index: 8)))
        clock.advance(to: 47)
        let decision = director.tick()
        XCTAssertEqual(decision?.bucket, .hopeful)
        XCTAssertEqual(decision?.reason, .dwellElapsed)
    }

    func testConfidentFarTrackTurnIsAQuickBigJump() {
        let director = opened(on: .cozy)
        clock.advance(to: 35)
        // 33 s after the last change: too soon for a regular track turn (45 s),
        // allowed for a big jump (30 s).
        let decision = director.receive(observation(.tense, index: 9, confidence: 0.9))
        XCTAssertEqual(decision?.bucket, .tense)
        XCTAssertEqual(decision?.reason, .bigJump)
        XCTAssertEqual(decision?.transition, .quick)
    }

    func testLiveReadingRightAfterATrackTurnDoesNotPullTheMusicBack() {
        let director = opened(on: .mysterious)
        clock.advance(to: 60)
        XCTAssertEqual(director.receive(observation(.cozy, index: 20))?.reason, .trackTurn)
        // The track ends here; a live engine takes over and still hears a little mystery.
        var index = 20
        for _ in 0..<10 {
            clock.advance(by: 4)
            index += 1
            XCTAssertNil(director.receive(observation(.mysterious, index: index, confidence: 0.4, source: .live)))
        }
        XCTAssertEqual(director.currentBucket, .cozy)
    }

    func testUnsureTrackReadingGoesThroughTheLiveRules() {
        let director = opened(on: .mysterious)
        clock.advance(to: 80)
        XCTAssertNil(
            director.receive(observation(.cozy, index: 20, confidence: 0.2)),
            "below the track's minimum confidence: smoothed and confirmed like a live reading"
        )
        XCTAssertEqual(director.currentBucket, .mysterious)
    }

    func testTrackReadingsAheadOfThePlayheadAreRefused() {
        let director = MoodDirector(clock: clock)
        director.notePlayhead(globalSentenceIndex: 10)
        clock.advance(to: 2)
        director.receive(observation(.mysterious, index: 10, trigger: .start))
        clock.advance(to: 60)
        XCTAssertNil(director.receive(observation(.cozy, index: 11)), "sentence 11 is not being narrated yet")
        XCTAssertEqual(director.ignoredCounts[.aheadOfPlayhead], 1)
        XCTAssertEqual(director.currentBucket, .mysterious)
        director.notePlayhead(globalSentenceIndex: 11)
        XCTAssertEqual(director.receive(observation(.cozy, index: 11))?.reason, .trackTurn)
    }

    // MARK: - Live readings every sentence

    /// Runs a fresh director over a story given as time → mood, with one live reading every
    /// `step` seconds, and returns its decisions. Held changes fire at their deadlines.
    private func runLive(
        every step: TimeInterval,
        until end: TimeInterval,
        config: DirectorConfig = DirectorConfig(),
        confidence: (Int) -> Double = { _ in 0.7 },
        story: (TimeInterval, Int) -> MoodBucket
    ) -> [MoodDecision] {
        let clock = ManualClock()
        let director = MoodDirector(config: config, clock: clock)
        var decisions: [MoodDecision] = []
        var index = 0
        clock.advance(to: 2)
        if let decision = director.receive(observation(story(2, 0), index: 0, trigger: .start, source: .live)) {
            decisions.append(decision)
        }
        var time = 2.0
        while time + step <= end {
            time += step
            if let deadline = director.nextDeadline, deadline < time {
                clock.advance(to: deadline)
                if let decision = director.tick() { decisions.append(decision) }
            }
            clock.advance(to: time)
            index += 1
            let reading = observation(story(time, index), index: index, confidence: confidence(index), source: .live)
            if let decision = director.receive(reading) { decisions.append(decision) }
        }
        return decisions
    }

    func testEverySentenceFollowsASustainedChangeNoFasterThanTheConfirmationAllows() {
        let story: (TimeInterval, Int) -> MoodBucket = { time, _ in time < 200 ? .tense : .cozy }
        let slow = runLive(every: 20, until: 400, story: story)
        let fast = runLive(every: 4, until: 400, story: story)
        XCTAssertEqual(slow.map(\.bucket), [.tense, .cozy])
        XCTAssertEqual(fast.map(\.bucket), [.tense, .cozy])
        let slowDelay = slow[1].time - 200
        let fastDelay = fast[1].time - 200
        XCTAssertGreaterThanOrEqual(fastDelay, 20, "a new mood must lead for the confirmation time")
        // The slow cadence credits its first new reading with the 20 s before it, so it can
        // look a little quicker on text that turns all at once; never by much.
        XCTAssertLessThanOrEqual(fastDelay, slowDelay + 15, "slow \(slowDelay) s, fast \(fastDelay) s")
        XCTAssertLessThanOrEqual(fastDelay, 90)
    }

    func testEverySentenceIgnoresAShortInterlude() {
        // Four sentences (16 s) of comfort inside a tense stretch.
        let fast = runLive(every: 4, until: 400) { time, _ in (200..<216).contains(time) ? .cozy : .tense }
        XCTAssertEqual(fast.map(\.bucket), [.tense])
    }

    func testEverySentenceKeepsTheMinimumDwell() {
        // Two minutes of comfort, then tense again. With a long dwell the music follows the
        // comfort, then must hold it for the whole dwell even though tense wins long before.
        var config = DirectorConfig()
        config.minimumDwell = 180
        let fast = runLive(every: 4, until: 700, config: config) { time, _ in (200..<320).contains(time) ? .cozy : .tense }
        XCTAssertEqual(fast.map(\.bucket), [.tense, .cozy, .tense])
        XCTAssertEqual(fast[2].time - fast[1].time, 180, accuracy: 1e-6, "held until the dwell ended: \(fast)")
        for (earlier, later) in zip(fast, fast.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.time - earlier.time, 180 - 1e-9, "\(later)")
        }
    }

    func testOneConfidentOddSentenceDoesNotJumpTheMusic() {
        // Cozy text with one sentence that reads, very confidently, as tense.
        let fast = runLive(every: 4, until: 300, confidence: { $0 == 40 ? 0.95 : 0.7 }) { _, index in
            index == 40 ? .tense : .cozy
        }
        XCTAssertEqual(fast.map(\.bucket), [.cozy])
    }

    func testConfidentFarTextJumpsWithinTwoSentences() {
        // Cozy, then from sentence 40 on, unmistakably tense.
        let fast = runLive(every: 4, until: 300, confidence: { $0 >= 40 ? 0.9 : 0.7 }) { _, index in
            index >= 40 ? .tense : .cozy
        }
        XCTAssertEqual(fast.map(\.bucket), [.cozy, .tense])
        XCTAssertEqual(fast.last?.reason, .bigJump)
        XCTAssertEqual(fast.last?.globalSentenceIndex, 41)
    }

    func testOneReadingStillJumpsAtTheSlowCadence() {
        let slow = runLive(every: 20, until: 300, confidence: { $0 >= 8 ? 0.9 : 0.7 }) { _, index in
            index >= 8 ? .tense : .cozy
        }
        XCTAssertEqual(slow.map(\.bucket), [.cozy, .tense])
        XCTAssertEqual(slow.last?.reason, .bigJump)
        XCTAssertEqual(slow.last?.globalSentenceIndex, 8)
    }

    func testNoisyEverySentenceReadingsChangeTheMusicNoMoreThanSlowOnes() {
        // One sentence in four reads as some other mood; the story never changes.
        let others = MoodBucket.allCases.filter { $0 != .melancholy }
        let story: (TimeInterval, Int) -> MoodBucket = { _, index in
            var state = UInt64(index) &* 6364136223846793005 &+ 1442695040888963407
            state ^= state >> 29
            return index > 0 && state % 4 == 0 ? others[Int(state >> 8) % others.count] : .melancholy
        }
        let slow = runLive(every: 20, until: 1800, story: story)
        let fast = runLive(every: 4, until: 1800, story: story)
        XCTAssertEqual(fast.map(\.bucket), [.melancholy], "\(fast)")
        XCTAssertLessThanOrEqual(fast.count, max(1, slow.count))
    }
}
