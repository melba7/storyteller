import Foundation

/// Minimal argument parsing: `--name value`, `--flag`, and positionals.
struct Arguments {
    private(set) var positionals: [String] = []
    private var options: [String: [String]] = [:]
    private var flags: Set<String> = []

    init(_ args: some Sequence<String>, flags knownFlags: Set<String>) {
        var it = Array(args).makeIterator()
        while let arg = it.next() {
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if let eq = name.firstIndex(of: "=") {
                    options[String(name[..<eq]), default: []].append(String(name[name.index(after: eq)...]))
                } else if knownFlags.contains(name) {
                    flags.insert(name)
                } else if let value = it.next() {
                    options[name, default: []].append(value)
                } else {
                    fail("missing value for --\(name)")
                }
            } else {
                positionals.append(arg)
            }
        }
    }

    func string(_ name: String) -> String? { options[name]?.last }
    func strings(_ name: String) -> [String] { options[name] ?? [] }
    func flag(_ name: String) -> Bool { flags.contains(name) }

    func int(_ name: String, default value: Int) -> Int {
        guard let raw = string(name) else { return value }
        guard let n = Int(raw) else { fail("--\(name) expects a whole number, got \(raw)") }
        return n
    }

    func double(_ name: String, default value: Double) -> Double {
        guard let raw = string(name) else { return value }
        guard let n = Double(raw) else { fail("--\(name) expects a number, got \(raw)") }
        return n
    }

    /// "3-7" or "4" -> a closed range of chapter ordinals.
    func range(_ name: String) -> ClosedRange<Int>? {
        guard let raw = string(name) else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        switch parts.count {
        case 1: return parts[0]...parts[0]
        case 2 where parts[0] <= parts[1]: return parts[0]...parts[1]
        default: fail("--\(name) expects a range like 0-3, got \(raw)")
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lofi-eval: \(message)\n".utf8))
    exit(2)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Writes one JSON object per line to a file or stdout.
final class JSONLWriter {
    private let handle: FileHandle
    private let encoder: JSONEncoder

    init(path: String?) throws {
        if let path, path != "-" {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
            guard let h = FileHandle(forWritingAtPath: path) else { fail("cannot write \(path)") }
            handle = h
        } else {
            handle = .standardOutput
        }
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func write(_ value: some Encodable) throws {
        var data = try encoder.encode(value)
        data.append(0x0A)
        handle.write(data)
    }

    deinit {
        if handle !== FileHandle.standardOutput { try? handle.close() }
    }
}

/// Reads one JSON object per line from a file or stdin.
func readJSONL<T: Decodable>(_ type: T.Type, path: String?) throws -> [T] {
    let data: Data
    if let path, path != "-" {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var out: [T] = []
    for (n, line) in data.split(separator: 0x0A).enumerated() where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) {
        do {
            out.append(try decoder.decode(T.self, from: Data(line)))
        } catch {
            fail("line \(n + 1) of \(path ?? "stdin"): \(error)")
        }
    }
    return out
}

/// SplitMix64, so samples replay exactly from a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Monotonic wall clock for latency measurements.
func now() -> Double { ProcessInfo.processInfo.systemUptime }

/// The narration pace `make_readaloud.py` assumes, used to simulate playback time.
enum Narration {
    static let wordsPerSecond = 2.6
    static let gapSeconds = 0.35
    static func seconds(forSentence text: String) -> Double {
        Double(text.split(whereSeparator: { $0.isWhitespace }).count) / wordsPerSecond + gapSeconds
    }
}
