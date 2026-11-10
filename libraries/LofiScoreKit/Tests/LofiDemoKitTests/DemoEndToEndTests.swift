import XCTest
import LofiAudio
import LofiDirector
import LofiScoreCore
@testable import LofiDemoKit

/// The whole music side running together on a manual clock: the demo story, the scripted
/// mood source, the director and the player, with a silent backend.
final class DemoEndToEndTests: XCTestCase {
    private struct Stack {
        let scheduler: ManualScheduler
        let backend: FakeAudioBackend
        let player: LofiScorePlayer
        let narrator: StoryNarrator
    }

    private var decisions: [(decision: MoodDecision, narratorIndex: Int)] = []

    private func makeStack(noise: Double, seed: UInt64 = 3) -> Stack {
        let scheduler = ManualScheduler()
        let backend = FakeAudioBackend(clock: scheduler)
        backend.defaultDuration = 40
        let tracks = MoodBucket.allCases.flatMap { bucket in
            (1...3).map { n in
                LibraryTrack(id: "\(bucket.rawValue)-\(n)", file: "\(bucket.rawValue)/\(bucket.rawValue)-\(n).wav",
                             bucket: bucket, bpm: 80, duration: 40, loudness: -16)
            }
        }
        var config = ScoreConfig()
        config.director = .demo
        let player = LofiScorePlayer(
            library: MusicLibrary(root: URL(fileURLWithPath: "/music"), tracks: tracks),
            backend: backend,
            scheduler: scheduler,
            config: config,
            rotationSeed: seed
        )
        let narrator = StoryNarrator(
            story: .greenLantern,
            player: player,
            scheduler: scheduler,
            moodSource: ScriptedMoodSource(noise: noise, seed: seed)
        )
        player.onDecision = { [unowned self, unowned narrator] decision in
            decisions.append((decision, narrator.index))
        }
        return Stack(scheduler: scheduler, backend: backend, player: player, narrator: narrator)
    }

    private func musicMood(_ stack: Stack) -> MoodBucket? {
        var mood: MoodBucket?
        stack.player.snapshot { mood = $0.musicMood }
        return mood
    }

    private func runToEnd(_ stack: Stack, limit: TimeInterval = 900) {
        var elapsed = 0.0
        while !stack.narrator.isFinished, elapsed < limit {
            stack.scheduler.advance(by: 0.5)
            elapsed += 0.5
        }
    }

    func testStoryStructure() {
        let story = DemoStory.greenLantern
        XCTAssertEqual(story.chapters.count, 4)
        XCTAssertEqual(Set(story.sentences.map(\.mood)), Set(MoodBucket.allCases), "the story visits every mood")
        XCTAssertEqual(story.sentences.map(\.globalIndex), Array(0..<story.sentences.count))
        for chapter in story.chapters {
            XCTAssertEqual(story.sentences[chapter.firstIndex].indexInChapter, 0)
        }
    }

    func testMusicFollowsTheStoryWithoutSpoilers() {
        let stack = makeStack(noise: 0)
        stack.narrator.play()
        runToEnd(stack)
        XCTAssertTrue(stack.narrator.isFinished)

        let story = DemoStory.greenLantern
        for (decision, index) in decisions {
            let heardSoFar = Set(story.sentences[0...index].map(\.mood))
            XCTAssertTrue(heardSoFar.contains(decision.bucket),
                          "\(decision.bucket) chosen at sentence \(index) before the story got there")
            if let reading = decision.globalSentenceIndex {
                XCTAssertLessThanOrEqual(reading, index)
            }
        }
        let visited = Set(decisions.map(\.decision.bucket))
        XCTAssertGreaterThanOrEqual(visited.count, 6, "visited \(visited)")
        XCTAssertLessThanOrEqual(decisions.count, 16, "no flapping")
        XCTAssertTrue([.calm, .cozy].contains(musicMood(stack)), "ends in the closing mood")
        for (decision, index) in decisions {
            print("timeline: sentence \(index) [\(story.sentences[index].mood)] -> \(decision)")
        }
    }

