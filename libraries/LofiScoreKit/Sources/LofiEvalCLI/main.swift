import Foundation
import LofiMood
import LofiScoreCore
import LofiText

// lofi-eval: the eval harness for the mood engines.
//
//   lofi-eval windows  <epub-dir> [--book id] [--sample N --seed S | --every-sentence] [--chapters a-b] [--out f]
//       Causal windows from a readaloud EPUB as JSON lines. By default, the
//       windows the app would read during straight-through playback (the
//       reading cadence on a simulated clock); --sample picks N random
//       sentences instead, for labelling.
//
//   lofi-eval run      --engine NAME [--in windows.jsonl] [--out readings.jsonl] [--limit N] [--concurrency N]
//       Runs one engine over window records and logs each reading with its latency.
//       --concurrency runs several readings at once (for network engines); the
//       output keeps the input order.
//
//   lofi-eval simulate <epub-dir> --engine NAME [--track track.json] [--book id] [--chapters a-b] [--out f]
//       Plays the book through MoodTracker on a simulated clock, exactly as the
//       app would, and reports readings, mood changes per hour and latency.
//       With --track, plays a saved mood track back and uses NAME wherever the
//       track does not reach, as the app does.
//
//   lofi-eval track    <epub-dir> --engine NAME --out track.json [--book id] [--words 250]
//                      [--chapters a-b] [--concurrency 4] [--dry-run]
//       Scores a whole book once into a mood track (see MoodTrackBuilder).
//       Resumes from an existing --out file. --dry-run only counts the entries
//       and estimates the Claude cost.
//
//   lofi-eval engines
//       Which engines can run on this machine.

let usage = """
    usage: lofi-eval windows <epub-dir> [--book ID] [--sample N --seed S | --every-sentence] [--chapters A-B] [--max-words 400] [--out FILE]
           lofi-eval run --engine NAME [--in FILE] [--out FILE] [--limit N] [--concurrency N]
           lofi-eval simulate <epub-dir> --engine NAME [--track FILE] [--book ID] [--chapters A-B] [--out FILE]
           lofi-eval track <epub-dir> --engine NAME --out FILE [--book ID] [--words 250] [--chapters A-B] [--concurrency 4] [--dry-run]
           lofi-eval engines
    engines: \(EngineFactory.names.joined(separator: ", "))
    """

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
let args = Arguments(arguments.dropFirst(), flags: ["every-sentence", "dry-run", "help"])

do {
    switch command {
    case "windows": try windowsCommand(args)
    case "run": try await runCommand(args)
    case "simulate": try await simulateCommand(args)
    case "track": try await trackCommand(args)
    case "engines": EngineFactory.availabilityReport().forEach { print($0) }
    case "help", "--help", "-h": print(usage)
    default: fail("unknown command \(command)\n\(usage)")
    }
} catch {
    fail("\(error)")
}

// MARK: - windows

/// Every narrated sentence of the book, in order.
func allPositions(_ guardian: SpoilerGuard, chapters: ClosedRange<Int>?) throws -> [SentencePosition] {
    var positions: [SentencePosition] = []
    var p = try guardian.firstPosition()
    while let position = p {
        if let chapters, position.chapterOrdinal > chapters.upperBound { break }
        if chapters?.contains(position.chapterOrdinal) ?? true { positions.append(position) }
        p = try guardian.position(after: position)
    }
    return positions
}

func openBook(_ args: Arguments, maxWords: Int = 400) throws -> (SpoilerGuard, String) {
    guard let dir = args.positionals.first else { fail("give the readaloud EPUB directory\n\(usage)") }
    let url = URL(fileURLWithPath: dir)
    let guardian = try SpoilerGuard(epubDirectory: url, policy: .init(maxWords: maxWords))
    return (guardian, args.string("book") ?? url.standardizedFileURL.lastPathComponent)
}

func windowsCommand(_ args: Arguments) throws {
    let (guardian, book) = try openBook(args, maxWords: args.int("max-words", default: 400))
    let chapters = args.range("chapters")
    let writer = try JSONLWriter(path: args.string("out"))
    let positions = try allPositions(guardian, chapters: nil)
    let total = positions.count
    let inRange = positions.filter { chapters?.contains($0.chapterOrdinal) ?? true }

    if let count = args.string("sample").flatMap(Int.init) {
        var rng = SeededGenerator(seed: UInt64(args.int("seed", default: 1)))
        var picked = Set<Int>()
        let eligible = inRange.filter { $0.sentenceIndex >= args.int("min-sentence", default: 0) }
        while picked.count < min(count, eligible.count) {
            picked.insert(Int.random(in: 0..<eligible.count, using: &rng))
        }
        for i in picked.sorted() {
            let window = try guardian.window(at: eligible[i])
            try writer.write(WindowRecord(book: book, window: window, total: total, trigger: "sample", seconds: nil))
        }
        note("\(book): \(picked.count) sampled windows of \(total) sentences")
        return
    }

    var cadence = ReadingCadence()
    var clock = 0.0
    var emitted = 0
    for position in inRange {
        let window = try guardian.window(at: position)
        let trigger: String?
        if args.flag("every-sentence") {
            trigger = "sentence"
        } else {
            trigger = cadence.observe(position, at: clock)?.rawValue
        }
        if let trigger {
            try writer.write(WindowRecord(book: book, window: window, total: total, trigger: trigger, seconds: clock))
            emitted += 1
        }
        clock += Narration.seconds(forSentence: window.lines.last?.text ?? "")
    }
    note("\(book): \(emitted) windows over \(inRange.count) sentences, \(Int(clock / 60)) min of narration")
}

// MARK: - run

