import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LofiScoreCore
import LofiText

/// Asks Claude (the Anthropic Messages API) for the mood of one causal window.
///
/// Each request holds one window and nothing else: no title, no author, no
/// earlier answers. The window comes from `SpoilerGuard`, so Claude only ever
/// sees text that has already been narrated. The answer is constrained by a JSON
/// schema, so it always names one of the moods unless Claude refuses.
///
/// This engine needs the network and an API key, and costs money per reading,
/// so the app does not call it during playback. `MoodTrackBuilder` uses it to
/// score a book once, ahead of time, and `TrackedMoodEngine` plays the saved
/// track back with the Fast engine covering anything not scored yet.
public struct ClaudeMoodEngine: MoodEngine {
    public struct Configuration: Sendable, Hashable {
        /// The Claude model, e.g. "claude-opus-5-5" or "claude-haiku-5-5".
        public var model: String
        /// `output_config.effort`. Classification needs little thinking.
        public var effort: String
        /// Most recent words of the window to send.
        public var maxWords: Int
        /// Room for thinking plus the short JSON answer.
        public var maxTokens: Int
        /// Re-run a refused request on Anthropic's recommended fallback model
        /// (`fallbacks: "default"`). `nil` turns it on for the models that accept it.
        public var serverFallback: Bool?
        /// Attempts after the first for rate limits, overload, 5xx and network errors.
        public var maxRetries: Int
        public var endpoint: URL
        public var apiVersion: String
        public var timeout: TimeInterval
        /// `ClaudeMoodPrompt` version: 2, or 3 (adds `about` and `also`).
        public var prompt: Int

        public init(
            model: String = "claude-opus-5-5",
            effort: String = "low",
            maxWords: Int = 400,
            maxTokens: Int = 2048,
            serverFallback: Bool? = nil,
            maxRetries: Int = 4,
            endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
            apiVersion: String = "2026-10-21",
            timeout: TimeInterval = 90,
            prompt: Int = ClaudeMoodPrompt.version
        ) {
            self.model = model
            self.effort = effort
            self.maxWords = max(1, maxWords)
            self.maxTokens = max(256, maxTokens)
            self.serverFallback = serverFallback
            self.maxRetries = max(0, maxRetries)
            self.endpoint = endpoint
            self.apiVersion = apiVersion
            self.timeout = timeout
            self.prompt = ClaudeMoodPrompt.versions.contains(prompt) ? prompt : ClaudeMoodPrompt.version
        }

        /// Haiku has no server-side refusal fallback; the other current models do.
        var usesServerFallback: Bool { serverFallback ?? !model.contains("haiku") }
    }

    public let configuration: Configuration
    /// Token counts and retries, shared by every copy of this engine. Optional.
    public let usage: ClaudeUsage?
    private let apiKey: String
    private let transport: any HTTPTransport
    private let pause: @Sendable (Double) async -> Void

    public init(
        apiKey: String,
        configuration: Configuration = Configuration(),
        usage: ClaudeUsage? = nil,
        transport: any HTTPTransport = URLSessionTransport(),
        pause: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configuration = configuration
        self.usage = usage
        self.transport = transport
        self.pause = pause
    }

    public var id: String {
        let model = configuration.model.hasPrefix("claude-") ? String(configuration.model.dropFirst(7)) : configuration.model
        return "claude.\(model)/p\(configuration.prompt)"
    }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        guard !apiKey.isEmpty else { throw MoodEngineError.unavailable("no Anthropic API key") }
        let request = try urlRequest(for: window)

