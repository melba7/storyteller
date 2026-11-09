import Foundation
import LofiMood
import LofiScoreCore
#if canImport(CreateML)
import CreateML
#endif

// lofi-train: builds the Fast engine's Create ML text classifier.
//
//   lofi-train export --windows W.jsonl --labels L.jsonl [--labels L2.jsonl ...]
//                     [--split split.json] [--out-dir DIR] [--chunk-words 160]
//       Joins window records with labels (a later label file wins over an
//       earlier one, so Mo's corrections override Claude's), keeps the newest
//       words of each window exactly as the Fast engine will see them, and
//       writes DIR/train.json and DIR/test.json in Create ML's JSON format,
//       plus DIR/test-windows.jsonl for `lofi-eval run`. Runs anywhere.
//
//   lofi-train train --algorithm maxent|elmo|bert [--data DIR] [--out FILE.mlmodel] [--version V] [--all]
//       macOS only. Trains on DIR/train.json (and DIR/test.json too with --all,
//       for the model that ships once the engine choice is made), reports
//       accuracy and macro-F1 on DIR/test.json, and writes the model plus a
//       FILE.report.json beside it.

let usage = """
    usage: lofi-train export --windows FILE --labels FILE [--labels FILE ...] [--split FILE] [--out-dir DIR] [--chunk-words N]
           lofi-train train --algorithm maxent|elmo|bert [--data DIR] [--out FILE.mlmodel] [--version V] [--all]
    """

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
let options = Options(arguments.dropFirst(), flags: ["all", "help"])

do {
    switch command {
    case "export": try exportCommand(options)
    case "train": try trainCommand(options)
    case "help", "--help", "-h": print(usage)
    default: fail("unknown command \(command)\n\(usage)")
    }
} catch {
    fail("\(error)")
}

// MARK: - export

struct WindowText: Codable {
    var id: String
    var book: String
    var text: String
}

struct Label: Codable {
    var id: String
    var bucket: String
    var labeller: String?
}

struct Split: Codable {
    var testBooks: [String]
    enum CodingKeys: String, CodingKey { case testBooks = "test_books" }
}

/// One row of Create ML's JSON training format.
struct Example: Codable {
    var id: String
    var book: String
    var text: String
    var label: String
}

