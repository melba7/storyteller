import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LofiAtmosphere
import LofiMood
import LofiText

final class ClaudeSceneTests: XCTestCase {
    private func memory() throws -> PlaceMemory {
        let guardian = try SpoilerGuard(chapters: [["One.", "Two.", "Three."]])
        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 0))
        let entry = AtmosphereTrack.Entry(
            position: position, sentence: "One.",
            scene: StoryScene(placeID: "p1", placeName: "the Crown inn", setting: .indoors, layers: [SceneLayer(.fireplace)]),
            world: "a Victorian seaside town"
        )
        return PlaceMemory(entries: [entry])
    }

    func testAnswersMapToKnownAndNewPlaces() throws {
        let memory = try memory()
        let known = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"p1","placeName":"the Crown","setting":"indoors","sounds":[{"sound":"fireplace","level":"faint"},{"sound":"rainIndoors","level":"soft"}],"world":"a Victorian seaside town","cue":"rain lashed the windows","confidence":0.8}
            """, memory: memory)
        XCTAssertEqual(known.place, .known("p1"))
        XCTAssertEqual(known.scene.layers, [SceneLayer(.rainIndoors, .soft), SceneLayer(.fireplace, .faint)])
        XCTAssertEqual(known.scene.cue, "rain lashed the windows")

        let renamed = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"new","placeName":"The Crown Inn","setting":"indoors","sounds":[],"world":"","cue":"","confidence":0.7}
            """, memory: memory)
        XCTAssertEqual(renamed.place, .known("p1"), "a new place with a known place's name is that place")

        let fresh = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"p9","placeName":"the pier","setting":"outdoors","sounds":[{"sound":"seaShore","level":"full"},{"sound":"bagpipes","level":"full"}],"world":"","cue":"","confidence":0.9}
            """, memory: memory)
        XCTAssertEqual(fresh.place, .new("the pier"), "an id the memory does not hold is a new place")
        XCTAssertEqual(fresh.scene.layers, [SceneLayer(.seaShore, .full)], "unknown sounds are dropped")

        let nowhere = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"none","placeName":"","setting":"unclear","sounds":[],"world":"","cue":"","confidence":0.2}
            """, memory: memory)
        XCTAssertEqual(nowhere.place, .none)
        XCTAssertTrue(nowhere.scene.isSilent)

        XCTAssertThrowsError(try ClaudeSceneEngine.answer(fromJSON: "not json", memory: memory))
    }

    func testRequestCarriesOnlyThePassageAndWhatCameBefore() throws {
        let guardian = try SpoilerGuard(chapters: [["It was a dark night.", "Rain lashed the windows of the inn.", "Nobody spoke of what came next."]])
        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 1))
        let window = try guardian.window(at: position)
        let engine = ClaudeSceneEngine(apiKey: "test-key", configuration: .init(model: "claude-sonnet-5-5"))
        let body = engine.body(for: window, memory: try memory())
        let message = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first)?["content"] as? String)
        XCTAssertTrue(message.contains("Rain lashed the windows of the inn."))
        XCTAssertFalse(message.contains("Nobody spoke"), "nothing after the narrated sentence")
        XCTAssertTrue(message.contains("p1 \"the Crown inn\" (indoors): fireplace soft"))
        XCTAssertTrue(message.contains("a Victorian seaside town"))
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertNotNil(output["format"])
        XCTAssertNil(body["temperature"])
        XCTAssertTrue(ClaudeScenePrompt.system.contains("crowd:"))

        let haiku = ClaudeSceneEngine(apiKey: "k", configuration: .init(model: "claude-haiku-5-5"))
        XCTAssertNil(haiku.body(for: window, memory: PlaceMemory())["fallbacks"])
        XCTAssertEqual(engine.id, "claude.sonnet-5-5/a4")
    }

    func testParsesAMessagesResponseAndCountsUsage() async throws {
        let guardian = try SpoilerGuard(chapters: [["The ship rolled in the swell."]])
        let window = try guardian.window(at: try XCTUnwrap(try guardian.firstPosition()))
        let answer = #"{\"place\":\"new\",\"placeName\":\"the Pequod\",\"setting\":\"vehicle\",\"sounds\":[{\"sound\":\"ship\",\"level\":\"full\"},{\"sound\":\"openSea\",\"level\":\"soft\"}],\"world\":\"a whaling voyage\",\"cue\":\"rolled in the swell\",\"confidence\":0.9}"#
        let response = #"{"model":"claude-opus-5-5","content":[{"type":"text","text":"\#(answer)"}],"stop_reason":"end_turn","usage":{"input_tokens":900,"output_tokens":120,"cache_read_input_tokens":2000}}"#
        let usage = SceneUsage()
        let transport = CannedTransport(responses: [(429, "{}"), (200, response)])
        let engine = ClaudeSceneEngine(apiKey: "k", usage: usage, transport: transport, pause: { _ in })
        let result = try await engine.scene(for: window, memory: PlaceMemory())
        XCTAssertEqual(result.place, .new("the Pequod"))
        XCTAssertEqual(result.scene.setting, .vehicle)
        XCTAssertEqual(result.world, "a whaling voyage")
        XCTAssertEqual(usage.totals.responses, 1)
        XCTAssertEqual(usage.totals.retries, 1)
        XCTAssertEqual(usage.totals.cacheReadTokens, 2000)
        let prices = try XCTUnwrap(ScenePrices.forModel("opus-5-5"))
        let expected: Double = (900.0 * 4.0 + 120.0 * 20.0 + 2000.0 * 0.2) / 1_000_000.0
        XCTAssertEqual(prices.dollars(usage.totals), expected, accuracy: 1e-9)
    }
}

final class CannedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { responses.removeFirst() }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