    func testNoisyReadingsStayCalm() {
        let stack = makeStack(noise: 0.3, seed: 11)
        stack.narrator.play()
        runToEnd(stack)
        XCTAssertLessThanOrEqual(decisions.count, 18)
        // Even with noise, nothing may come from text the narrator has not reached.
        for (decision, index) in decisions {
            if let reading = decision.globalSentenceIndex {
                XCTAssertLessThanOrEqual(reading, index)
            }
        }
    }

    func testSeekMovesTheMusicToTheNewPlaceQuickly() {
        let stack = makeStack(noise: 0)
        stack.narrator.play()
        stack.scheduler.advance(by: 30)
        let story = DemoStory.greenLantern
        let somber = story.sentences.first { $0.mood == .somber }!.globalIndex
        decisions.removeAll()
        stack.narrator.seek(to: somber + 5)
        stack.scheduler.advance(by: 6)
        XCTAssertEqual(decisions.first?.decision.reason, .seek)
        XCTAssertEqual(decisions.first?.decision.bucket, .somber)
        XCTAssertEqual(musicMood(stack), .somber)
    }

    func testPauseSleepAndClose() {
        let stack = makeStack(noise: 0)
        stack.narrator.play()
        stack.scheduler.advance(by: 10)
        XCTAssertTrue(stack.backend.isPlaying(.a) || stack.backend.isPlaying(.b))

        stack.narrator.sleep(after: 5)
        stack.scheduler.advance(by: 6.5)
        XCTAssertFalse(stack.narrator.isPlaying)
        XCTAssertFalse(stack.backend.isPlaying(.a) || stack.backend.isPlaying(.b))

        let index = stack.narrator.index
        stack.narrator.play()
        stack.scheduler.advance(by: 3)
        XCTAssertTrue(stack.backend.isPlaying(.a) || stack.backend.isPlaying(.b))
        XCTAssertGreaterThanOrEqual(stack.narrator.index, index)

        stack.narrator.closeBook()
        stack.scheduler.advance(by: 2)
        XCTAssertFalse(stack.backend.isPlaying(.a) || stack.backend.isPlaying(.b))
        var snapshot: PlayerSnapshot?
        stack.player.snapshot { snapshot = $0 }
        XCTAssertNil(snapshot?.bookID)

        stack.narrator.play()
        stack.scheduler.advance(by: 3)
        XCTAssertTrue(stack.narrator.isBookOpen)
        XCTAssertTrue(stack.backend.isPlaying(.a) || stack.backend.isPlaying(.b))
    }

    func testReadingsNeverLookAhead() {
        var source = ScriptedMoodSource(windowSentences: 8, noise: 0, seed: 1)
        let story = DemoStory.greenLantern
        // At the last calm sentence, the cozy paragraph that follows must not count.
        let lastCalm = story.sentences.last { $0.chapter == 0 && $0.mood == .calm }!.globalIndex
        let reading = source.observation(at: lastCalm, trigger: .cadence, in: story)
        XCTAssertEqual(reading.reading.bucket, .calm)
        XCTAssertEqual(reading.globalSentenceIndex, lastCalm)
        // A chapter-start reading looks only at the new chapter.
        let chapterTwo = story.chapters[1].firstIndex
        let start = source.observation(at: chapterTwo + 2, trigger: .chapterStart, in: story)
        XCTAssertEqual(start.reading.bucket, .hopeful)
        XCTAssertEqual(start.chapterOrdinal, 1)
        XCTAssertEqual(start.sentenceIndex, 2)
    }

    func testRateChangesNeverTouchTheMusic() {
        let stack = makeStack(noise: 0)
        stack.narrator.play()
        stack.scheduler.advance(by: 10)
        let calls = stack.backend.calls.count
        stack.narrator.settings.rate = 2
        stack.scheduler.advance(by: 0.1)
        // Only gain updates may happen; nothing reloads, restarts or retimes a deck.
        XCTAssertEqual(stack.backend.calls.count, calls)
    }
}
