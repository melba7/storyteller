import Foundation
import LofiAtmosphere
import LofiMood
import LofiPlaceholders
import LofiText

// lofi-atmosphere: score a book's atmosphere track with Claude, print a track's scenes,
// write the synthesised stand-in sounds, or check a sounds folder.

let usage = """
    usage:
      lofi-atmosphere track EPUB-DIR --book NAME --out FILE [--model claude-opus-5-5] [--effort low]
                      [--max-dollars D] [--words 250] [--probe-budget 0.5] [--resolution 3] [--concurrency 4]
      lofi-atmosphere track EPUB-DIR --book NAME --dry-run
      lofi-atmosphere show FILE [--places]
      lofi-atmosphere synth FOLDER [--seconds 30] [--rate 32000] [--sound rain]
      lofi-atmosphere library FOLDER

    The key comes from ANTHROPIC_API_KEY, or the file named by ANTHROPIC_API_KEY_FILE; it is never printed.
    """

func note(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func fail(_ text: String) -> Never {
    note(text)
    exit(2)
}

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []
    static let flagNames: Set<String> = ["dry-run", "places"]

    init(_ raw: [String]) {
        var i = 0
        while i < raw.count {
            let item = raw[i]
            if item.hasPrefix("--") {
                let name = String(item.dropFirst(2))
                if Self.flagNames.contains(name) {
                    flags.insert(name)
                } else if i + 1 < raw.count {
                    options[name] = raw[i + 1]
                    i += 1
                } else {
                    fail("\(item) needs a value\n\(usage)")
                }
            } else {
                positional.append(item)
            }
            i += 1
        }
    }

    func string(_ name: String) -> String? { options[name] }
    func int(_ name: String, default value: Int) -> Int { options[name].flatMap(Int.init) ?? value }
    func double(_ name: String, default value: Double) -> Double { options[name].flatMap(Double.init) ?? value }
    func flag(_ name: String) -> Bool { flags.contains(name) }
}

func apiKey() -> String {
    let env = ProcessInfo.processInfo.environment
    if let key = env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    if let path = env["ANTHROPIC_API_KEY_FILE"], !path.isEmpty,
       let key = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    fail("set ANTHROPIC_API_KEY, or ANTHROPIC_API_KEY_FILE to a file holding the key")
}

/// Stops a paid run before it spends more than `--max-dollars` at list prices.
final class SpendCap: @unchecked Sendable {
    let dollars: Double?
    let prices: ScenePrices
    let usage: SceneUsage
    private let lock = NSLock()
    private var started = 0

    init(dollars: Double?, prices: ScenePrices, usage: SceneUsage) {
        self.dollars = dollars
        self.prices = prices
        self.usage = usage
    }

    var spent: Double { prices.dollars(usage.totals) }

    /// True when one more request fits under the cap, counting requests still in flight.
    func allowsAnother() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let dollars else {
            started += 1
            return true
        }
        let totals = usage.totals
        let perRequest = totals.responses > 0 ? spent / Double(totals.responses) : prices.dollars(input: 3_000, output: 600)
        let inFlight = Double(max(0, started - totals.responses))
        guard spent + perRequest * (inFlight + 1) <= dollars else { return false }
        started += 1
        return true
    }
}

func openGuard(_ path: String) -> SpoilerGuard {
    do {
        return try SpoilerGuard(epubDirectory: URL(fileURLWithPath: path))
    } catch {
        fail("could not open \(path) as an unpacked read-aloud EPUB: \(error)")
    }
}

// MARK: - track

