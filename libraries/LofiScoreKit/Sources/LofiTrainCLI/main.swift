import Foundation
import LofiMood
import LofiScoreCore
#if canImport(CreateML)
import CreateML
#endif

// lofi-train: builds the Fast engine's Create ML text classifier.
//
//   lofi-train export --windows W.jsonl [--windows W2.jsonl ...] --labels L.jsonl [--labels L2.jsonl ...]
//                     [--split split.json] [--out-dir DIR] [--chunk-words 160] [--balance]
//                     [--validation-books N]
//       Joins window records (several window files are read in order; a window
//       id seen twice is kept once) with labels (a later label file wins over an
//       earlier one, so Mo's corrections override Claude's), keeps the newest
//       words of each window exactly as the Fast engine will see them, and
//       writes DIR/train.json and DIR/test.json in Create ML's JSON format,
//       plus DIR/test-windows.jsonl for `lofi-eval run` and DIR/earlier.json
//       (the words before each chunk, which the engines blend in) for
//       `embed`. With --balance, rarer moods in the training set are repeated
//       (in order, no randomness) until every mood has as many examples as the
//       commonest; Create ML's MaxEnt has no class weights, and without this it
//       rarely predicts the rare moods.
//       The test set is never changed. With --validation-books N, N training
//       books (spread evenly through the sorted list) go to DIR/valid.json
//       instead, unbalanced and never repeated, so Create ML validates on rows
//       it has not trained on. Without it, Create ML splits its own validation
//       set off train.json, and after --balance that set holds copies of
//       training rows, so its validation accuracy means nothing. Runs anywhere.
//
//   lofi-train train --algorithm maxent|elmo|bert [--data DIR] [--out FILE.mlmodel] [--version V] [--all]
//                    [--max-iterations N]
//       macOS only. Trains on DIR/train.json (and DIR/valid.json and
//       DIR/test.json too with --all, for the model that ships once the engine
//       choice is made), validates on DIR/valid.json when it exists, reports
//       accuracy and macro-F1 on DIR/test.json, and writes the model plus a
//       FILE.report.json beside it. --max-iterations sets Create ML's
//       ModelParameters.maxIterations (its default is used otherwise).
//
//   lofi-train embed [--data DIR] [--kinds word,contextual,word+contextual] [--folds 5]
//                    [--choose exact|kappa|macro-f1] [--version V] [--out-dir DIR]
//                    [--iterations N] [--all] [--curve]
//       macOS only. A Fast engine on Apple's on-device embeddings instead of a
//       bag of words; see Embed.swift.

let usage = """
    usage: lofi-train export --windows FILE [--windows FILE ...] --labels FILE [--labels FILE ...] [--split FILE] [--out-dir DIR] [--chunk-words N] [--balance] [--validation-books N]
           lofi-train train --algorithm maxent|elmo|bert [--data DIR] [--out FILE.mlmodel] [--version V] [--all] [--max-iterations N]
           lofi-train embed [--data DIR] [--kinds word,contextual,word+contextual] [--folds 5] [--choose exact|kappa|macro-f1] [--version V] [--out-dir DIR] [--iterations N] [--all] [--curve]
    """

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
let options = Options(arguments.dropFirst(), flags: ["all", "balance", "curve", "help"])

