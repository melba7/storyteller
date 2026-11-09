import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LofiScoreCore
import LofiText
import Testing

@testable import LofiMood

// MARK: - Helpers

/// Answers requests from a script, and remembers them.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    private func take(_ request: URLRequest) -> Reply {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return replies.isEmpty ? Reply(status: 500, body: "{}") : replies.removeFirst()
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = take(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

final class PauseLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var seconds: [Double] = []
    func add(_ s: Double) {
        lock.lock()
        seconds.append(s)
        lock.unlock()
    }
}

func messageJSON(_ answer: String, stopReason: String = "end_turn", model: String = "claude-opus-5-5") -> String {
    let escaped = answer.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return """
        {"id":"msg_1","type":"message","role":"assistant","model":"\(model)",
         "content":[{"type":"thinking","thinking":"","signature":"x"},{"type":"text","text":"\(escaped)"}],
         "stop_reason":"\(stopReason)","stop_details":null,
         "usage":{"input_tokens":812,"output_tokens":95,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
        """
}

func sampleBook(chapters: Int = 3, sentences: Int = 30) -> [[String]] {
    (0..<chapters).map { c in
        (0..<sentences).map { s in "In chapter \(c) the walker passes stone number \(s) on the road." }
    }
}

/// Returns a reading that names the window's own position, so tests can check
/// which entry a playback reading came from.
struct PositionEchoEngine: MoodEngine {
    var id: String { "echo/1" }
    func reading(for window: CausalWindow) async throws -> MoodReading {
        let p = window.position
        let bucket = MoodBucket.allCases[(p.chapterOrdinal + p.sentenceIndex) % MoodBucket.allCases.count]
        return MoodReading(bucket: bucket, valence: 0, arousal: 0.3, confidence: 0.9, engineID: "echo@\(p.chapterOrdinal):\(p.sentenceIndex)")
    }
}

func echoedPosition(_ reading: MoodReading) -> (Int, Int)? {
    guard reading.engineID.hasPrefix("echo@") else { return nil }
    let parts = reading.engineID.dropFirst(5).split(separator: ":").compactMap { Int($0) }
    return parts.count == 2 ? (parts[0], parts[1]) : nil
}

