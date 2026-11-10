import XCTest
import LofiScoreCore
@testable import LofiDirector

/// The music panel's "Wrong mood" button: the listener overrides the director.
final class ListenerOverrideTests: XCTestCase {
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

    private func opened(on bucket: MoodBucket, source: ReadingSource = .track) -> MoodDirector {
        let director = MoodDirector(clock: clock)
        clock.advance(to: 2)
        XCTAssertEqual(director.receive(observation(bucket, index: 2, trigger: .start, source: source))?.bucket, bucket)
        return director
    }

    func testOverrideChangesAtOnceWithAQuickCrossfade() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        let decision = director.listenerOverride(to: .mysterious)
        XCTAssertEqual(decision?.bucket, .mysterious)
        XCTAssertEqual(decision?.previous, .tense)
        XCTAssertEqual(decision?.reason, .listener)
        XCTAssertEqual(decision?.transition, .quick)
        XCTAssertEqual(director.currentBucket, .mysterious)
        XCTAssertEqual(director.rejectedBucket, .tense)
        XCTAssertNil(director.listenerOverride(to: .mysterious), "already playing")
    }

    func testTrackNamingTheRejectedMoodIsNotFollowed() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        var index = 2
        // The track keeps saying tense, well past every dwell: the music stays calm.
        while clock.now < 400 {
            clock.advance(by: 4)
            index += 1
            XCTAssertNil(director.receive(observation(.tense, index: index)))
            XCTAssertNil(director.tick())
        }
        XCTAssertEqual(director.currentBucket, .calm)
        XCTAssertNil(director.nextDeadline)
    }

    func testTheRejectionEndsWhenTheTextNamesAThirdMood() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        clock.advance(to: 100)
        XCTAssertEqual(director.receive(observation(.cozy, index: 20))?.bucket, .cozy, "the story moved on")
        XCTAssertNil(director.rejectedBucket)
        clock.advance(to: 200)
        XCTAssertEqual(director.receive(observation(.tense, index: 40))?.bucket, .tense, "tense can come back later")
    }

    func testTheTextAgreeingWithTheListenerKeepsTheRejection() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        clock.advance(to: 100)
        XCTAssertNil(director.receive(observation(.calm, index: 20)))
        XCTAssertEqual(director.rejectedBucket, .tense)
    }

    func testAChapterStartOrASeekEndsTheRejection() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        clock.advance(to: 100)
        XCTAssertEqual(director.receive(observation(.tense, index: 30, trigger: .chapterStart))?.bucket, .tense)
        XCTAssertNil(director.rejectedBucket)

        director.listenerOverride(to: .calm)
        director.noteSeek(toGlobalSentenceIndex: 500)
        XCTAssertEqual(director.receive(observation(.tense, index: 500, trigger: .seek))?.bucket, .tense)
        XCTAssertNil(director.rejectedBucket)
    }

    func testTheOverrideHoldsForTheDwell() {
        let director = opened(on: .tense, source: .live)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        // Live readings for a third mood: the first one ends the rejection, but the dwell
        // keeps the listener's choice for a minute.
        var index = 2
        var decisions: [MoodDecision] = []
        while clock.now < 60 {
            clock.advance(by: 5)
            index += 1
            if let decision = director.receive(observation(.playful, index: index, source: .live)) { decisions.append(decision) }
        }
        XCTAssertTrue(decisions.isEmpty, "nothing within 60 s of the listener's change")
        clock.advance(to: 75)
        index += 1
        let later = director.receive(observation(.playful, index: index, source: .live)) ?? director.tick()
        XCTAssertEqual(later?.bucket, .playful)
    }

    func testLiveEvidenceForTheRejectedMoodCannotWin() {
        let director = opened(on: .tense, source: .live)
        clock.advance(to: 10)
        director.listenerOverride(to: .calm)
        var index = 2
        while clock.now < 300 {
            clock.advance(by: 5)
            index += 1
            XCTAssertNil(director.receive(observation(.tense, index: index, confidence: 0.95, source: .live)))
            XCTAssertNil(director.tick())
        }
        XCTAssertEqual(director.currentBucket, .calm)
        XCTAssertEqual(director.snapshot.shares[.tense] ?? 0, 0, accuracy: 1e-9)
    }

    func testPickingRightAfterAGuessKeepsTheFirstRejection() {
        let director = opened(on: .tense)
        clock.advance(to: 10)
        director.listenerOverride(to: .mysterious)
        clock.advance(to: 20)
        director.listenerOverride(to: .melancholy)
        XCTAssertEqual(director.rejectedBucket, .tense, "the guess was replaced, the miss is still tense")
        clock.advance(to: 30)
        director.listenerOverride(to: .tense)
        XCTAssertEqual(director.rejectedBucket, .melancholy, "picking tense back means the guess was the wrong one")
        clock.advance(to: 400)
        director.listenerOverride(to: .calm)
        XCTAssertEqual(director.rejectedBucket, .tense, "minutes later it is a new miss")
    }

    func testNextGuessFollowsTheEvidence() {
        let director = MoodDirector(clock: clock)
        clock.advance(to: 2)
        director.receive(observation(.tense, index: 2, trigger: .start, source: .live))
        clock.advance(to: 22)
        director.receive(observation(.mysterious, index: 6, confidence: 0.5, source: .live))
        XCTAssertEqual(director.nextGuess(excluding: [.tense]), .mysterious)
        XCTAssertEqual(director.nextGuess(excluding: [.tense], hasTracks: { $0 != .mysterious }) == .mysterious, false)
        XCTAssertNotNil(director.nextGuess(excluding: Set(MoodBucket.allCases).subtracting([.calm])))
    }
}