        var attempt = 0
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                guard attempt < configuration.maxRetries else {
                    throw MoodEngineError.generationFailed("network: \(error)")
                }
                attempt += 1
                usage?.recordRetry()
                await pause(Self.backoff(attempt: attempt, retryAfter: nil))
                continue
            }

            switch response.statusCode {
            case 200:
                return try Self.parse(data, engineID: id, requestedModel: configuration.model, usage: usage)
            case 401, 403:
                throw MoodEngineError.unavailable("API key rejected (\(response.statusCode)): \(Self.errorMessage(data))")
            case 408, 409, 429, 500...599:
                guard attempt < configuration.maxRetries else {
                    throw MoodEngineError.generationFailed("HTTP \(response.statusCode) after \(attempt + 1) attempts: \(Self.errorMessage(data))")
                }
                attempt += 1
                usage?.recordRetry()
                await pause(Self.backoff(attempt: attempt, retryAfter: Self.header("retry-after", in: response)))
            default:
                throw MoodEngineError.generationFailed("HTTP \(response.statusCode): \(Self.errorMessage(data))")
            }
        }
    }

    // MARK: - Request

    func urlRequest(for window: CausalWindow) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
        if configuration.usesServerFallback {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(for: window), options: [.sortedKeys])
        return request
    }

    func body(for window: CausalWindow) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "system": [[
                "type": "text",
                "text": ClaudeMoodPrompt.system(version: configuration.prompt),
                // Identical on every request; cached when it is long enough for the model.
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [[
                "role": "user",
                "content": ClaudeMoodPrompt.message(for: window, maxWords: configuration.maxWords),
            ]],
            "output_config": [
                "effort": configuration.effort,
                "format": ["type": "json_schema", "schema": ClaudeMoodPrompt.schema(version: configuration.prompt)],
            ],
        ]
        if configuration.usesServerFallback { body["fallbacks"] = "default" }
        return body
    }

    // MARK: - Response

    static func parse(_ data: Data, engineID: String, requestedModel: String? = nil, usage: ClaudeUsage? = nil) throws -> MoodReading {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let message: MessageResponse
        do {
            message = try decoder.decode(MessageResponse.self, from: data)
        } catch {
            throw MoodEngineError.unparseable(String(decoding: data.prefix(200), as: UTF8.self))
        }
        usage?.record(message, requestedModel: requestedModel)

        switch message.stopReason {
        case "refusal":
            throw MoodEngineError.generationFailed("Claude declined (\(message.stopDetails?.category ?? "no category"))")
        case "max_tokens":
            throw MoodEngineError.generationFailed("answer cut off at max_tokens")
        default:
            break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(text.utf8)),
              let bucket = MoodBucket(rawValue: answer.mood) ?? MoodBucket(lenient: answer.mood)
        else {
            throw MoodEngineError.unparseable(text)
        }
        // Prompt v3's other moods that also fit go into `scores`, after the
        // best mood: 1 for the best and 0.5 for each other, before normalising.
        var scores: [MoodBucket: Double]?
        let also = (answer.also ?? []).compactMap { MoodBucket(rawValue: $0) ?? MoodBucket(lenient: $0) }.filter { $0 != bucket }
        if !also.isEmpty {
            var s: [MoodBucket: Double] = [bucket: 1]
            for other in also.prefix(2) { s[other] = 0.5 }
            scores = s
        }
        return MoodReading(
            bucket: bucket,
            valence: answer.valence,
            arousal: answer.arousal,
            confidence: answer.confidence,
            scores: scores,
            engineID: engineID
        )
    }

    /// Seconds to wait before retry `attempt` (1-based): the server's
    /// `retry-after` when it gives one, otherwise 2, 4, 8, ... seconds capped at 60.
    static func backoff(attempt: Int, retryAfter: String?) -> Double {
        if let retryAfter, let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            return min(seconds, 120)
        }
        return min(60, pow(2, Double(attempt)))
    }

    static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String
            }
        }
        return nil
    }

    static func errorMessage(_ data: Data) -> String {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return "\(body.error.type): \(body.error.message)"
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }

    struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        struct StopDetails: Decodable {
            let category: String?
        }
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreationInputTokens: Int?
        }
        let model: String?
        let content: [Block]
        let stopReason: String?
        let stopDetails: StopDetails?
        let usage: Usage?
    }

    struct Answer: Decodable {
        let about: String?
        let also: [String]?
        let mood: String
        let valence: Double
        let arousal: Double
        let confidence: Double
    }

    struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }
        let error: Detail
    }
}

/// Running totals of what `ClaudeMoodEngine` used, for cost reports.
public final class ClaudeUsage: @unchecked Sendable {
    public struct Totals: Sendable, Hashable, Codable {
        public var responses = 0
        public var inputTokens = 0
        public var outputTokens = 0
        public var cacheReadTokens = 0
        public var cacheWriteTokens = 0
        public var retries = 0
        public var refusals = 0
        /// Responses served by a different model than requested (a server-side fallback).
        public var otherModel = 0
    }

    private let lock = NSLock()
    private var current = Totals()

    public init() {}

    public var totals: Totals {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func record(_ message: ClaudeMoodEngine.MessageResponse, requestedModel: String?) {
        lock.lock()
        defer { lock.unlock() }
        current.responses += 1
        current.inputTokens += message.usage?.inputTokens ?? 0
        current.outputTokens += message.usage?.outputTokens ?? 0
        current.cacheReadTokens += message.usage?.cacheReadInputTokens ?? 0
        current.cacheWriteTokens += message.usage?.cacheCreationInputTokens ?? 0
        if message.stopReason == "refusal" { current.refusals += 1 }
        if let requestedModel, let served = message.model, served != requestedModel { current.otherModel += 1 }
    }

    func recordRetry() {
        lock.lock()
        current.retries += 1
        lock.unlock()
    }
}

/// Sends one HTTP request. A protocol so tests can answer without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