do {
    switch command {
    case "export": try exportCommand(options)
    case "train": try trainCommand(options)
    case "embed": try embedCommand(options)
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
    let windowPaths = options.strings("windows")
    guard !windowPaths.isEmpty else { fail("give at least one --windows file\n\(usage)") }
    let labelPaths = options.strings("labels")
    guard !labelPaths.isEmpty else { fail("give at least one --labels file\n\(usage)") }
    let outDir = URL(fileURLWithPath: options.string("out-dir") ?? "Tools/data/work/train", isDirectory: true)
    let chunkWords = options.int("chunk-words", default: ClassifierInput.defaultChunkWords)
    let validationBookCount = options.int("validation-books", default: 0)
    if validationBookCount < 0 { fail("--validation-books must be 0 or more") }
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
    var duplicates = 0
    var seen: Set<String> = []
    var earlierChunks: [String: String] = [:]
    let windowLines = try windowPaths.flatMap { try Data(contentsOf: URL(fileURLWithPath: $0)).split(separator: 0x0A) }
    for line in windowLines where !line.isEmpty {
        let window = try JSONDecoder().decode(WindowText.self, from: Data(line))
        guard seen.insert(window.id).inserted else {
            duplicates += 1
            continue
        }
        guard let label = labels[window.id], let bucket = MoodBucket(lenient: label.bucket) else {
            unlabelled += 1
            continue
        }
        let example = Example(
            id: window.id, book: window.book,
            text: ClassifierInput.recentChunk(of: window.text, words: chunkWords), label: bucket.rawValue
        )
        let earlier = ClassifierInput.earlierChunk(of: window.text, words: chunkWords)
        if ClassifierInput.wordCount(earlier) >= ClassifierInput.minimumEarlierWords { earlierChunks[window.id] = earlier }
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

    let validationBooks = spreadPick(Set(train.map(\.book)).sorted(), count: validationBookCount)
    if validationBookCount > 0 && validationBooks.count < validationBookCount {
        fail("--validation-books \(validationBookCount) would leave no training books")
    }
    let valid = train.filter { validationBooks.contains($0.book) }
    train.removeAll { validationBooks.contains($0.book) }

    let distinctTrain = train.count
    if options.flag("balance") { train = balanced(train) }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(train).write(to: outDir.appendingPathComponent("train.json"))
    try encoder.encode(test).write(to: outDir.appendingPathComponent("test.json"))
    try testWindows.write(to: outDir.appendingPathComponent("test-windows.jsonl"))
    // The words before each chunk, which the engines blend in; `embed` reads them.
    try encoder.encode(earlierChunks).write(to: outDir.appendingPathComponent("earlier.json"))
    let validURL = outDir.appendingPathComponent("valid.json")
    if valid.isEmpty {
        // A stale valid.json from an earlier export would be picked up by `train`.
        try? FileManager.default.removeItem(at: validURL)
    } else {
        try encoder.encode(valid).write(to: validURL)
    }

    note("train: \(distinctTrain) examples from \(Set(train.map(\.book)).count) books (\(describe(labellers["train"]!)))")
    if train.count != distinctTrain { note("  balanced to \(train.count) by repeating rarer moods") }
    note("  \(distribution(train))")
    if valid.isEmpty {
        if train.count != distinctTrain {
            note("  no --validation-books: Create ML will validate on copies of training rows, so ignore its validation accuracy")
        }
    } else {
        note("valid: \(valid.count) examples from \(validationBooks.count) books (\(validationBooks.sorted().joined(separator: ", ")))")
        note("  \(distribution(valid))")
    }
    note("test:  \(test.count) examples from \(Set(test.map(\.book)).count) books (\(describe(labellers["test"]!)))")
    note("  \(distribution(test))")
    if unlabelled > 0 { note("skipped \(unlabelled) windows with no label") }
    if duplicates > 0 { note("skipped \(duplicates) repeated window ids") }
    note("wrote \(outDir.path)/train.json, \(valid.isEmpty ? "" : "valid.json, ")test.json, test-windows.jsonl, earlier.json (newest \(chunkWords) words per window, and the \(chunkWords) before them)")
}

/// `count` items spread evenly through `items` (which should be sorted), so
/// the same book list always gives the same choice.
func spreadPick(_ items: [String], count: Int) -> Set<String> {
    guard count > 0, count < items.count else { return [] }
    return Set((0..<count).map { items[($0 * items.count + items.count / 2) / count] })
}

/// Repeats each mood's examples in order until every mood has as many as the
/// commonest one. Deterministic, so the same labels always give the same model.
func balanced(_ examples: [Example]) -> [Example] {
    let groups = Dictionary(grouping: examples, by: \.label)
    guard let target = groups.values.map(\.count).max() else { return examples }
    var out = examples
    for label in groups.keys.sorted() {
        let group = groups[label]!
        for k in 0..<(target - group.count) { out.append(group[k % group.count]) }
    }
    return out
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
    // Create ML's `ModelParameters.maxIterations` (Int?); nil keeps its default.
    let maxIterations = options.string("max-iterations").map { _ in options.int("max-iterations", default: 0) }
    if let n = maxIterations, n < 1 { fail("--max-iterations must be at least 1") }
    #if canImport(CreateML)
    try train(algorithm: algorithm, dataDir: dataDir, out: out, version: version, includeTest: options.flag("all"), maxIterations: maxIterations)
    #else
    _ = (dataDir, out, version, maxIterations)
    fail("training needs macOS with Create ML; run `lofi-train export` here and `lofi-train train` on the Mac")
    #endif
}

#if canImport(CreateML)
func train(algorithm name: String, dataDir: URL, out: URL, version: String, includeTest: Bool, maxIterations: Int? = nil) throws {
    let trainURL = dataDir.appendingPathComponent("train.json")
    let validURL = dataDir.appendingPathComponent("valid.json")
    let testURL = dataDir.appendingPathComponent("test.json")
    let test = try JSONDecoder().decode([Example].self, from: Data(contentsOf: testURL))
    var table = try MLDataTable(contentsOf: trainURL)
    let validTable = try FileManager.default.fileExists(atPath: validURL.path) ? MLDataTable(contentsOf: validURL) : nil
    let validation: MLTextClassifier.ModelParameters.ValidationData
    if includeTest {
        // The shipping model learns from every labelled window.
        table.append(contentsOf: try MLDataTable(contentsOf: testURL))
        if let validTable { table.append(contentsOf: validTable) }
        validation = .none
    } else if let validTable {
        validation = .table(validTable, textColumn: "text", labelColumn: "label")
    } else {
        validation = .split(strategy: .automatic)
    }

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
    var parameters = MLTextClassifier.ModelParameters(validation: validation, algorithm: algorithm, language: .english)
    if let maxIterations { parameters.maxIterations = maxIterations }

    let validNote = includeTest ? " (including the validation and test books)" : validTable.map { ", validating on \($0.rows.count) held-out examples" } ?? ""
    note("training \(name) on \(table.rows.count) examples\(validNote)\(maxIterations.map { ", max \($0) iterations" } ?? "")…")
    let started = Date()
    let classifier = try MLTextClassifier(trainingData: table, textColumn: "text", labelColumn: "label", parameters: parameters)
    let seconds = Date().timeIntervalSince(started)

    let predicted = try test.map { try classifier.prediction(from: $0.text) }
    let scores = Scores(gold: test.map(\.label), predicted: predicted)
    let validationAccuracy: Double? = includeTest ? nil : 1 - classifier.validationMetrics.classificationError
    note(String(format: "trained in %.0f s; training accuracy %.1f%%", seconds, (1 - classifier.trainingMetrics.classificationError) * 100)
         + (validationAccuracy.map { String(format: ", validation accuracy %.1f%%", $0 * 100) } ?? ""))
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
        validationExamples: includeTest ? nil : validTable?.rows.count,
        trainingAccuracy: 1 - classifier.trainingMetrics.classificationError,
        validationAccuracy: validationAccuracy,
        testAccuracy: scores.accuracy, testMacroF1: scores.macroF1,
        maxIterations: maxIterations
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
    /// Held-out rows from DIR/valid.json; nil when Create ML split its own.
    var validationExamples: Int?
    var trainingAccuracy: Double
    /// nil when there was no validation set (`--all`).
    var validationAccuracy: Double?
    var testAccuracy: Double
    var testMacroF1: Double
    /// Create ML's iteration cap when `--max-iterations` was given.
    var maxIterations: Int? = nil
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