func runCommand(_ args: Arguments) async throws {
    guard let name = args.string("engine") else { fail("give --engine\n\(usage)") }
    let engine = try EngineFactory.make(name)
    var records = try readJSONL(WindowRecord.self, path: args.string("in"))
    if let limit = args.string("limit").flatMap(Int.init) { records = Array(records.prefix(limit)) }
    let writer = try JSONLWriter(path: args.string("out"))

    var failures = 0
    var latencies: [Double] = []
    var counts: [String: Int] = [:]
    let started = now()
    let width = max(1, args.int("concurrency", default: 1))
    var done = 0
    for batchStart in stride(from: 0, to: records.count, by: width) {
        let batch = Array(records[batchStart..<min(records.count, batchStart + width)])
        let windows = try batch.map(rebuild)
        // Run the batch at once, then write it in input order.
        let results = await withTaskGroup(of: (Int, Result<MoodReading, any Error>, Double).self) { group in
            for (i, window) in windows.enumerated() {
                group.addTask {
                    let t0 = now()
                    do {
                        return (i, .success(try await engine.reading(for: window)), (now() - t0) * 1000)
                    } catch {
                        return (i, .failure(error), (now() - t0) * 1000)
                    }
                }
            }
            var out: [(Int, Result<MoodReading, any Error>, Double)] = []
            for await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }
        }
        for (i, result, ms) in results {
            switch result {
            case .success(let reading):
                latencies.append(ms)
                counts[reading.bucket.rawValue, default: 0] += 1
                try writer.write(ReadingRecord(id: batch[i].id, engine: engine.id, reading: reading, latencyMs: ms))
            case .failure(let error):
                failures += 1
                try writer.write(ReadingRecord(id: batch[i].id, engine: engine.id, error: error, latencyMs: ms))
            }
            done += 1
            if done % 100 == 0 { note("  \(done)/\(records.count)") }
        }
    }
    latencies.sort()
    let p50 = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
    let p95 = latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]
    note(String(
        format: "%@: %d readings, %d failures, p50 %.1f ms, p95 %.1f ms, %.1f s total",
        engine.id, records.count - failures, failures, p50, p95, now() - started
    ))
    note("  buckets: " + counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    reportClaudeUsage()
}

/// Rebuilds the record's window through an in-memory guard, so engines see
/// exactly the text that was exported (and, for masked records, edited).
func rebuild(_ record: WindowRecord) throws -> CausalWindow {
    let chapters = record.chapters.filter { !$0.isEmpty }
    guard let last = chapters.last else { throw MoodEngineError.emptyWindow }
    let guardian = try SpoilerGuard(
        chapters: chapters,
        policy: .init(maxWords: 1_000_000, maxEarlierChapters: chapters.count)
    )
    guard let position = try guardian.position(chapterOrdinal: chapters.count - 1, sentenceIndex: last.count - 1) else {
        throw MoodEngineError.emptyWindow
    }
    return try guardian.window(at: position)
}

// MARK: - simulate

final class SimulatedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 0.0
    func advance(_ seconds: Double) { lock.lock(); t += seconds; lock.unlock() }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return t }
}

func simulateCommand(_ args: Arguments) async throws {
    guard let name = args.string("engine") else { fail("give --engine\n\(usage)") }
    let (guardian, book) = try openBook(args)
    var live = try EngineFactory.make(name)
    if let trackPath = args.string("track") {
        let track = try MoodTrack.decode(Data(contentsOf: URL(fileURLWithPath: trackPath)))
        note("playing \(track.entries.count) track entries from \(track.engineID), \(name) elsewhere")
        live = TrackedMoodEngine(store: MoodTrackStore(track), fallback: live)
    }
    let engine = TimedEngine(live)
    let clock = SimulatedClock()
    let tracker = MoodTracker(spoilerGuard: guardian, engine: engine, clock: { clock.read() })
    let writer = try JSONLWriter(path: args.string("out"))
    let positions = try allPositions(guardian, chapters: args.range("chapters"))

    var observations: [ObservationRecord] = []
    var latencies: [Double] = []
    for position in positions {
        if let o = await tracker.sentenceStarted(position) {
            let latency = engine.takeLatency()
            if let latency { latencies.append(latency) }
            let record = ObservationRecord(
                book: book, chapter: o.chapterOrdinal, sentence: o.sentenceIndex, global: o.globalSentenceIndex,
                seconds: (clock.read() * 10).rounded() / 10, trigger: o.trigger.rawValue,
                bucket: o.reading.bucket.rawValue, valence: round3(o.reading.valence), arousal: round3(o.reading.arousal),
                confidence: round3(o.reading.confidence), engine: o.reading.engineID,
                latencyMs: latency.map { ($0 * 10).rounded() / 10 }
            )
            observations.append(record)
            try writer.write(record)
        }
        let line = try guardian.window(at: position).lines.last?.text ?? ""
        clock.advance(Narration.seconds(forSentence: line))
    }

    let hours = max(clock.read() / 3600, 1e-9)
    var changes = 0
    for (a, b) in zip(observations, observations.dropFirst()) where a.bucket != b.bucket { changes += 1 }
    latencies.sort()
    let failures = await tracker.failures
    note(String(
        format: "%@ with %@: %d readings over %.1f h of narration, %d mood changes (%.1f per hour), p50 latency %.1f ms, %d failures",
        book, engine.id, observations.count, hours, changes, Double(changes) / hours,
        latencies.isEmpty ? 0 : latencies[latencies.count / 2], failures.count
    ))
    let byEngine = Dictionary(grouping: observations, by: \.engine).mapValues(\.count)
    if byEngine.count > 1 {
        note("  readings by engine: " + byEngine.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    }
}