func trackCommand(_ args: Arguments) async throws {
    guard let epub = args.positional.dropFirst().first else { fail(usage) }
    let book = args.string("book") ?? URL(fileURLWithPath: epub).lastPathComponent
    let spoilerGuard = openGuard(epub)
    let budget = args.double("probe-budget", default: 0.5)
    let plan = AtmosphereTrackBuilder.Plan(
        wordsBetweenEntries: args.int("words", default: 250),
        refinement: budget > 0 ? .init(resolutionSentences: args.int("resolution", default: 3), probeBudget: budget) : nil
    )
    let builder = AtmosphereTrackBuilder(spoilerGuard: spoilerGuard, plan: plan)

    if args.flag("dry-run") {
        let all = try builder.narratedPositions()
        let positions = try builder.scoringPositions(all)
        var passageWords = 0
        for position in positions {
            passageWords += min(400, try spoilerGuard.window(at: position).wordCount)
        }
        let probes = plan.refinement?.maxProbes(planned: positions.count) ?? 0
        let requests = positions.count + probes
        let averageWords = Double(passageWords) / Double(max(1, positions.count))
        // Passage at ~1.35 tokens a word, plus ~450 for the place list and framing;
        // the ~2,000-token system prompt is read from the cache after the first request.
        let input = Int(Double(requests) * (averageWords * 1.35 + 450))
        let cached = requests * 2_000
        let output = requests * 450
        note("\(book): \(all.count) narrated sentences, \(positions.count) entries (one per ~\(plan.wordsBetweenEntries) words plus one per chapter), up to \(probes) probes")
        for prices in ScenePrices.known {
            var totals = SceneUsage.Totals()
            totals.inputTokens = input
            totals.cacheReadTokens = cached
            totals.outputTokens = output
            note(String(format: "  %@: about $%.2f at most (%.0fk input, %.0fk output tokens; estimate)",
                        prices.model, prices.dollars(totals), Double(input + cached) / 1000, Double(output) / 1000))
        }
        note("  the first pass runs in order (each request knows the places before it): about \(Int(Double(positions.count) * 6 / 60)) min at ~6 s a request")
        return
    }

    guard let outPath = args.string("out") else { fail("give --out FILE\n\(usage)") }
    let model = args.string("model") ?? "claude-opus-5-5"
    guard let prices = ScenePrices.forModel(model) else { fail("no price known for \(model); use one of \(ScenePrices.known.map(\.model))") }
    let usage = SceneUsage()
    let engine = ClaudeSceneEngine(
        apiKey: apiKey(),
        configuration: .init(model: prices.model, effort: args.string("effort") ?? "low"),
        usage: usage
    )
    let outURL = URL(fileURLWithPath: outPath)
    var track = AtmosphereTrack(engineID: engine.id, bookID: book, wordsBetweenEntries: plan.wordsBetweenEntries)
    if FileManager.default.fileExists(atPath: outPath) {
        let existing = try AtmosphereTrack.load(from: outURL)
        guard existing.engineID == engine.id else {
            fail("\(outPath) was made by \(existing.engineID), not \(engine.id); use another --out")
        }
        track = existing
        note("resuming: \(existing.entries.count) entries already in \(outPath)")
    }
    let store = AtmosphereTrackStore(track)
    let cap = SpendCap(dollars: args.string("max-dollars").flatMap(Double.init), prices: prices, usage: usage)
    let started = Date()
    let report = try await builder.build(
        into: store, engine: engine,
        concurrency: args.int("concurrency", default: 4),
        continueIf: { cap.allowsAnother() }
    ) { entry, added in
        if added % 10 == 0 {
            try? store.snapshot.save(to: outURL)
            note("  \(added) scored, now at ch\(entry.chapterOrdinal):s\(entry.sentenceIndex): \(entry.scene)")
        }
    }
    try store.snapshot.save(to: outURL)
    let totals = usage.totals
    note(String(format: "%@ with %@: %d planned, %d already there, %d scored, %d probes, %d failed, %d places, %.0f s",
                book, engine.id, report.planned, report.alreadyScored, report.scored, report.probes, report.failed,
                report.places, Date().timeIntervalSince(started)))
    if report.stoppedEarly {
        note(String(format: "  stopped at --max-dollars %.2f; run again with a higher cap to finish", cap.dollars ?? 0))
    }
    report.failures.prefix(5).forEach { note("  failed \($0)") }
    note(String(format: "  Claude: %d responses, %d input, %d cache-read, %d output tokens, %d retries, %d refusals: about $%.2f at %@",
                totals.responses, totals.inputTokens, totals.cacheReadTokens, totals.outputTokens, totals.retries,
                totals.refusals, prices.dollars(totals), prices.model))
    note("wrote \(outPath)")
}

// MARK: - show

func showCommand(_ args: Arguments) throws {
    guard let path = args.positional.dropFirst().first else { fail(usage) }
    let track = try AtmosphereTrack.load(from: URL(fileURLWithPath: path))
    print("\(track.bookID): \(track.entries.count) entries by \(track.engineID)")
    var previous: StoryScene?
    var previousChapter: Int?
    for entry in track.entries {
        if entry.chapterOrdinal != previousChapter {
            print("-- chapter \(entry.chapterOrdinal)")
            previousChapter = entry.chapterOrdinal
        }
        let same = previous.map { $0.soundsLike(entry.scene) } ?? false
        previous = entry.scene
        guard !same else { continue }
        let cue = entry.scene.cue.map { "  \"\($0)\"" } ?? ""
        let sure = entry.scene.confidence < 0.35 ? " (unsure, ignored)" : ""
        print("s\(entry.sentenceIndex) #\(entry.globalIndex): \(entry.scene)\(sure)\(cue)")
    }
    if args.flag("places") {
        let memory = PlaceMemory(entries: track.entries)
        print("-- places")
        for place in memory.places.values.sorted(by: { Int($0.id.dropFirst()) ?? 0 < Int($1.id.dropFirst()) ?? 0 }) {
            print("\(place.id) \(place.name) (\(place.setting.rawValue)), \(place.visits) visit(s)")
        }
        if let world = memory.world { print("world: \(world)") }
    }
}

// MARK: - synth and library

func synthCommand(_ args: Arguments) throws {
    guard let path = args.positional.dropFirst().first else { fail(usage) }
    let sounds: [AmbientSound]
    if let name = args.string("sound") {
        guard let sound = AmbientSound(lenient: name) else { fail("unknown sound \(name)") }
        sounds = [sound]
    } else {
        sounds = AmbientSound.allCases
    }
    let library = try AmbienceSynth.prepare(
        at: URL(fileURLWithPath: path), sounds: sounds,
        seconds: args.double("seconds", default: 30), sampleRate: args.double("rate", default: 32_000)
    )
    print("wrote \(library.recordings.count) stand-in sounds to \(path)")
}

func libraryCommand(_ args: Arguments) throws {
    guard let path = args.positional.dropFirst().first else { fail(usage) }
    let library = try AmbienceLibrary.load(from: URL(fileURLWithPath: path))
    for sound in AmbientSound.allCases {
        let recordings = library.recordings(of: sound)
        let detail = recordings.map { r in r.loudness.map { String(format: "%@ %.1f LUFS", r.file, $0) } ?? "\(r.file) (unmeasured)" }
        print("\(sound.folderName): \(recordings.isEmpty ? "none" : detail.joined(separator: ", "))")
    }
}

// MARK: - main

let args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.positional.first {
    case "track": try await trackCommand(args)
    case "show": try showCommand(args)
    case "synth": try synthCommand(args)
    case "library": try libraryCommand(args)
    default: fail(usage)
    }
} catch {
    fail("error: \(error)")
}
