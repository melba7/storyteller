#if os(macOS) || os(Linux)
import Foundation
import LofiScoreCore
import LofiText
import Testing

@testable import LofiMood

/// One stand-in `claude` script, written once: it saves its arguments and
/// stdin next to how it was called, then prints that folder's output.json and
/// exits with its status. Each test calls it through a symlink in its own
/// folder. Writing a fresh script per test and running it at once can fail
/// on Linux with "Text file busy" when a parallel test forks while the file is
/// still open for writing, which turned into a retry and a pause now and then.
let sharedFakeClaude: String = {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fake-claude-shared-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = """
        #!/bin/sh
        dir="$(dirname "$0")"
        for a in "$@"; do printf '%s\\n' "$a"; done > "$dir/args.txt"
        cat > "$dir/stdin.txt"
        printf '%s' "${ANTHROPIC_API_KEY:-unset}" > "$dir/key.txt"
        pwd > "$dir/pwd.txt"
        cat "$dir/output.json"
        exit "$(cat "$dir/status.txt")"
        """
    let executable = folder.appendingPathComponent("claude")
    try! script.write(to: executable, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable.path
}()

/// A stand-in `claude` that prints `output` and exits with `status`, so the
/// transport runs end to end without Claude Code.
func fakeClaude(output: String, status: Int32 = 0) throws -> (executable: String, folder: URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fake-claude-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try output.write(to: folder.appendingPathComponent("output.json"), atomically: true, encoding: .utf8)
    try "\(status)".write(to: folder.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    let executable = folder.appendingPathComponent("claude")
    try FileManager.default.createSymbolicLink(atPath: executable.path, withDestinationPath: sharedFakeClaude)
    return (executable.path, folder)
}

@Suite("Claude Code transport", .serialized)
struct ClaudeCodeTransportTests {
    let guardian: SpoilerGuard

    init() throws {
        guardian = try SpoilerGuard(chapters: [[
            "The rain had stopped by evening.",
            "Somewhere below, a door slammed and boots ran on the stairs.",
            "She held her breath.",
        ]])
    }

    @Test func turnsTheEngineRequestIntoAClaudeCodeRun() throws {
        let engine = ClaudeMoodEngine(apiKey: "unused", configuration: .init(model: "claude-sonnet-5-5", effort: "low"))
        let w = try window(guardian, 0, 2)
        let call = try ClaudeCodeTransport.call(for: engine.body(for: w))
        #expect(call.model == "claude-sonnet-5-5")
        #expect(call.prompt == ClaudeMoodPrompt.message(for: w, maxWords: engine.configuration.maxWords))
        let args = call.arguments
        #expect(args.first == "-p")
        #expect(args.contains("--no-session-persistence"))
        #expect(!args.contains("--bare"), "bare mode never uses the subscription login")
        #expect(args.contains("--strict-mcp-config"), "no connectors' tools in the context")
        #expect(args.contains("--disable-slash-commands"))
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        #expect(value("--tools") == "")
        #expect(value("--model") == "claude-sonnet-5-5")
        #expect(value("--output-format") == "json")
        #expect(value("--effort") == "low")
        // The schema goes at the end of the system prompt, not to --json-schema,
        // which would cost a second model turn per request.
        #expect(value("--json-schema") == nil)
        #expect(call.expectsJSON)
        let system = try #require(value("--system-prompt"))
        #expect(system.hasPrefix(ClaudeMoodPrompt.system + "\n\n" + ClaudeCodeTransport.schemaInstruction))
        let schema = String(system.dropFirst(ClaudeMoodPrompt.system.count + 2 + ClaudeCodeTransport.schemaInstruction.count))
        let decoded = try #require(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        #expect((decoded["required"] as? [String])?.contains("mood") == true)

        let asTool = try ClaudeCodeTransport.call(for: engine.body(for: w), schemaAsTool: true)
        #expect(asTool.arguments.contains("--json-schema"))
        #expect(!asTool.expectsJSON)
        let toolSystem = asTool.arguments.firstIndex(of: "--system-prompt").map { asTool.arguments[$0 + 1] }
        #expect(toolSystem == ClaudeMoodPrompt.system)
    }

    @Test func readsAJSONAnswerFromTheReplyText() async throws {
        let fake = try fakeClaude(output: #"""
            {"type":"result","subtype":"success","is_error":false,"num_turns":1,
             "result":"Here it is:\n```json\n{\"about\": \"a door {slams}\", \"mood\": \"tense\", \"valence\": -0.5, \"arousal\": 0.7, \"confidence\": 0.8}\n```",
             "usage":{"input_tokens":900,"output_tokens":40}}
            """#)
        defer { try? FileManager.default.removeItem(at: fake.folder) }
        let engine = ClaudeMoodEngine(apiKey: "subscription", transport: ClaudeCodeTransport(executable: fake.executable))
        let reading = try await engine.reading(for: try window(guardian, 0, 2))
        #expect(reading.bucket == .tense)
        #expect(reading.confidence == 0.8)
        let args = try String(contentsOf: fake.folder.appendingPathComponent("args.txt"), encoding: .utf8)
        #expect(!args.contains("--json-schema"))
    }

    @Test func aReplyWithoutJSONIsRetried() {
        let output = Data(#"{"type":"result","is_error":false,"result":"Tense, I think.","usage":{}}"#.utf8)
        let (_, status) = ClaudeCodeTransport.response(fromCLI: output, exitStatus: 0, requestedModel: "claude-opus-5-5", expectsJSON: true)
        #expect(status == 500)
        let (_, plain) = ClaudeCodeTransport.response(fromCLI: output, exitStatus: 0, requestedModel: "claude-opus-5-5")
        #expect(plain == 200)
    }

    @Test func findsTheFirstWholeJSONObject() {
        #expect(ClaudeCodeTransport.jsonObjectText(in: #"x {"a": "}{", "b": {"c": 1}} y {"d": 2}"#) == #"{"a": "}{", "b": {"c": 1}}"#)
        #expect(ClaudeCodeTransport.jsonObjectText(in: #"{broken {"ok": "\"q\""}"#) == #"{"ok": "\"q\""}"#)
        #expect(ClaudeCodeTransport.jsonObjectText(in: "no object here") == nil)
    }

    @Test func readsAStructuredAnswerEndToEnd() async throws {
        let fake = try fakeClaude(output: """
            {"type":"result","subtype":"success","is_error":false,"duration_ms":2100,"result":"",
             "structured_output":{"mood":"tense","valence":-0.6,"arousal":0.8,"confidence":0.85},
             "usage":{"input_tokens":900,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},
             "modelUsage":{"claude-opus-5-5":{"inputTokens":900}},"total_cost_usd":0.01}
            """)
        defer { try? FileManager.default.removeItem(at: fake.folder) }
        let work = fake.folder.appendingPathComponent("work", isDirectory: true)
        let usage = ClaudeUsage()
        let engine = ClaudeMoodEngine(
            apiKey: "subscription", usage: usage,
            transport: ClaudeCodeTransport(executable: fake.executable, workingDirectory: work)
        )
        let reading = try await engine.reading(for: try window(guardian, 0, 2))
        #expect(reading.bucket == .tense)
        #expect(reading.confidence == 0.85)
        #expect(usage.totals.responses == 1)
        #expect(usage.totals.inputTokens == 900)
        #expect(usage.totals.otherModel == 0)

        let stdin = try String(contentsOf: fake.folder.appendingPathComponent("stdin.txt"), encoding: .utf8)
        #expect(stdin.contains("She held her breath."))
        let ran = try String(contentsOf: fake.folder.appendingPathComponent("pwd.txt"), encoding: .utf8)
        #expect(ran.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/work"))
    }

    @Test func neverPassesAnAPIKeyToClaudeCode() async throws {
        setenv("ANTHROPIC_API_KEY", "sk-test-should-not-pass", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let fake = try fakeClaude(output: """
            {"type":"result","is_error":false,"structured_output":{"mood":"calm","valence":0.2,"arousal":0.1,"confidence":0.7},"usage":{}}
            """)
        defer { try? FileManager.default.removeItem(at: fake.folder) }
        let engine = ClaudeMoodEngine(apiKey: "subscription", transport: ClaudeCodeTransport(executable: fake.executable))
        _ = try await engine.reading(for: try window(guardian, 0, 0))
        let key = try String(contentsOf: fake.folder.appendingPathComponent("key.txt"), encoding: .utf8)
        #expect(key == "unset")
    }

    @Test func notSignedInStopsWithoutRetrying() async throws {
        let fake = try fakeClaude(output: """
            {"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","usage":{"input_tokens":0}}
            """, status: 1)
        defer { try? FileManager.default.removeItem(at: fake.folder) }
        let pauses = PauseLog()
        let engine = ClaudeMoodEngine(
            apiKey: "subscription",
            transport: ClaudeCodeTransport(executable: fake.executable),
            pause: { pauses.add($0) }
        )
        await #expect(throws: MoodEngineError.self) {
            _ = try await engine.reading(for: try window(guardian, 0, 2))
        }
        #expect(pauses.seconds.isEmpty)
    }

    @Test func promptThreeAsksForTheMomentAndTheOtherMoodsThatFit() async throws {
        let transport = ScriptedTransport([.init(status: 200, body: messageJSON(
            #"{"about":"boots on the stairs, someone is coming","also":["mysterious","tense"],"mood":"tense","valence":-0.5,"arousal":0.8,"confidence":0.7}"#
        ))])
        let engine = ClaudeMoodEngine(apiKey: "k", configuration: .init(prompt: 3), transport: transport)
        #expect(engine.id.hasSuffix("/p3"))
        let reading = try await engine.reading(for: try window(guardian, 0, 2))
        #expect(reading.bucket == .tense)
        let scores = try #require(reading.scores)
        #expect(Set(scores.keys) == [.tense, .mysterious], "the best mood is not repeated as an alternative")
        #expect(scores[.tense]! > scores[.mysterious]!)

        let sent = try #require(transport.requests.first?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        let system = try #require((body["system"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(system.contains("In `also`"))
        let schema = try #require(((body["output_config"] as? [String: Any])?["format"] as? [String: Any])?["schema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties.keys.sorted().first == "about", "about must sort first so it is written before the mood")
        #expect(ClaudeMoodEngine(apiKey: "k", configuration: .init(prompt: 9)).configuration.prompt == ClaudeMoodPrompt.version)
    }

    @Test func mapsErrorsToStatuses() {
        #expect(ClaudeCodeTransport.status(for: "Not logged in · Please run /login") == 401)
        #expect(ClaudeCodeTransport.status(for: "Claude AI usage limit reached|1794249600") == 429)
        #expect(ClaudeCodeTransport.status(for: "API Error: 529 Overloaded") == 529)
        #expect(ClaudeCodeTransport.status(for: "something else") == 500)
        let (_, status) = ClaudeCodeTransport.response(fromCLI: Data("garbage".utf8), exitStatus: 2, requestedModel: "claude-opus-5-5")
        #expect(status == 500)
    }

    @Test func findsClaudeOutsideThePath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)", isDirectory: true)
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let path = bin.appendingPathComponent("claude").path
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(try ClaudeCodeTransport.resolve("claude", environment: ["HOME": home.path, "PATH": "/nonexistent"]) == path)
        #expect(throws: ClaudeCodeError.self) {
            _ = try ClaudeCodeTransport.resolve("claude-missing", environment: ["HOME": home.path, "PATH": "/nonexistent"])
        }
    }
}
#endif
