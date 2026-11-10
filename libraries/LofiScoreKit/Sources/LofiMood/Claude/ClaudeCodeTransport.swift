#if os(macOS) || os(Linux)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends `ClaudeMoodEngine`'s Messages API requests through Claude Code's
/// scripted mode (`claude -p`) instead of the API, so they run on the Claude
/// subscription (Pro or Max) that Claude Code is signed in with, and need no
/// API key. For the Mac scripts only: the phone never calls Claude.
///
/// Each request becomes one `claude -p` run from an empty folder, with the
/// request's system prompt replacing Claude Code's own, every tool turned off,
/// the answer constrained by the request's JSON schema (`--json-schema`), and
/// nothing saved to Claude Code's session history. `ANTHROPIC_API_KEY` is
/// removed from the child's environment, because Claude Code would otherwise
/// use it in place of the subscription. Claude Code's JSON result is turned
/// back into a Messages API response (or an API-style error with a matching
/// status), so the engine's parsing, retries and usage counts work unchanged.
///
/// Claude Code must be signed in once on the machine (run `claude` and log in,
/// or set `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`). Not `--bare`:
/// bare mode never reads the subscription login.
public struct ClaudeCodeTransport: HTTPTransport {
    /// `claude`, or a path to it. A bare name is looked up on PATH and then in
    /// the usual install folders, since scripts often run without the login PATH.
    public var executable: String
    /// Where each run starts: an empty folder, so no project settings,
    /// CLAUDE.md or hooks are picked up from the current directory.
    public var workingDirectory: URL
    /// Appended to every run, e.g. `["--setting-sources", "user"]`.
    public var extraArguments: [String]
    /// A run is stopped after this many seconds, or the request's timeout if longer.
    public var minimumTimeout: TimeInterval
    /// How a request's JSON schema reaches Claude. `false` (the default) puts
    /// it in the system prompt and reads the JSON object from the answer's
    /// text. `true` passes `--json-schema`, which makes Claude Code take two
    /// model turns per request (a StructuredOutput tool call, then a closing
    /// message), so the prompt is sent and cached twice: about twice the usage.
    public var schemaAsTool: Bool

    public init(
        executable: String = "claude",
        workingDirectory: URL? = nil,
        extraArguments: [String] = [],
        minimumTimeout: TimeInterval = 120,
        schemaAsTool: Bool = false
    ) {
        self.executable = executable
        self.workingDirectory = workingDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lofi-claude-code", isDirectory: true)
        self.extraArguments = extraArguments
        self.minimumTimeout = minimumTimeout
        self.schemaAsTool = schemaAsTool
    }