func window(_ guardian: SpoilerGuard, _ chapter: Int, _ sentence: Int) throws -> CausalWindow {
    let position = try guardian.position(chapterOrdinal: chapter, sentenceIndex: sentence)
    return try guardian.window(at: try #require(position))
}

// MARK: - Claude engine

@Suite("Claude engine")
struct ClaudeMoodEngineTests {
    let guardian: SpoilerGuard

    init() throws {
        guardian = try SpoilerGuard(chapters: [[
            "The rain had stopped by evening.",
            "Somewhere below, a door slammed and boots ran on the stairs.",
            "She held her breath.",
        ]])
    }

    @Test func sendsOneWindowWithTheGuidelinesAndASchema() async throws {
        let transport = ScriptedTransport([.init(status: 200, body: messageJSON(#"{"mood":"tense","valence":-0.6,"arousal":0.8,"confidence":0.7}"#))])
        let usage = ClaudeUsage()
        let engine = ClaudeMoodEngine(apiKey: " sk-test \n", usage: usage, transport: transport)
        let reading = try await engine.reading(for: try window(guardian, 0, 1))

        #expect(reading.bucket == .tense)
        #expect(reading.valence == -0.6 && reading.arousal == 0.8 && reading.confidence == 0.7)
        #expect(reading.engineID == "claude.opus-5-5/p1")
        #expect(engine.id == "claude.opus-5-5/p1")

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let httpBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["thinking"] == nil)
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        let mood = try #require((schema["properties"] as? [String: Any])?["mood"] as? [String: Any])
        #expect(mood["enum"] as? [String] == MoodBucket.allCases.map(\.rawValue))
        #expect(schema["additionalProperties"] as? Bool == false)

        let system = try #require((body["system"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(system.contains("Judge only the words in the passage"))
        let content = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(content.contains("boots ran on the stairs"))
        #expect(!content.contains("held her breath"), "the window at sentence 1 must not hold sentence 2")

        #expect(usage.totals.responses == 1)
        #expect(usage.totals.inputTokens == 812 && usage.totals.outputTokens == 95)
    }

    @Test func haikuGetsNoServerFallback() throws {
        let engine = ClaudeMoodEngine(apiKey: "k", configuration: .init(model: "claude-haiku-5-5"), transport: ScriptedTransport([]))
        let request = try engine.urlRequest(for: try window(guardian, 0, 2))
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let httpBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["fallbacks"] == nil)
        #expect(engine.id == "claude.haiku-5-5/p1")
    }

    @Test func retriesRateLimitsThenSucceeds() async throws {
        let transport = ScriptedTransport([
            .init(status: 429, body: #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#, headers: ["Retry-After": "3"]),
            .init(status: 529, body: #"{"type":"error","error":{"type":"overloaded_error","message":"busy"}}"#),
            .init(status: 200, body: messageJSON(#"{"mood":"calm","valence":0.1,"arousal":0.2,"confidence":0.8}"#)),
        ])
        let pauses = PauseLog()
        let usage = ClaudeUsage()
        let engine = ClaudeMoodEngine(apiKey: "k", usage: usage, transport: transport, pause: { pauses.add($0) })
        let reading = try await engine.reading(for: try window(guardian, 0, 0))
        #expect(reading.bucket == .calm)
        #expect(transport.requestCount == 3)
        #expect(pauses.seconds == [3, 4], "honours retry-after, then backs off")
        #expect(usage.totals.retries == 2)
    }

    @Test func givesUpAfterMaxRetries() async throws {
        let transport = ScriptedTransport(Array(repeating: .init(status: 529, body: "{}"), count: 10))
        let engine = ClaudeMoodEngine(apiKey: "k", configuration: .init(maxRetries: 2), transport: transport, pause: { _ in })
        await #expect(throws: MoodEngineError.self) { try await engine.reading(for: try window(guardian, 0, 0)) }
        #expect(transport.requestCount == 3)
    }

    @Test func doesNotRetryBadKeysOrBadRequests() async throws {
        for (status, kind) in [(401, "unavailable"), (400, "generation")] {
            let transport = ScriptedTransport([.init(status: status, body: #"{"type":"error","error":{"type":"x","message":"no"}}"#)])
            let engine = ClaudeMoodEngine(apiKey: "k", transport: transport, pause: { _ in })
            do {
                _ = try await engine.reading(for: try window(guardian, 0, 0))
                Issue.record("HTTP \(status) should throw")
            } catch let error as MoodEngineError {
                switch (error, kind) {
                case (.unavailable, "unavailable"), (.generationFailed, "generation"): break
                default: Issue.record("HTTP \(status) threw \(error)")
                }
            }
            #expect(transport.requestCount == 1)
        }
    }

    @Test func refusalsAndCutOffsThrowSoTheFallbackRuns() async throws {
        for stop in ["refusal", "max_tokens"] {
            let transport = ScriptedTransport([.init(status: 200, body: messageJSON("", stopReason: stop))])
            let claude = ClaudeMoodEngine(apiKey: "k", transport: transport)
            await #expect(throws: MoodEngineError.self) { try await claude.reading(for: try window(guardian, 0, 1)) }

            let again = ScriptedTransport([.init(status: 200, body: messageJSON("", stopReason: stop))])
            let engine = FallbackMoodEngine(primary: ClaudeMoodEngine(apiKey: "k", transport: again), fallback: LexiconMoodEngine())
            let reading = try await engine.reading(for: try window(guardian, 0, 1))
            #expect(reading.engineID.hasPrefix("lexicon"))
        }
    }

    @Test func missingKeyIsUnavailableWithoutARequest() async throws {
        let transport = ScriptedTransport([])
        let engine = ClaudeMoodEngine(apiKey: "  ", transport: transport)
        await #expect(throws: MoodEngineError.self) { try await engine.reading(for: try window(guardian, 0, 0)) }
        #expect(transport.requestCount == 0)
    }

    @Test func backoffDoublesAndCaps() {
        #expect(ClaudeMoodEngine.backoff(attempt: 1, retryAfter: nil) == 2)
        #expect(ClaudeMoodEngine.backoff(attempt: 3, retryAfter: nil) == 8)
        #expect(ClaudeMoodEngine.backoff(attempt: 9, retryAfter: nil) == 60)
        #expect(ClaudeMoodEngine.backoff(attempt: 1, retryAfter: "7") == 7)
        #expect(ClaudeMoodEngine.backoff(attempt: 1, retryAfter: "soon") == 2)
    }
}

// MARK: - Mood tracks

@Suite("Mood track")
struct MoodTrackTests {
    @Test func plansAnEntryEveryFewHundredWordsAndOnePerChapter() throws {
        let guardian = try SpoilerGuard(chapters: sampleBook(chapters: 3, sentences: 30) + [["A very short chapter."]])
        let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 50))
        let points = try builder.scoringPositions()
        // Each sentence has 12 words, so after the chapter-start entry at
        // sentence 2 there is one entry every 5 sentences (60 words >= 50).
        let firstChapter = points.filter { $0.chapterOrdinal == 0 }.map(\.sentenceIndex)
        #expect(firstChapter == [2, 7, 12, 17, 22, 27])
        #expect(Set(points.map(\.chapterOrdinal)) == [0, 1, 2, 3])
        #expect(points.last?.chapterOrdinal == 3 && points.last?.sentenceIndex == 0, "a one-sentence chapter still gets an entry")
        #expect(points == points.sorted(), "positions come in reading order")
    }

    @Test func buildsFromCausalWindowsAndResumes() async throws {
        let guardian = try SpoilerGuard(chapters: sampleBook())
        let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 50))
        let store = MoodTrackStore(MoodTrack(engineID: "echo/1", bookID: "sample", wordsBetweenEntries: 50))

        let first = try await builder.build(into: store, engine: PositionEchoEngine(), concurrency: 3)
        #expect(first.planned > 0 && first.scored == first.planned && first.failed == 0)
        for entry in store.snapshot.entries {
            // Each entry was scored from the window at its own position.
            let echoed = try #require(echoedPosition(entry.reading))
            #expect(echoed == (entry.chapterOrdinal, entry.sentenceIndex))
        }

        let second = try await builder.build(into: store, engine: PositionEchoEngine())
        #expect(second.scored == 0 && second.alreadyScored == first.planned)

        let decoded = try MoodTrack.decode(try store.snapshot.encoded())
        #expect(decoded == store.snapshot)
    }

    @Test func playbackNeverUsesAnEntryFromLaterInTheBook() async throws {
        let guardian = try SpoilerGuard(chapters: sampleBook(chapters: 4, sentences: 25))
        let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 40))
        let store = MoodTrackStore(MoodTrack(engineID: "echo/1", bookID: "sample", wordsBetweenEntries: 40))
        _ = try await builder.build(into: store, engine: PositionEchoEngine())
        let engine = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine())

        var fromTrack = 0
        var p = try guardian.firstPosition()
        while let position = p {
            let reading = try await engine.reading(for: try guardian.window(at: position))
            if case let (c, s)? = echoedPosition(reading) {
                fromTrack += 1
                #expect((c, s) <= (position.chapterOrdinal, position.sentenceIndex), "entry \(c):\(s) used at \(position)")
                let expected = try #require(store.entry(atOrBefore: position))
                #expect((c, s) == (expected.chapterOrdinal, expected.sentenceIndex), "the newest entry is used")
            } else {
                // Only before the first entry does the live engine run.
                #expect(position.chapterOrdinal == 0 && position.sentenceIndex < 2)
                #expect(reading.engineID.hasPrefix("lexicon"))
            }
            p = try guardian.position(after: position)
        }
        #expect(fromTrack > 90)
    }

    @Test func fallsBackWhenTheBookTextNoLongerMatches() async throws {
        let original = try SpoilerGuard(chapters: sampleBook())
        let store = MoodTrackStore(MoodTrack(engineID: "echo/1", bookID: "sample", wordsBetweenEntries: 50))
        _ = try await MoodTrackBuilder(spoilerGuard: original, plan: .init(wordsBetweenEntries: 50))
            .build(into: store, engine: PositionEchoEngine())
        let engine = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine())

        // Same book, realigned: the sentences now split differently.
        var realigned = sampleBook()
        realigned[1] = realigned[1].map { $0.replacingOccurrences(of: "on the road.", with: "on the old road.") }
        let changed = try SpoilerGuard(chapters: realigned)

        let unchanged = try await engine.reading(for: try window(changed, 0, 20))
        #expect(echoedPosition(unchanged) != nil, "chapter 0 still matches")
        let stale = try await engine.reading(for: try window(changed, 1, 20))
        #expect(stale.engineID.hasPrefix("lexicon"), "chapter 1 changed, so the track must not be used there")
    }

    @Test func tooOldEntriesAreNotUsed() async throws {
        let guardian = try SpoilerGuard(chapters: sampleBook())
        let store = MoodTrackStore(MoodTrack(engineID: "echo/1", bookID: "sample", wordsBetweenEntries: 50))
        // Score only chapter 0, as if the build were still running.
        _ = try await MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 50))
            .build(into: store, engine: PositionEchoEngine(), chapters: 0...0)
        let engine = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine(), maxLagSentences: 10)

        let nearEnd = try await engine.reading(for: try window(guardian, 0, 29))
        #expect(echoedPosition(nearEnd) != nil)
        let wellPast = try await engine.reading(for: try window(guardian, 1, 15))
        #expect(wellPast.engineID.hasPrefix("lexicon"), "the scored part ends 16+ sentences back")
    }

    @Test func digestIgnoresWhitespaceOnly() {
        #expect(TextDigest.fnv1a64("a  b\nc") == TextDigest.fnv1a64("a b c"))
        #expect(TextDigest.fnv1a64("a b c") != TextDigest.fnv1a64("a b d"))
        #expect(TextDigest.fnv1a64("").count == 16)
    }
}
