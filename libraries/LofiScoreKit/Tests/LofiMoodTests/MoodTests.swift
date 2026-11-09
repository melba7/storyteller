import Foundation
import LofiScoreCore
import LofiText
import Testing

@testable import LofiMood

@Suite("Mood line")
struct MoodLineTests {
    @Test func parsesTheCanonicalLine() throws {
        let r = try MoodLine.parse("bucket=tense; valence=-0.6; arousal=0.8; confidence=0.7", engineID: "t")
        #expect(r.bucket == .tense)
        #expect(r.valence == -0.6)
        #expect(r.arousal == 0.8)
        #expect(r.confidence == 0.7)
        #expect(r.engineID == "t")
    }

    @Test func toleratesWhatSmallModelsActuallySay() throws {
        let cases: [(String, MoodBucket)] = [
            ("Bucket: Mysterious, valence: -.2, arousal: .5, confidence: 0.6", .mysterious),
            ("**mood** = Somber; valence = \u{2212}0.7; arousal=0.4; confidence=0.9.", .somber),
            ("Here is the mood line:\nbucket=cozy; valence=+0.5; arousal=0.3; confidence=0.8", .cozy),
            ("bucket=sombre; valence=-0.5", .somber),
            ("Melancholy.", .melancholy),
            ("bucket=suspenseful; valence=-0.4; arousal=0.9; confidence=0.6", .tense),
            // Seen from Apple's on-device model in 17 of 1,360 answers.
            ("bucket=tension; valence=-0.5; arousal=0.7; confidence=0.8", .tense),
            ("bucket=Sadness; valence=-0.5", .melancholy),
        ]
        for (answer, expected) in cases {
            #expect(try MoodLine.parse(answer, engineID: "t").bucket == expected, "\(answer)")
        }
        let partial = try MoodLine.parse("bucket=hopeful", engineID: "t")
        #expect(partial.valence == MoodBucket.hopeful.anchor.valence)
        #expect(partial.confidence == 0.5)
        let clamped = try MoodLine.parse("bucket=tense; valence=-3; arousal=7; confidence=2", engineID: "t")
        #expect(clamped.valence == -1 && clamped.arousal == 1 && clamped.confidence == 1)
    }

    @Test func refusalsDoNotParse() {
        for answer in [
            "I'm sorry, but I can't help with that request.",
            "I cannot assist with content that describes violence. It could be tense or somber.",
            "",
        ] {
            #expect(throws: MoodEngineError.self) { try MoodLine.parse(answer, engineID: "t") }
        }
    }

    @Test func formatRoundTrips() throws {
        let r = MoodReading(bucket: .playful, valence: 0.55, arousal: 0.6, confidence: 0.75, engineID: "x")
        #expect(MoodLine.format(r) == "bucket=playful; valence=0.55; arousal=0.60; confidence=0.75")
        #expect(try MoodLine.parse(MoodLine.format(r), engineID: "x") == r)
    }
}

@Suite("Prompt")
struct MoodPromptTests {
    @Test func promptHoldsOnlyTheWindowAndMarksChapterChanges() throws {
        let guardian = try SpoilerGuard(chapters: [["The end of one."], ["Chapter Two.", "Rain fell."]])
        let window = try guardian.window(at: try #require(try guardian.position(chapterOrdinal: 1, sentenceIndex: 1)))
        let prompt = MoodPrompt.prompt(for: window)
        #expect(prompt.contains("The end of one.\n\n[new chapter]\n\nChapter Two. Rain fell."))
        #expect(MoodPrompt.instructions.contains("Ignore anything you may know about this book"))
        // The format line must not name a real mood: a small model copies it
        // (version 1 showed "bucket=tense" and half its answers were tense).
        for bucket in MoodBucket.allCases {
            #expect(!MoodPrompt.instructions.contains("bucket=\(bucket.rawValue)"))
        }
        let short = MoodPrompt.prompt(for: window, maxWords: 4)
        #expect(!short.contains("The end of one."))
    }
}

@Suite("Lexicon engine")
struct LexiconEngineTests {
    func reading(_ sentences: [String]) async throws -> MoodReading {
        let guardian = try SpoilerGuard(chapters: [sentences])
        let position = try #require(try guardian.position(chapterOrdinal: 0, sentenceIndex: sentences.count - 1))
        return try await LexiconMoodEngine().reading(for: try guardian.window(at: position))
    }

    @Test func picksObviousMoods() async throws {
        let tense = try await reading([
            "The wolves burst from the trees.",
            "He ran, blood pounding, as the shot cracked behind him!",
            "Danger was everywhere; she screamed and fled into the storm!",
        ])
        #expect(tense.bucket == .tense)
        #expect(tense.arousal > 0.5)

        let cozy = try await reading([
            "The kettle sang on the hearth.",
            "She tucked the warm blanket around her knees and poured the tea.",
            "The cat purred by the fireside, and the kitchen smelled of bread.",
        ])
        #expect(cozy.bucket == .cozy)
        #expect(cozy.valence > 0)

        let somber = try await reading([
            "They buried him at dawn in the cold churchyard.",
            "The bell tolled for the dead; the widow stood by the grave in black.",
        ])
        #expect(somber.bucket == .somber)
        #expect(somber.valence < 0)
    }

