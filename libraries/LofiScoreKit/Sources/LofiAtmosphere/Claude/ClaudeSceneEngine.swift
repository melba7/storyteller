import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LofiMood
import LofiText

/// Asks Claude (the Anthropic Messages API) for the scene at the end of one causal window.
///
/// Each request holds the window, the book's world note and the places met so far, all
/// from text already narrated, and nothing else: no title, no author. The answer is held
/// to a JSON schema. Like the mood engine, this costs money per request, so the app never
/// calls it: ``AtmosphereTrackBuilder`` scores a book once on the Mac.
public struct ClaudeSceneEngine: SceneEngine {
    public struct Configuration: Sendable, Hashable {
        public var model: String
        /// `output_config.effort`. Picking a place and a few sounds needs little thinking.
        public var effort: String
        public var maxWords: Int
        public var maxTokens: Int
        /// Re-run a refused request on Anthropic's recommended fallback model; nil turns it
        /// on for the models that accept it (not Haiku).
        public var serverFallback: Bool?
        public var maxRetries: Int
        public var endpoint: URL
        public var apiVersion: String
        public var timeout: TimeInterval
        /// Variants offered in every request of a run (the starter set and other books'),
        /// sent once in the cached system prompt. The builder offers the same ones through
        /// the memory, which is what answers are checked against.
        public var sharedVariants: [SoundVariant]

        public init(
            model: String = "claude-opus-5-5",
            effort: String = "low",
            maxWords: Int = 400,
            maxTokens: Int = 4096,
            serverFallback: Bool? = nil,
            maxRetries: Int = 4,
            endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
            apiVersion: String = "2026-10-21",
            timeout: TimeInterval = 120,
            sharedVariants: [SoundVariant] = []
        ) {
            self.model = model
            self.effort = effort
            self.maxWords = max(1, maxWords)
            self.maxTokens = max(512, maxTokens)
            self.serverFallback = serverFallback
            self.maxRetries = max(0, maxRetries)
            self.endpoint = endpoint
            self.apiVersion = apiVersion
            self.timeout = timeout
            self.sharedVariants = sharedVariants
        }

        var usesServerFallback: Bool { serverFallback ?? !model.contains("haiku") }
    }

    public let configuration: Configuration
    public let usage: SceneUsage?
    private let apiKey: String
    private let transport: any HTTPTransport
    private let pause: @Sendable (Double) async -> Void

    public init(
        apiKey: String,
        configuration: Configuration = Configuration(),
        usage: SceneUsage? = nil,
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
        return "claude.\(model)/a\(ClaudeScenePrompt.version)"
    }

    public func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
        guard window.wordCount > 0 else { throw SceneEngineError.emptyWindow }
        guard !apiKey.isEmpty else { throw SceneEngineError.unavailable("no Anthropic API key") }
        let request = try urlRequest(for: window, memory: memory)

