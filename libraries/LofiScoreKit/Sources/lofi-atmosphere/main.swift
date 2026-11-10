import Foundation
import LofiAtmosphere
import LofiMood
import LofiPlaceholders
import LofiText

// lofi-atmosphere: score a book's atmosphere track with Claude, print a track's scenes,
// combine it with the mood track into a book score, write the synthesised stand-in
// sounds, or check a sounds folder.

let usage = """
    usage:
      lofi-atmosphere track EPUB-DIR --book NAME --out FILE [--model claude-opus-5-5] [--effort low]
                      [--max-dollars D] [--words 250] [--probe-budget 0.5] [--resolution 3] [--concurrency 4]
                      [--variants Atmosphere/variants.json]
      lofi-atmosphere track EPUB-DIR --book NAME --dry-run [--variants FILE]
      lofi-atmosphere show FILE [--places]
      lofi-atmosphere score --out FILE [--mood TRACK.track.json] [--atmosphere TRACK.atmosphere.json]
      lofi-atmosphere synth FOLDER [--seconds 30] [--rate 32000] [--sound rain]
      lofi-atmosphere library FOLDER [--edition personal|publish]
      lofi-atmosphere catalog [--out Tools/atmosphere/catalog.json] [--prompt]

    The built-in catalogue (every sound family, its more specific kinds and the place guide) is
    always offered to Claude. --variants adds the Mac's catalog of other books' requests. catalog
    writes the catalogue as JSON for the fetch script (--prompt prints the system prompt instead).

    Claude is reached like lofi-eval: LOFI_CLAUDE_VIA=api uses the Anthropic API with the key from
    ANTHROPIC_API_KEY, or the file named by ANTHROPIC_API_KEY_FILE (never printed); LOFI_CLAUDE_VIA=plan
    runs each request through Claude Code (`claude -p`, or LOFI_CLAUDE_CODE) on its signed-in plan.
    Unset, the API is used when a key is set and the plan otherwise.
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
    static let flagNames: Set<String> = ["dry-run", "places", "prompt"]

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

func apiKey() -> String? {
    let env = ProcessInfo.processInfo.environment
    if let key = env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    if let path = env["ANTHROPIC_API_KEY_FILE"], !path.isEmpty,
       let key = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    return nil
}

/// How requests reach Claude: the same LOFI_CLAUDE_VIA convention as lofi-eval.
func claudeTransport() -> (apiKey: String, transport: any HTTPTransport, via: String) {
    let env = ProcessInfo.processInfo.environment
    let plan: () -> (String, any HTTPTransport, String) = {
        #if os(macOS) || os(Linux)
        let executable = env["LOFI_CLAUDE_CODE"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
        return ("claude-code", ClaudeCodeTransport(executable: executable), "plan")
        #else
        fail("the plan route needs macOS or Linux")
        #endif
    }
    switch env["LOFI_CLAUDE_VIA"]?.lowercased() {
    case "api":
        guard let key = apiKey() else { fail("set ANTHROPIC_API_KEY, or ANTHROPIC_API_KEY_FILE to a file holding the key") }
        return (key, URLSessionTransport(), "api")
    case "plan", "claude-code", "subscription":
        return plan()
    case nil, "":
        if let key = apiKey() { return (key, URLSessionTransport(), "api") }
        return plan()
    case let other?:
        fail("LOFI_CLAUDE_VIA must be api or plan, not \(other)")
    }
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
    var offered: [SoundVariant] = []
    if let path = args.string("variants") {
        if FileManager.default.fileExists(atPath: path) {
            do {
                offered = try SoundVariantCatalog.load(from: URL(fileURLWithPath: path)).offered(toBook: book)
            } catch {
                fail("could not read \(path): \(error)")
            }
        } else {
            note("no variants catalog at \(path) yet; Claude gets the built-in catalogue and the variants it asks for")
        }
    }
    let builder = AtmosphereTrackBuilder(spoilerGuard: spoilerGuard, plan: plan, offeredVariants: offered)
    offered = builder.offeredVariants

    if args.flag("dry-run") {
        let all = try builder.narratedPositions()
        let positions = try builder.scoringPositions(all)
        var passageWords = 0
        for position in positions {
            passageWords += min(400, try spoilerGuard.window(at: position).wordCount)
        }
        let probes = plan.refinement?.maxProbes(planned: positions.count) ?? 0
        // Checks of one-off sounds found before a passage's last sentence: few in practice.
        let cueChecks = Int((Double(positions.count) * plan.oneShotCheckBudget * 0.25).rounded(.up))
        let requests = positions.count + probes + cueChecks
        let averageWords = Double(passageWords) / Double(max(1, positions.count))
        // Passage at ~1.35 tokens a word, plus ~500 for the place list and framing;
        // the system prompt (the catalogue and the place guide, about four characters a
        // token) is read from the cache after the first request.
        let input = Int(Double(requests) * (averageWords * 1.35 + 500))
        let systemTokens = ClaudeScenePrompt.system(sharedVariants: offered).count / 4
        let cached = requests * systemTokens
        let output = requests * 450
        note("\(book): \(all.count) narrated sentences, \(positions.count) entries (one per ~\(plan.wordsBetweenEntries) words plus one per chapter), up to \(probes) probes, \(offered.count) specific sounds offered (\(SoundCatalog.variants.count) built in), system prompt ~\(systemTokens) tokens")
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
    let route = claudeTransport()
    let engine = ClaudeSceneEngine(
        apiKey: route.apiKey,
        configuration: .init(model: prices.model, effort: args.string("effort") ?? "low", sharedVariants: offered),
        usage: usage,
        transport: route.transport
    )
    note("\(book): \(engine.id) via the \(route.via == "plan" ? "Claude plan (Claude Code)" : "Anthropic API")")
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
    let shared = Set(offered.map(\.id))
    let asked = store.snapshot.variants.filter { !shared.contains($0.id) }
    note("  more specific sounds: \(report.variants) used, \(asked.count) new" + (asked.isEmpty ? "" : ": " + asked.map { "\($0.id) (\($0.of.rawValue))" }.joined(separator: ", ")))
    let cueCounts = Dictionary(grouping: store.snapshot.cues, by: \.sound).map { "\($0.value.count) \($0.key.rawValue)" }.sorted()
    note("  one-off sounds: \(report.cues)" + (cueCounts.isEmpty ? "" : " (" + cueCounts.joined(separator: ", ") + ")")
        + ", \(report.cueChecks) checked on their own sentence, \(report.cuesRejected) not confirmed")
    if report.stoppedEarly {
        note(String(format: "  stopped at --max-dollars %.2f; run again with a higher cap to finish", cap.dollars ?? 0))
    }
    report.failures.prefix(5).forEach { note("  failed \($0)") }
    note(String(format: "  Claude: %d responses, %d input, %d cache-read, %d output tokens, %d retries, %d refusals: about $%.2f at %@ list prices",
                totals.responses, totals.inputTokens, totals.cacheReadTokens, totals.outputTokens, totals.retries,
                totals.refusals, prices.dollars(totals), prices.model))
    note("wrote \(outPath)")
}

// MARK: - show

func showCommand(_ args: Arguments) throws {
    guard let path = args.positional.dropFirst().first else { fail(usage) }
    let track = try AtmosphereTrack.load(from: URL(fileURLWithPath: path))
    print("\(track.bookID): \(track.entries.count) entries by \(track.engineID)")
    for variant in track.variants {
        print("variant \(variant.id), a kind of \(variant.of.rawValue), from #\(variant.firstIndex ?? 0): \(variant.about) [search: \(variant.search)]")
    }
    var previous: StoryScene?
    var previousChapter: Int?
    var cues = track.cues[...]
    for entry in track.entries {
        while let cue = cues.first, cue.globalIndex < entry.globalIndex {
            cues = cues.dropFirst()
            print("   #\(cue.globalIndex): one-off \(cue.sound.rawValue)" + (cue.quote.map { "  \"\($0)\"" } ?? ""))
        }
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
    for cue in cues {
        print("   #\(cue.globalIndex): one-off \(cue.sound.rawValue)" + (cue.quote.map { "  \"\($0)\"" } ?? ""))
    }
    if args.flag("places") {
        let memory = PlaceMemory(entries: track.entries)
        print("-- places")
        for place in memory.places.values.sorted(by: { Int($0.id.dropFirst()) ?? 0 < Int($1.id.dropFirst()) ?? 0 }) {
            let state = place.state.map { ", \($0)" } ?? ""
            print("\(place.id) \(place.name) (\(place.setting.rawValue)\(state)), \(place.visits) visit(s)")
        }
        if let world = memory.world { print("world: \(world)") }
    }
}

// MARK: - score

/// Writes a book score, format 1: `{"format":1,"mood":…,"atmosphere":…}`, the file that can
/// travel inside the read-aloud EPUB at META-INF/storyteller-lofi/score.json.
func scoreCommand(_ args: Arguments) throws {
    guard let outPath = args.string("out") else { fail("give --out FILE\n\(usage)") }
    var object: [String: Any] = ["format": 1]
    if let path = args.string("mood") {
        object["mood"] = try JSONSerialization.jsonObject(with: MoodTrack.load(from: URL(fileURLWithPath: path)).encoded())
    }
    if let path = args.string("atmosphere") {
        object["atmosphere"] = try JSONSerialization.jsonObject(with: AtmosphereTrack.load(from: URL(fileURLWithPath: path)).encoded())
    }
    guard object.count > 1 else { fail("give --mood, --atmosphere or both\n\(usage)") }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
    note("wrote \(outPath) with \(object.keys.filter { $0 != "format" }.sorted().joined(separator: " and "))")
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
    let editionName = args.string("edition") ?? SoundEdition.personal.rawValue
    guard let edition = SoundEdition(rawValue: editionName) else { fail("--edition is personal or publish") }
    let library = try AmbienceLibrary.load(from: URL(fileURLWithPath: path), edition: edition)
    func describe(_ recordings: [AmbienceRecording]) -> String {
        guard !recordings.isEmpty else { return "none" }
        return recordings.map { r in
            let level = r.loudness.map { String(format: " %.1f LUFS", $0) } ?? " (unmeasured)"
            let use = r.isPersonalUseOnly ? " [personal use]" : r.isPublishStandBy ? " [publishing stand-by]" : ""
            return r.file + level + use
        }.joined(separator: ", ")
    }
    print("\(edition.rawValue) edition")
    for sound in AmbientSound.allCases {
        print("\(sound.folderName): \(describe(library.recordings(of: sound)))")
    }
    for key in library.variants.sorted() {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard let sound = AmbientSound(rawValue: parts[0]) else { continue }
        print("\(SoundVariant.folderName(of: sound, id: parts[1])): \(describe(library.recordings(of: sound, variant: parts[1])))")
    }
    let oneShots = try OneShotLibrary.load(
        from: URL(fileURLWithPath: path).appendingPathComponent(OneShotLibrary.folderName), edition: edition
    )
    print("-- one-off sounds (\(OneShotLibrary.folderName)/)")
    for sound in OneShotSound.allCases {
        let recordings = oneShots.recordings(of: sound)
        let text = recordings.isEmpty ? "none" : recordings.map { r in
            let level = r.loudness.map { String(format: " %.1f LUFS", $0) } ?? " (unmeasured)"
            let use = r.isPersonalUseOnly ? " [personal use]" : r.isPublishStandBy ? " [publishing stand-by]" : ""
            return r.file + level + use
        }.joined(separator: ", ")
        print("\(sound.folderName): \(text)")
    }
}

// MARK: - catalog

func catalogCommand(_ args: Arguments) throws {
    if args.flag("prompt") {
        print(ClaudeScenePrompt.system)
        return
    }
    let data = try SoundCatalog.export()
    if let out = args.string("out") {
        try data.write(to: URL(fileURLWithPath: out), options: .atomic)
        note("wrote \(AmbientSound.allCases.count) sounds, \(SoundCatalog.variants.count) specific sounds, \(OneShotSound.allCases.count) one-off sounds and \(SoundCatalog.placeGuide.count) place guides to \(out)")
    } else {
        print(String(decoding: data, as: UTF8.self))
    }
}

// MARK: - main

let args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.positional.first {
    case "track": try await trackCommand(args)
    case "show": try showCommand(args)
    case "score": try scoreCommand(args)
    case "synth": try synthCommand(args)
    case "library": try libraryCommand(args)
    case "catalog": try catalogCommand(args)
    default: fail(usage)
    }
} catch {
    fail("error: \(error)")
}