func exportCommand(_ options: Options) throws {
    guard let windowsPath = options.string("windows") else { fail("give --windows\n\(usage)") }
    let labelPaths = options.strings("labels")
    guard !labelPaths.isEmpty else { fail("give at least one --labels file\n\(usage)") }
    let outDir = URL(fileURLWithPath: options.string("out-dir") ?? "Tools/data/work/train", isDirectory: true)
    let chunkWords = options.int("chunk-words", default: ClassifierInput.defaultChunkWords)
    let testBooks: Set<String>
    if let splitPath = options.string("split") {
        testBooks = Set(try JSONDecoder().decode(Split.self, from: Data(contentsOf: URL(fileURLWithPath: splitPath))).testBooks)
    } else {
        testBooks = []
    }

    // Later files win, so corrections can be layered over a first pass.
    var labels: [String: Label] = [:]
    for path in labelPaths {
        for label in try readLines(Label.self, path: path) {
            guard MoodBucket(lenient: label.bucket) != nil else { fail("\(path): \(label.id) has unknown bucket \(label.bucket)") }
            labels[label.id] = label
        }
    }

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    var train: [Example] = []
    var test: [Example] = []
    var testWindows = Data()
    var labellers: [String: [String: Int]] = ["train": [:], "test": [:]]
    var unlabelled = 0
    let windowLines = try Data(contentsOf: URL(fileURLWithPath: windowsPath)).split(separator: 0x0A)
    for line in windowLines where !line.isEmpty {
        let window = try JSONDecoder().decode(WindowText.self, from: Data(line))
        guard let label = labels[window.id], let bucket = MoodBucket(lenient: label.bucket) else {
            unlabelled += 1
            continue
        }
        let example = Example(
            id: window.id, book: window.book,
            text: ClassifierInput.recentChunk(of: window.text, words: chunkWords), label: bucket.rawValue
        )
        let side = testBooks.contains(window.book) ? "test" : "train"
        labellers[side]![label.labeller ?? "unknown", default: 0] += 1
        if side == "test" {
            test.append(example)
            testWindows.append(line)
            testWindows.append(0x0A)
        } else {
            train.append(example)
        }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(train).write(to: outDir.appendingPathComponent("train.json"))
    try encoder.encode(test).write(to: outDir.appendingPathComponent("test.json"))
    try testWindows.write(to: outDir.appendingPathComponent("test-windows.jsonl"))

    note("train: \(train.count) examples from \(Set(train.map(\.book)).count) books (\(describe(labellers["train"]!)))")
    note("  \(distribution(train))")
    note("test:  \(test.count) examples from \(Set(test.map(\.book)).count) books (\(describe(labellers["test"]!)))")
    note("  \(distribution(test))")
    if unlabelled > 0 { note("skipped \(unlabelled) windows with no label") }
    note("wrote \(outDir.path)/train.json, test.json, test-windows.jsonl (newest \(chunkWords) words per window)")
}

func describe(_ counts: [String: Int]) -> String {
    counts.isEmpty ? "no labels" : counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
}

func distribution(_ examples: [Example]) -> String {
    let counts = Dictionary(grouping: examples, by: \.label).mapValues(\.count)
    return MoodBucket.allCases.map { "\($0.rawValue) \(counts[$0.rawValue] ?? 0)" }.joined(separator: ", ")
}

// MARK: - train

func trainCommand(_ options: Options) throws {
    guard let algorithm = options.string("algorithm") else { fail("give --algorithm maxent, elmo or bert\n\(usage)") }
    guard ["maxent", "elmo", "bert"].contains(algorithm) else { fail("unknown --algorithm \(algorithm); use maxent, elmo or bert") }
    let dataDir = URL(fileURLWithPath: options.string("data") ?? "Tools/data/work/train", isDirectory: true)
    let version = options.string("version") ?? "1"
    let out = URL(fileURLWithPath: options.string("out") ?? "Models/LofiMood-\(algorithm)-\(version).mlmodel")
    #if canImport(CreateML)
    try train(algorithm: algorithm, dataDir: dataDir, out: out, version: version, includeTest: options.flag("all"))
    #else
    _ = (dataDir, out, version)
    fail("training needs macOS with Create ML; run `lofi-train export` here and `lofi-train train` on the Mac")
    #endif
}

#if canImport(CreateML)
func train(algorithm name: String, dataDir: URL, out: URL, version: String, includeTest: Bool) throws {
    let trainURL = dataDir.appendingPathComponent("train.json")
    let testURL = dataDir.appendingPathComponent("test.json")
    let test = try JSONDecoder().decode([Example].self, from: Data(contentsOf: testURL))
    var table = try MLDataTable(contentsOf: trainURL)
    if includeTest { table.append(contentsOf: try MLDataTable(contentsOf: testURL)) }

    let algorithm: MLTextClassifier.ModelAlgorithmType
    switch name {
    case "maxent":
        algorithm = .maxEnt(revision: 1)
    case "elmo":
        algorithm = .transferLearning(.dynamicEmbedding, revision: 1)
    default:
        guard #available(macOS 14.0, *) else { fail("bert needs macOS 14 or later") }
        algorithm = .transferLearning(.bertEmbedding, revision: 1)
    }
    let parameters = MLTextClassifier.ModelParameters(
        validation: .split(strategy: .automatic), algorithm: algorithm, language: .english
    )

    note("training \(name) on \(table.rows.count) examples\(includeTest ? " (including the test books)" : "")…")
    let started = Date()
    let classifier = try MLTextClassifier(trainingData: table, textColumn: "text", labelColumn: "label", parameters: parameters)
    let seconds = Date().timeIntervalSince(started)

    let predicted = try test.map { try classifier.prediction(from: $0.text) }
    let scores = Scores(gold: test.map(\.label), predicted: predicted)
    note(String(format: "trained in %.0f s; training accuracy %.1f%%, validation accuracy %.1f%%",
                seconds,
                (1 - classifier.trainingMetrics.classificationError) * 100,
                (1 - classifier.validationMetrics.classificationError) * 100))
    if includeTest {
        note("test books were trained on, so the test numbers below are not an estimate of quality")
    }
    note(String(format: "test (%d windows): accuracy %.1f%%, macro-F1 %.3f", test.count, scores.accuracy * 100, scores.macroF1))
    scores.confusionLines().forEach { note($0) }

    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let metadata = MLModelMetadata(
        author: "LofiScoreKit lofi-train",
        shortDescription: "Mood of the newest \(ClassifierInput.defaultChunkWords) narrated words, one of: \(MoodBucket.allCases.map(\.rawValue).joined(separator: ", ")).",
        version: version
    )
    try classifier.write(to: out, metadata: metadata)

    let report = TrainReport(
        algorithm: name, version: version, trainedOnTestBooks: includeTest,
        trainingExamples: table.rows.count, testExamples: test.count, seconds: seconds.rounded(),
        trainingAccuracy: 1 - classifier.trainingMetrics.classificationError,
        validationAccuracy: 1 - classifier.validationMetrics.classificationError,
        testAccuracy: scores.accuracy, testMacroF1: scores.macroF1
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: out.deletingPathExtension().appendingPathExtension("report.json"))
    note("wrote \(out.path)")
}

struct TrainReport: Codable {
    var algorithm: String
    var version: String
    var trainedOnTestBooks: Bool
    var trainingExamples: Int
    var testExamples: Int
    var seconds: Double
    var trainingAccuracy: Double
    var validationAccuracy: Double
    var testAccuracy: Double
    var testMacroF1: Double
}
#endif

// MARK: - scoring

/// Accuracy, macro-F1 and a confusion table over the eight buckets.
struct Scores {
    let gold: [String]
    let predicted: [String]

    var accuracy: Double {
        gold.isEmpty ? 0 : Double(zip(gold, predicted).filter { $0 == $1 }.count) / Double(gold.count)
    }

    var macroF1: Double {
        let present = MoodBucket.allCases.map(\.rawValue).filter { gold.contains($0) || predicted.contains($0) }
        guard !present.isEmpty else { return 0 }
        let f1s = present.map { bucket -> Double in
            let tp = Double(zip(gold, predicted).filter { $0 == bucket && $1 == bucket }.count)
            let fp = Double(zip(gold, predicted).filter { $0 != bucket && $1 == bucket }.count)
            let fn = Double(zip(gold, predicted).filter { $0 == bucket && $1 != bucket }.count)
            return tp == 0 ? 0 : 2 * tp / (2 * tp + fp + fn)
        }
        return f1s.reduce(0, +) / Double(f1s.count)
    }

    func confusionLines() -> [String] {
        let buckets = MoodBucket.allCases.map(\.rawValue)
        var lines = ["  gold \\ model " + buckets.map { String($0.prefix(5)).padding(toLength: 6, withPad: " ", startingAt: 0) }.joined()]
        for g in buckets {
            let row = buckets.map { p in String(zip(gold, predicted).filter { $0 == g && $1 == p }.count) }
            lines.append("  " + g.padding(toLength: 12, withPad: " ", startingAt: 0) + row.map { $0.padding(toLength: 6, withPad: " ", startingAt: 0) }.joined())
        }
        return lines
    }
}

// MARK: - support

/// `--name value`, `--name=value`, known flags, and positionals.
struct Options {
    private var values: [String: [String]] = [:]
    private var flags: Set<String> = []

    init(_ args: some Sequence<String>, flags known: Set<String>) {
        var it = Array(args).makeIterator()
        while let arg = it.next() {
            guard arg.hasPrefix("--") else { continue }
            let name = String(arg.dropFirst(2))
            if let eq = name.firstIndex(of: "=") {
                values[String(name[..<eq]), default: []].append(String(name[name.index(after: eq)...]))
            } else if known.contains(name) {
                flags.insert(name)
            } else if let value = it.next() {
                values[name, default: []].append(value)
            } else {
                fail("missing value for --\(name)")
            }
        }
    }

    func string(_ name: String) -> String? { values[name]?.last }
    func strings(_ name: String) -> [String] { values[name] ?? [] }
    func flag(_ name: String) -> Bool { flags.contains(name) }
    func int(_ name: String, default value: Int) -> Int {
        guard let raw = string(name) else { return value }
        guard let n = Int(raw) else { fail("--\(name) expects a whole number, got \(raw)") }
        return n
    }
}

func readLines<T: Decodable>(_ type: T.Type, path: String) throws -> [T] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let decoder = JSONDecoder()
    return try data.split(separator: 0x0A).filter { !$0.isEmpty }.map { try decoder.decode(T.self, from: Data($0)) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lofi-train: \(message)\n".utf8))
    exit(2)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