        var attempt = 0
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                guard attempt < configuration.maxRetries else {
                    throw SceneEngineError.generationFailed("network: \(error)")
                }
                attempt += 1
                usage?.recordRetry()
                await pause(Self.backoff(attempt: attempt, retryAfter: nil))
                continue
            }
            switch response.statusCode {
            case 200:
                return try Self.parse(data, memory: memory, requestedModel: configuration.model, usage: usage)
            case 401, 403:
                throw SceneEngineError.unavailable("API key rejected (\(response.statusCode)): \(Self.errorMessage(data))")
            case 408, 409, 429, 500...599:
                guard attempt < configuration.maxRetries else {
                    throw SceneEngineError.generationFailed("HTTP \(response.statusCode) after \(attempt + 1) attempts: \(Self.errorMessage(data))")
                }
                attempt += 1
                usage?.recordRetry()
                await pause(Self.backoff(attempt: attempt, retryAfter: Self.header("retry-after", in: response)))
            default:
                throw SceneEngineError.generationFailed("HTTP \(response.statusCode): \(Self.errorMessage(data))")
            }
        }
    }

    // MARK: - Request

    func urlRequest(for window: CausalWindow, memory: PlaceMemory) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
        if configuration.usesServerFallback {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(for: window, memory: memory), options: [.sortedKeys])
        return request
    }

    func body(for window: CausalWindow, memory: PlaceMemory) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "system": [[
                "type": "text",
                "text": ClaudeScenePrompt.system(sharedVariants: configuration.sharedVariants),
                // The same on every request of a run; cached once it is long enough.
                "cache_control": ["type": "ephemeral"],
            ] as [String: Any]],
            "messages": [[
                "role": "user",
                "content": ClaudeScenePrompt.message(
                    for: window, memory: memory, maxWords: configuration.maxWords, sharedVariants: configuration.sharedVariants
                ),
            ]],
            "output_config": [
                "effort": configuration.effort,
                "format": ["type": "json_schema", "schema": ClaudeScenePrompt.schema] as [String: Any],
            ] as [String: Any],
        ]
        if configuration.usesServerFallback { body["fallbacks"] = "default" }
        return body
    }

    // MARK: - Response

    static func parse(_ data: Data, memory: PlaceMemory, requestedModel: String? = nil, usage: SceneUsage? = nil) throws -> SceneAnswer {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let message: MessageResponse
        do {
            message = try decoder.decode(MessageResponse.self, from: data)
        } catch {
            throw SceneEngineError.unparseable(String(decoding: data.prefix(200), as: UTF8.self))
        }
        usage?.record(
            input: message.usage?.inputTokens ?? 0,
            output: message.usage?.outputTokens ?? 0,
            cacheRead: message.usage?.cacheReadInputTokens ?? 0,
            cacheWrite: message.usage?.cacheCreationInputTokens ?? 0,
            refused: message.stopReason == "refusal",
            otherModel: requestedModel.map { requested in message.model.map { $0 != requested } ?? false } ?? false
        )
        switch message.stopReason {
        case "refusal":
            throw SceneEngineError.generationFailed("Claude declined (\(message.stopDetails?.category ?? "no category"))")
        case "max_tokens":
            throw SceneEngineError.generationFailed("answer cut off at max_tokens")
        default:
            break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        return try answer(fromJSON: text, memory: memory)
    }

    /// New sounds kept from one answer; the prompt asks for one at most.
    static let maxNewVariantsPerAnswer = 1

    /// Turns the JSON answer into a ``SceneAnswer``. Unknown sounds are dropped, an id the
    /// memory does not hold is treated as a new place, and "new" with the name of a known
    /// place is that place. A variant must be one the memory offers or one this answer
    /// adds; any other is dropped and the plain sound kept.
    public static func answer(fromJSON text: String, memory: PlaceMemory) throws -> SceneAnswer {
        guard let raw = try? JSONDecoder().decode(Answer.self, from: Data(text.utf8)) else {
            throw SceneEngineError.unparseable(text)
        }
        var available = Dictionary(
            (SoundCatalog.starterVariants + memory.variants).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var added: [SoundVariant] = []
        for item in raw.newSounds ?? [] where added.count < maxNewVariantsPerAnswer {
            guard let id = SoundVariant.normalizedID(item.id), available[id] == nil,
                  let of = AmbientSound(rawValue: item.of) ?? AmbientSound(lenient: item.of)
            else { continue }
            let about = String(item.about.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            let search = String(item.search.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !about.isEmpty || !search.isEmpty else { continue }
            let variant = SoundVariant(id: id, of: of, about: about.isEmpty ? search : about, search: search.isEmpty ? about : search)
            available[id] = variant
            added.append(variant)
        }
        var used = Set<String>()
        let layers = raw.sounds.compactMap { item -> SceneLayer? in
            let family = item.sound.split(separator: ".", maxSplits: 1).first.map(String.init) ?? item.sound
            guard let sound = AmbientSound(rawValue: family) ?? AmbientSound(lenient: family),
                  let level = AmbientLevel(lenient: item.level)
            else { return nil }
            // "crowd.cafe" in either field is the kind cafe of crowd.
            var variantName = item.variant ?? ""
            if variantName.isEmpty, let dot = item.sound.firstIndex(of: ".") {
                variantName = String(item.sound[item.sound.index(after: dot)...])
            } else if let dot = variantName.lastIndex(of: ".") {
                variantName = String(variantName[variantName.index(after: dot)...])
            }
            if let id = SoundVariant.normalizedID(variantName), let variant = available[id] {
                used.insert(id)
                // The variant decides which sound it stands in for.
                return SceneLayer(variant.of, level, variant: id)
            }
            return SceneLayer(sound, level)
        }
        let name = raw.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = raw.place.trimmingCharacters(in: .whitespacesAndNewlines)
        let place: SceneAnswer.Place
        switch id.lowercased() {
        case "none", "":
            place = layers.isEmpty ? .none : (name.isEmpty ? .none : .new(name))
        case "new":
            if let known = memory.place(named: name) {
                place = .known(known.id)
            } else {
                place = name.isEmpty ? .none : .new(name)
            }
        default:
            if memory.places[id] != nil {
                place = .known(id)
            } else if let known = memory.place(named: name) {
                place = .known(known.id)
            } else {
                place = name.isEmpty ? .none : .new(name)
            }
        }
        let cue = raw.cue.trimmingCharacters(in: .whitespacesAndNewlines)
        let world = raw.world.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = (raw.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scene = StoryScene(
            placeID: nil,
            placeName: name.isEmpty ? nil : name,
            setting: StoryScene.Setting(rawValue: raw.setting.lowercased()) ?? .unclear,
            layers: layers,
            confidence: raw.confidence,
            cue: cue.isEmpty ? nil : String(cue.prefix(120)),
            // A moment or a transition needs somewhere to happen.
            moment: place == .none ? nil : raw.moment.flatMap { StoryScene.Moment(rawValue: $0.lowercased()) },
            state: state.isEmpty || state.lowercased() == "none" ? nil : String(state.prefix(80)),
            transition: place == .none ? nil : raw.transition.flatMap { SceneTransition(rawValue: $0) ?? SceneTransition(lenient: $0) }
        )
        var oneShot: OneShotMention?
        if let item = raw.oneShot, let sound = OneShotSound(rawValue: item.sound) ?? OneShotSound(lenient: item.sound) {
            let quote = item.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            // Without the words it cannot be placed on a sentence.
            if !quote.isEmpty { oneShot = OneShotMention(sound: sound, quote: String(quote.prefix(120))) }
        }
        return SceneAnswer(
            place: place, scene: scene, world: world.isEmpty ? nil : String(world.prefix(160)),
            // A new sound the scene does not use is not worth fetching.
            newVariants: added.filter { used.contains($0.id) },
            oneShot: oneShot
        )
    }

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
        struct Sound: Decodable {
            let sound: String
            let level: String
            let variant: String?
        }
        struct NewSound: Decodable {
            let id: String
            let of: String
            let about: String
            let search: String
        }
        let place: String
        let placeName: String
        let setting: String
        let state: String?
        let sounds: [Sound]
        struct OneShot: Decodable {
            let sound: String
            let quote: String
        }
        let newSounds: [NewSound]?
        let moment: String?
        /// Optional, so answers in the older shape (and the eval set) still read.
        let transition: String?
        let oneShot: OneShot?
        let world: String
        let cue: String
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

/// Running token totals for a scoring run, for cost reports and the spending cap.
public final class SceneUsage: @unchecked Sendable {
    public struct Totals: Sendable, Hashable, Codable {
        public var responses = 0
        public var inputTokens = 0
        public var outputTokens = 0
        public var cacheReadTokens = 0
        public var cacheWriteTokens = 0
        public var retries = 0
        public var refusals = 0
        public var otherModel = 0

        public init() {}
    }

    private let lock = NSLock()
    private var current = Totals()

    public init() {}

    public var totals: Totals {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func record(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, refused: Bool, otherModel: Bool) {
        lock.lock()
        defer { lock.unlock() }
        current.responses += 1
        current.inputTokens += input
        current.outputTokens += output
        current.cacheReadTokens += cacheRead
        current.cacheWriteTokens += cacheWrite
        if refused { current.refusals += 1 }
        if otherModel { current.otherModel += 1 }
    }

    func recordRetry() {
        lock.lock()
        current.retries += 1
        lock.unlock()
    }
}

/// List prices per million tokens, for estimates and the spending cap.
public struct ScenePrices: Sendable, Hashable {
    public var model: String
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double

    /// Checked against Anthropic's price list on 9 Nov 2026.
    public static let known: [ScenePrices] = [
        ScenePrices(model: "claude-opus-5-5", input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5),
        ScenePrices(model: "claude-sonnet-5-5", input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.5),
        ScenePrices(model: "claude-haiku-5-5", input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
    ]

    public static func forModel(_ model: String) -> ScenePrices? {
        let full = model.hasPrefix("claude-") ? model : "claude-" + model
        return known.first { $0.model == full }
    }

    public func dollars(_ totals: SceneUsage.Totals) -> Double {
        (Double(totals.inputTokens) * input + Double(totals.outputTokens) * output
            + Double(totals.cacheReadTokens) * cacheRead + Double(totals.cacheWriteTokens) * cacheWrite) / 1_000_000
    }

    public func dollars(input inputTokens: Int, output outputTokens: Int) -> Double {
        (Double(inputTokens) * input + Double(outputTokens) * output) / 1_000_000
    }
}