    /// One `claude -p` run: its arguments and the prompt it reads on stdin.
    struct Call: Equatable {
        var arguments: [String]
        var prompt: String
        var model: String
        /// The answer must be a JSON object found in the reply's text.
        var expectsJSON = false
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { throw ClaudeCodeError.badRequest("the request has no JSON body") }
        let call = try Self.call(for: json, extraArguments: extraArguments, schemaAsTool: schemaAsTool)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let path = try Self.resolve(executable)
        let run = try await Self.run(
            path: path, arguments: call.arguments, input: Data(call.prompt.utf8),
            directory: workingDirectory, timeout: max(minimumTimeout, request.timeoutInterval)
        )
        let (data, status) = Self.response(fromCLI: run.output, exitStatus: run.status, errorOutput: run.errorOutput,
                                           requestedModel: call.model, expectsJSON: call.expectsJSON)
        let url = request.url ?? URL(string: "https://api.anthropic.com/v1/messages")!
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"]) else {
            throw ClaudeCodeError.badRequest("could not make a response")
        }
        return (data, http)
    }

    // MARK: - Request

    /// Turns a Messages API body into `claude -p` arguments. Only what
    /// `ClaudeMoodEngine` sends is supported: one system prompt, one user
    /// message of text, an optional JSON schema and effort.
    static func call(for body: [String: Any], extraArguments: [String] = [], schemaAsTool: Bool = false) throws -> Call {
        guard let model = body["model"] as? String, !model.isEmpty else { throw ClaudeCodeError.badRequest("no model") }
        var system: String
        if let text = body["system"] as? String {
            system = text
        } else if let blocks = body["system"] as? [[String: Any]] {
            system = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        } else {
            system = ""
        }
        guard let messages = body["messages"] as? [[String: Any]], messages.count == 1,
              messages[0]["role"] as? String == "user"
        else { throw ClaudeCodeError.badRequest("expected exactly one user message") }
        let prompt: String
        if let text = messages[0]["content"] as? String {
            prompt = text
        } else if let blocks = messages[0]["content"] as? [[String: Any]] {
            prompt = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        } else {
            throw ClaudeCodeError.badRequest("the user message has no text")
        }

        var arguments = [
            "-p",
            "--output-format", "json",
            "--no-session-persistence",
            "--tools", "",
            "--model", model,
        ]
        let output = body["output_config"] as? [String: Any]
        var expectsJSON = false
        if let format = output?["format"] as? [String: Any], let schema = format["schema"] {
            let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
            let text = String(decoding: data, as: UTF8.self)
            if schemaAsTool {
                arguments += ["--json-schema", text]
            } else {
                system += (system.isEmpty ? "" : "\n\n") + Self.schemaInstruction + text
                expectsJSON = true
            }
        }
        if !system.isEmpty { arguments += ["--system-prompt", system] }
        if let effort = output?["effort"] as? String, !effort.isEmpty {
            arguments += ["--effort", effort]
        }
        return Call(arguments: arguments + extraArguments, prompt: prompt, model: model, expectsJSON: expectsJSON)
    }

    /// Precedes the schema at the end of the system prompt when it is not
    /// passed as a tool. Keys in the schema's order keep prompt v3's `about`
    /// before the mood, as structured output did.
    static let schemaInstruction = """
        Reply with one JSON object and nothing else: no other text and no code fence. \
        It must match this JSON Schema, with its keys in the order the schema lists them:

        """

    /// The first complete JSON object in `text` (skipping any words, code
    /// fence or stray brace around it), or nil when there is none.
    static func jsonObjectText(in text: String) -> String? {
        let chars = Array(text.unicodeScalars)
        for start in chars.indices where chars[start] == "{" {
            var depth = 0
            var inString = false
            var escaped = false
            scan: for i in start..<chars.count {
                let c = chars[i]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                    continue
                }
                switch c {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        var view = String.UnicodeScalarView()
                        view.append(contentsOf: chars[start...i])
                        let candidate = String(view)
                        if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) is [String: Any] {
                            return candidate
                        }
                        break scan
                    }
                default: break
                }
            }
        }
        return nil
    }

    // MARK: - Response

    struct CLIResult: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreationInputTokens: Int?
        }
        let type: String?
        let subtype: String?
        let isError: Bool?
        let result: String?
        let usage: Usage?
        let modelUsage: [String: ModelUsage]?
        struct ModelUsage: Decodable {}
    }

    /// Claude Code's `--output-format json` result as a Messages API response
    /// body and HTTP status. Errors map to the statuses the engine already
    /// handles: not signed in is 401 (stop), usage or rate limits 429 and
    /// overload 529 (retry), anything else 500 (retry).
    static func response(fromCLI output: Data, exitStatus: Int32, errorOutput: Data = Data(), requestedModel: String,
                         expectsJSON: Bool = false) -> (Data, Int) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // The result is the JSON object Claude Code printed: the whole output
        // with --output-format json, or the last line with stream-json.
        let printed = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [printed] + printed.split(whereSeparator: \.isNewline).map(String.init).reversed()
        var parsed: (CLIResult, [String: Any])?
        for candidate in candidates {
            let data = Data(candidate.utf8)
            if let r = try? decoder.decode(CLIResult.self, from: data),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               r.type == "result" || r.result != nil {
                parsed = (r, raw)
                break
            }
        }
        guard let (result, raw) = parsed else {
            let detail = String(decoding: (errorOutput.isEmpty ? output : errorOutput).suffix(300), as: UTF8.self)
            return (errorBody(type: "api_error", message: "claude exited \(exitStatus) without a result: \(detail)"), 500)
        }
        if result.isError == true || exitStatus != 0 {
            let message = result.result ?? result.subtype ?? "claude -p failed (exit \(exitStatus))"
            return (errorBody(type: errorType(message), message: message), status(for: message))
        }

        let text: String
        if let structured = raw["structured_output"], !(structured is NSNull),
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]) {
            text = String(decoding: data, as: UTF8.self)
        } else if expectsJSON {
            // A reply that holds no JSON object is retried, like an API error.
            guard let object = jsonObjectText(in: result.result ?? "") else {
                let detail = String((result.result ?? "").prefix(200))
                return (errorBody(type: "api_error", message: "the answer was not a JSON object: \(detail)"), 500)
            }
            text = object
        } else {
            text = result.result ?? ""
        }
        // Claude Code may also bill a small model for housekeeping; report the
        // requested model when it served the answer.
        let models = result.modelUsage.map { Array($0.keys).sorted() } ?? []
        let served = models.contains(requestedModel) ? requestedModel
            : models.first { $0.hasPrefix("claude-") && !$0.contains("haiku") } ?? requestedModel
        var usage: [String: Any] = [:]
        if let u = result.usage {
            usage["input_tokens"] = u.inputTokens ?? 0
            usage["output_tokens"] = u.outputTokens ?? 0
            usage["cache_read_input_tokens"] = u.cacheReadInputTokens ?? 0
            usage["cache_creation_input_tokens"] = u.cacheCreationInputTokens ?? 0
        }
        let message: [String: Any] = [
            "type": "message",
            "role": "assistant",
            "model": served,
            "content": [["type": "text", "text": text]],
            "stop_reason": "end_turn",
            "usage": usage,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
        return (data, 200)
    }

    static func status(for message: String) -> Int {
        let m = message.lowercased()
        if m.contains("not logged in") || m.contains("/login") || m.contains("invalid api key") || m.contains("oauth") {
            return 401
        }
        if m.contains("limit") || m.contains("rate") { return 429 }
        if m.contains("overload") { return 529 }
        return 500
    }

    static func errorType(_ message: String) -> String {
        switch status(for: message) {
        case 401: "authentication_error"
        case 429: "rate_limit_error"
        case 529: "overloaded_error"
        default: "api_error"
        }
    }

    static func errorBody(type: String, message: String) -> Data {
        let body: [String: Any] = ["type": "error", "error": ["type": type, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    // MARK: - Running claude

    /// The executable's path: as given when it contains a slash, otherwise
    /// the first match on PATH or in the folders Claude Code installs into.
    public static func resolve(_ executable: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let fm = FileManager.default
        if executable.contains("/") {
            let path = (executable as NSString).expandingTildeInPath
            guard fm.isExecutableFile(atPath: path) else { throw ClaudeCodeError.notFound(path) }
            return path
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        for folder in folders where !folder.isEmpty {
            let path = (folder as NSString).appendingPathComponent(executable)
            if fm.isExecutableFile(atPath: path) { return path }
        }
        throw ClaudeCodeError.notFound(executable)
    }

    struct Run {
        var output: Data
        var errorOutput: Data
        var status: Int32
    }

    /// One child process and its pipes, shared with the queues that feed and drain it.
    final class Child: @unchecked Sendable {
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        private let lock = NSLock()
        private var drained = Data()

        var errorOutput: Data {
            lock.lock()
            defer { lock.unlock() }
            return drained
        }

        func setErrorOutput(_ data: Data) {
            lock.lock()
            drained = data
            lock.unlock()
        }
    }

    static func run(path: String, arguments: [String], input: Data, directory: URL, timeout: TimeInterval) async throws -> Run {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Run, Error>) in
            let child = Child()
            child.process.executableURL = URL(fileURLWithPath: path)
            child.process.arguments = arguments
            child.process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "ANTHROPIC_API_KEY")
            child.process.environment = environment
            child.process.standardInput = child.stdin
            child.process.standardOutput = child.stdout
            child.process.standardError = child.stderr
            DispatchQueue.global().async {
                do {
                    try child.process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    child.stdin.fileHandleForWriting.write(input)
                    try? child.stdin.fileHandleForWriting.close()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    child.setErrorOutput(child.stderr.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let stop = DispatchWorkItem { if child.process.isRunning { child.process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
                let output = child.stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                child.process.waitUntilExit()
                stop.cancel()
                continuation.resume(returning: Run(output: output, errorOutput: child.errorOutput, status: child.process.terminationStatus))
            }
        }
    }
}

public enum ClaudeCodeError: Error, CustomStringConvertible {
    case badRequest(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .badRequest(let detail): "Claude Code transport: \(detail)"
        case .notFound(let name): "Claude Code not found (\(name)); install it and sign in once with `claude`"
        }
    }
}
#endif
