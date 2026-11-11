import Foundation
import LofiMood
import LofiScoreCore
import LofiText

/// Engines by name, for `--engine`:
///
///     lexicon                  hand-written cues (runs anywhere)
///     nltagger                 NLTagger sentiment + cues (Apple platforms)
///     fm                       Apple's on-device model, general use case
///     fm-tagging               Apple's on-device model, content-tagging adapter
///     fast:<model>             Create ML classifier (.mlmodel or .mlmodelc)
///     fm+fast:<model>          on-device model, falling back to the classifier
///     embed:<model.json>       Apple's on-device embeddings + a model from `lofi-train embed`
///     lm:<LofiMood-lm-*.json>  a fine-tuned transformer through Core ML (Tools/mac/finetune.sh --convert)
///     recommended[:<model>]    what the app would pick on this machine
///     claude[:<model>]         Claude (default claude-opus-5-5); LOFI_CLAUDE_EFFORT sets the effort,
///                              LOFI_CLAUDE_PROMPT the prompt version (2, or 3 for also-fits).
///                              LOFI_CLAUDE_VIA=api uses the Anthropic API with the key from
///                              ANTHROPIC_API_KEY or the file named by ANTHROPIC_API_KEY_FILE;
///                              LOFI_CLAUDE_VIA=plan runs each request through Claude Code
///                              (`claude -p`) on its signed-in subscription, no key needed
///                              (LOFI_CLAUDE_CODE names the executable if not on PATH;
///                              LOFI_CLAUDE_CODE_ARGS adds arguments to each run).
///                              Unset: the API when a key is set, otherwise the plan.
enum EngineFactory {
    static let names = ["lexicon", "nltagger", "fm", "fm-tagging", "fast:<model>", "fm+fast:<model>", "embed:<model.json>", "lm:<config.json>", "recommended[:<model>]", "claude[:<model>]"]

    /// Token counts for every Claude engine made in this process.
    static let claudeUsage = ClaudeUsage()

    static func make(_ name: String) throws -> any MoodEngine {
        let (base, argument) = split(name)
        switch base {
        case "lexicon":
            return LexiconMoodEngine()
        case "nltagger":
            #if canImport(NaturalLanguage)
            return NLTaggerMoodEngine()
            #else
            throw unavailable(name, "NaturalLanguage is not available on this platform")
            #endif
        case "fm", "fm-tagging":
            return try foundationModels(tagging: base == "fm-tagging")
        case "fast":
            return try classifier(argument, name: name)
        case "embed":
            guard let argument, !argument.isEmpty else { throw unavailable(name, "give the model path, e.g. embed:Models/LofiMood-embed-contextual-1.json") }
            #if canImport(NaturalLanguage)
            let url = URL(fileURLWithPath: argument)
            return try EmbeddingMoodEngine(modelURL: url, version: url.deletingPathExtension().lastPathComponent)
            #else
            throw unavailable(name, "NaturalLanguage is not available on this platform")
            #endif
        case "lm":
            guard let argument, !argument.isEmpty else { throw unavailable(name, "give the settings file, e.g. lm:Models/LofiMood-lm-soft.json") }
            #if canImport(CoreML)
            return try TransformerMoodEngine(configURL: URL(fileURLWithPath: argument))
            #else
            throw unavailable(name, "Core ML is not available on this platform")
            #endif
        case "fm+fast":
            return FallbackMoodEngine(primary: try foundationModels(tagging: false), fallback: try classifier(argument, name: name))
        case "recommended":
            return MoodEngineCatalog.recommendedEngine(classifierModelURL: argument.map { URL(fileURLWithPath: $0) })
        case "claude":
            return try claude(model: argument)
        default:
            throw unavailable(name, "unknown engine; try one of \(names.joined(separator: ", "))")
        }
    }