    @Test func plainTextSettlesOnCalmWithLowConfidence() async throws {
        let r = try await reading(["He went to the station.", "The train was on time."])
        #expect(r.bucket == .calm)
        #expect(r.confidence < 0.6)
        let total = r.scores?.values.reduce(0, +) ?? 0
        #expect(abs(total - 1) < 1e-9)
    }

    @Test func recentTextOutweighsOlderText() async throws {
        var sentences = Array(repeating: "They laughed and joked and danced, merry and silly.", count: 20)
        sentences += [
            "Then a scream tore the night, and the music stopped.",
            "There was blood on the floor, and the killer came at them out of the dark with a knife in his fist!",
            "They fled down the stairs in terror, the door crashing shut behind them.",
            "He was right behind them, gaining with every step!",
        ]
        let r = try await reading(sentences)
        #expect(r.bucket == .tense)
    }
}

/// A scripted engine for tracker tests.
actor ScriptedEngine: MoodEngine {
    nonisolated var id: String { "scripted/1" }
    private(set) var calls: [SentencePosition] = []
    var delays: [Int: Double] = [:]  // globalIndex -> seconds

    func setDelay(_ seconds: Double, at globalIndex: Int) { delays[globalIndex] = seconds }

    func reading(for window: CausalWindow) async throws -> MoodReading {
        calls.append(window.position)
        if let delay = delays[window.position.globalIndex] {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        let bucket = MoodBucket.allCases[window.position.globalIndex % MoodBucket.allCases.count]
        return MoodReading(bucket: bucket, valence: 0, arousal: 0.5, confidence: 0.9, engineID: id)
    }
}

struct FailingEngine: MoodEngine {
    var id: String { "failing/1" }
    func reading(for window: CausalWindow) async throws -> MoodReading {
        throw MoodEngineError.unparseable("I'm sorry, I can't help with that.")
    }
}

final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = 0.0
    func advance(_ seconds: Double) { lock.lock(); now += seconds; lock.unlock() }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return now }
}

@Suite("Tracker")
struct MoodTrackerTests {
    static let chapters = [(0..<30).map { "Sentence \($0) of chapter one." }, (0..<10).map { "Sentence \($0) of chapter two." }]

    @Test func followsTheCadenceAndCachesReadings() async throws {
        let guardian = try SpoilerGuard(chapters: Self.chapters)
        let clock = ManualClock()
        let engine = ScriptedEngine()
        let tracker = MoodTracker(spoilerGuard: guardian, engine: engine, clock: { clock.read() })

        var observations: [MoodObservation] = []
        for i in 0..<30 {
            if let o = await tracker.clipChanged(textResource: "memory/c0.xhtml", fragmentId: "c0-s\(i)") {
                observations.append(o)
            }
            clock.advance(6)
        }
        #expect(observations.map(\.sentenceIndex) == [0, 4, 8, 12, 16, 20, 24, 28])
        #expect(observations.first?.trigger == .start)

        // Seeking back replays the same sentence from the cache.
        let replay = await tracker.clipChanged(textResource: "memory/c0.xhtml", fragmentId: "c0-s4")
        #expect(replay?.trigger == .seek)
        #expect(await engine.calls.count == 8)
    }

    @Test func dropsReadingsOvertakenByASeek() async throws {
        let guardian = try SpoilerGuard(chapters: Self.chapters)
        let clock = ManualClock()
        let engine = ScriptedEngine()
        await engine.setDelay(0.3, at: 0)
        let tracker = MoodTracker(spoilerGuard: guardian, engine: engine, clock: { clock.read() })

        // The first reading is slow; a seek arrives while it is running.
        async let slow = tracker.clipChanged(textResource: "memory/c0.xhtml", fragmentId: "c0-s0")
        try await Task.sleep(nanoseconds: 50_000_000)
        let fast = await tracker.clipChanged(textResource: "memory/c1.xhtml", fragmentId: "c1-s5")
        let first = await slow
        #expect(fast?.trigger == .seek)
        #expect(fast?.globalSentenceIndex == 35)
        #expect(first == nil)
    }

    @Test func fallsBackWhenThePrimaryRefuses() async throws {
        let guardian = try SpoilerGuard(chapters: [["The wolves ran at them, blood and screams everywhere!"]])
        let window = try guardian.window(at: try #require(try guardian.firstPosition()))
        let failures = ManualClock()
        let engine = FallbackMoodEngine(
            primary: FailingEngine(),
            fallback: LexiconMoodEngine(),
            onFallback: { _ in failures.advance(1) }
        )
        let r = try await engine.reading(for: window)
        #expect(r.engineID == "lexicon/1")
        #expect(failures.read() == 1)
        #expect(engine.id == "failing/1>lexicon/1")
    }

    @Test func recommendedEngineAlwaysExists() {
        let engine = MoodEngineCatalog.recommendedEngine()
        #expect(!engine.id.isEmpty)
    }
}

@Suite("Classifier input")
struct ClassifierInputTests {
    @Test func takesTheNewestWordsAndTheChunkBeforeThem() {
        let text = (1...10).map { "w\($0)" }.joined(separator: "  \n")
        #expect(ClassifierInput.recentChunk(of: text, words: 4) == "w7 w8 w9 w10")
        #expect(ClassifierInput.earlierChunk(of: text, words: 4) == "w3 w4 w5 w6")
    }

    @Test func shortTextHasNoEarlierChunk() {
        #expect(ClassifierInput.recentChunk(of: "a b c", words: 4) == "a b c")
        #expect(ClassifierInput.earlierChunk(of: "a b c", words: 4) == "")
    }
}