    /// One line per engine saying whether it can run here.
    static func availabilityReport() -> [String] {
        var lines = ["lexicon: available"]
        #if canImport(NaturalLanguage)
        lines.append("nltagger: available")
        #else
        lines.append("nltagger: unavailable (no NaturalLanguage on this platform)")
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let a = FoundationModelsMoodEngine.availability()
            lines.append("fm: \(a.isAvailable ? "available" : "unavailable (\(a.reason))")")
        } else {
            lines.append("fm: unavailable (needs macOS 26 or iOS 26)")
        }
        #else
        lines.append("fm: unavailable (SDK has no FoundationModels)")
        #endif
        #if canImport(NaturalLanguage) && canImport(CoreML)
        lines.append("fast: available when given a model (fast:<path>)")
        #else
        lines.append("fast: unavailable (no CoreML on this platform)")
        #endif
        switch try? claudeRoute() {
        case .api?:
            lines.append("claude: via the Anthropic API (key found)")
        case .plan(let executable)?:
            #if os(macOS) || os(Linux)
            let found = (try? ClaudeCodeTransport.resolve(executable)) != nil
            lines.append(found ? "claude: via Claude Code on its signed-in plan (\(executable))"
                               : "claude: unavailable (no API key, and Claude Code not found)")
            #else
            lines.append("claude: unavailable (no API key)")
            #endif
        case nil:
            lines.append("claude: unavailable (set ANTHROPIC_API_KEY or ANTHROPIC_API_KEY_FILE, or LOFI_CLAUDE_VIA=plan)")
        }
        lines.append("recommended here: \(MoodEngineCatalog.recommendedEngine().id)")
        return lines
    }

    private static func split(_ name: String) -> (String, String?) {
        guard let colon = name.firstIndex(of: ":") else { return (name, nil) }
        return (String(name[..<colon]), String(name[name.index(after: colon)...]))
    }

    private static func foundationModels(tagging: Bool) throws -> any MoodEngine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let a = FoundationModelsMoodEngine.availability()
            guard a.isAvailable else { throw unavailable("fm", a.reason) }
            return FoundationModelsMoodEngine(variant: tagging ? .contentTagging : .general)
        }
        throw unavailable("fm", "needs macOS 26 or iOS 26")
        #else
        throw unavailable("fm", "this SDK has no FoundationModels")
        #endif
    }

    private static func classifier(_ path: String?, name: String) throws -> any MoodEngine {
        guard let path, !path.isEmpty else { throw unavailable(name, "give the model path, e.g. fast:Models/LofiMood.mlmodel") }
        #if canImport(NaturalLanguage) && canImport(CoreML)
        let url = URL(fileURLWithPath: path)
        let version = url.deletingPathExtension().lastPathComponent
        return try ClassifierMoodEngine(modelURL: url, version: version)
        #else
        throw unavailable(name, "CoreML is not available on this platform")
        #endif
    }

    static func claude(model: String?) throws -> ClaudeMoodEngine {
        var configuration = ClaudeMoodEngine.Configuration()
        if let model, !model.isEmpty {
            configuration.model = model.hasPrefix("claude-") ? model : "claude-" + model
        }
        if let effort = ProcessInfo.processInfo.environment["LOFI_CLAUDE_EFFORT"], !effort.isEmpty {
            configuration.effort = effort
        }
        if let prompt = ProcessInfo.processInfo.environment["LOFI_CLAUDE_PROMPT"].flatMap(Int.init) {
            guard ClaudeMoodPrompt.versions.contains(prompt) else {
                throw unavailable("claude", "LOFI_CLAUDE_PROMPT must be one of \(ClaudeMoodPrompt.versions)")
            }
            configuration.prompt = prompt
        }
        switch try claudeRoute() {
        case .api(let key):
            return ClaudeMoodEngine(apiKey: key, configuration: configuration, usage: claudeUsage)
        case .plan(let executable):
            #if os(macOS) || os(Linux)
            // The key is never sent: the transport ignores headers.
            // LOFI_CLAUDE_CODE_ARGS adds arguments to every run, e.g.
            // "--strict-mcp-config --disable-slash-commands" to keep the
            // account's connectors and skills out of each request.
            let extra = (ProcessInfo.processInfo.environment["LOFI_CLAUDE_CODE_ARGS"] ?? "")
                .split(whereSeparator: \.isWhitespace).map(String.init)
            // LOFI_CLAUDE_CODE_SCHEMA=tool passes the answer's schema as
            // --json-schema (two model turns per request) instead of in the prompt.
            let asTool = ProcessInfo.processInfo.environment["LOFI_CLAUDE_CODE_SCHEMA"] == "tool"
            return ClaudeMoodEngine(apiKey: "subscription", configuration: configuration, usage: claudeUsage,
                                    transport: ClaudeCodeTransport(executable: executable, extraArguments: extra,
                                                                   schemaAsTool: asTool))
            #else
            _ = executable
            throw unavailable("claude", "Claude Code runs only on a Mac")
            #endif
        }
    }

    enum ClaudeRoute {
        case api(String)
        case plan(String)
    }

    /// How `claude` engines reach Claude: LOFI_CLAUDE_VIA=api|plan, or by default
    /// the API when a key is set and the Claude subscription (Claude Code) otherwise.
    static func claudeRoute() throws -> ClaudeRoute {
        let env = ProcessInfo.processInfo.environment
        let executable = env["LOFI_CLAUDE_CODE"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
        switch env["LOFI_CLAUDE_VIA"]?.lowercased() {
        case "api":
            return .api(try apiKey())
        case "plan", "claude-code", "subscription":
            return .plan(executable)
        case nil, "":
            if let key = try? apiKey() { return .api(key) }
            return .plan(executable)
        case let other?:
            throw unavailable("claude", "LOFI_CLAUDE_VIA must be api or plan, not \(other)")
        }
    }

    /// The Anthropic API key from the environment, or from a file it names.
    /// Never printed.
    static func apiKey() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let key = env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        if let path = env["ANTHROPIC_API_KEY_FILE"], !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            guard let key = try? String(contentsOfFile: expanded, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
            else { throw unavailable("claude", "could not read a key from ANTHROPIC_API_KEY_FILE") }
            return key
        }
        throw unavailable("claude", "set ANTHROPIC_API_KEY, or ANTHROPIC_API_KEY_FILE to a file holding the key")
    }

    private static func unavailable(_ name: String, _ reason: String) -> MoodEngineError {
        .unavailable("\(name): \(reason)")
    }
}

/// Wraps an engine and remembers how long each reading took.
final class TimedEngine: MoodEngine, @unchecked Sendable {
    let inner: any MoodEngine
    private let lock = NSLock()
    private var last: Double?

    init(_ inner: any MoodEngine) { self.inner = inner }

    var id: String { inner.id }

    func reading(for window: CausalWindow) async throws -> MoodReading {
        let start = now()
        defer { record((now() - start) * 1000) }
        return try await inner.reading(for: window)
    }

    private func record(_ elapsed: Double) {
        lock.lock(); last = elapsed; lock.unlock()
    }

    /// The latency of the most recent reading, then forgets it (cache hits take none).
    func takeLatency() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let value = last
        last = nil
        return value
    }
}
