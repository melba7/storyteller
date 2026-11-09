import Foundation
import LofiMood
import LofiScoreCore
import LofiText

// MARK: - track

func trackCommand(_ args: Arguments) async throws {
    let (guardian, book) = try openBook(args)
    let budget = args.double("refine-budget", default: 0.6)
    let refinement = budget > 0
        ? MoodTrackBuilder.Refinement(resolutionSentences: args.int("resolution", default: 3), probeBudget: budget)
        : nil
    let plan = MoodTrackBuilder.Plan(wordsBetweenEntries: args.int("words", default: 250), refinement: refinement)
    let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: plan)
    let chapters = args.range("chapters")

    if args.flag("dry-run") {
        let positions = try builder.scoringPositions(chapters: chapters)
        var passageWords = 0
        for position in positions {
            passageWords += min(400, try guardian.window(at: position).wordCount)
        }
        let estimate = ClaudeCostEstimate(requests: positions.count, passageWords: passageWords)
        let probes = refinement?.maxProbes(planned: positions.count) ?? 0
        // Probes are windows of the same size as entries.
        let withProbes = ClaudeCostEstimate(
            requests: positions.count + probes,
            passageWords: passageWords + Int(Double(passageWords) * Double(probes) / Double(max(1, positions.count)))
        )
        note("\(book): \(positions.count) track entries (one per ~\(plan.wordsBetweenEntries) words plus one per chapter)")
        if let refinement {
            note("  plus up to \(probes) probes to pin mood changes to \(refinement.resolutionSentences) sentences (--refine-budget \(refinement.probeBudget))")
        }
        for model in ClaudePrices.known {
            var line = String(format: "  %@: about $%.2f (%.0fk input, %.0fk output tokens; estimate)",
                              model.name, estimate.dollars(model), estimate.inputTokens / 1000, estimate.outputTokens / 1000)
            if probes > 0 { line += String(format: ", at most $%.2f with probes", withProbes.dollars(model)) }
            note(line)
        }
        return
    }

    guard let name = args.string("engine") else { fail("give --engine\n\(usage)") }
    guard let outPath = args.string("out") else { fail("give --out FILE for the track\n\(usage)") }
    let engine = try EngineFactory.make(name)
    let outURL = URL(fileURLWithPath: outPath)

    var track = MoodTrack(engineID: engine.id, bookID: book, wordsBetweenEntries: plan.wordsBetweenEntries)
    if FileManager.default.fileExists(atPath: outPath) {
        let existing = try MoodTrack.decode(Data(contentsOf: outURL))
        guard existing.engineID == engine.id else {
            fail("\(outPath) was made by \(existing.engineID), not \(engine.id); use another --out")
        }
        track = existing
        note("resuming: \(existing.entries.count) entries already in \(outPath)")
    }
    let store = MoodTrackStore(track)
    let started = now()
    let saveEvery = 20
    let cap = SpendCap(args)
    let report = try await builder.build(
        into: store, engine: engine, chapters: chapters,
        concurrency: args.int("concurrency", default: 4),
        continueIf: { cap.allows(1) }
    ) { _, added in
        if added % saveEvery == 0 {
            try? store.snapshot.encoded().write(to: outURL, options: .atomic)
            note("  \(added) scored")
        }
    }
    try store.snapshot.encoded().write(to: outURL, options: .atomic)

    let entries = store.snapshot.entries
    let counts = Dictionary(grouping: entries, by: { $0.reading.bucket.rawValue }).mapValues(\.count)
    note(String(format: "%@ with %@: %d planned, %d already there, %d scored, %d failed, %.0f s",
                book, engine.id, report.planned, report.alreadyScored, report.scored, report.failed, now() - started))
    if report.stoppedEarly {
        note(String(format: "  stopped at --max-dollars %.2f (about $%.2f spent); run again with a higher cap to finish", cap.dollars ?? 0, cap.spent))
    }
    if plan.refinement != nil {
        note("  refinement: \(report.probes) probes this run, \(report.earlierProbes) earlier, budget \(report.probeBudget); \(report.unrefinedChanges) changes left wider than the resolution")
    }
    note("  moods: " + counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    report.failures.prefix(5).forEach { note("  failed \($0)") }
    note("wrote \(outPath)")
    reportClaudeUsage()
}

// MARK: - Claude cost

/// Stops a paid run before it spends more than `--max-dollars` at list prices.
/// It checks before each new request, using the average cost so far (or a
/// cautious guess before the first answer), so a run ends a little under the
/// cap rather than over it.
struct SpendCap: Sendable {
    let dollars: Double?
    let prices: ClaudePrices?

    init(_ args: Arguments) {
        guard let raw = args.string("max-dollars") else {
            dollars = nil
            prices = nil
            return
        }
        guard let cap = Double(raw), cap >= 0 else { fail("--max-dollars expects a number, got \(raw)") }
        guard let model = lastClaudeModel(), let prices = ClaudePrices.forModel(model) else {
            fail("--max-dollars needs a claude engine with a known price")
        }
        dollars = cap
        self.prices = prices
    }

    var spent: Double {
        guard let prices else { return 0 }
        let t = EngineFactory.claudeUsage.totals
        return prices.dollars(
            input: Double(t.inputTokens), output: Double(t.outputTokens),
            cacheRead: Double(t.cacheReadTokens), cacheWrite: Double(t.cacheWriteTokens)
        )
    }

    /// Whether `requests` more requests fit under the cap.
    func allows(_ requests: Int) -> Bool {
        guard let dollars, let prices else { return true }
        let responses = EngineFactory.claudeUsage.totals.responses
        // Before any answer: a long window with plenty of thinking.
        let perRequest = responses > 0 ? spent / Double(responses) : prices.dollars(input: 2_000, output: 600)
        return spent + perRequest * Double(requests) <= dollars
    }
}

/// Anthropic list prices in dollars per million tokens, from the Claude API
/// reference cached on 2026-10-06. Check the pricing page before relying on them.
struct ClaudePrices {
    let name: String
    let input: Double
    let output: Double
    let cacheRead: Double

    static let known = [
        ClaudePrices(name: "claude-opus-5-5", input: 4, output: 20, cacheRead: 0.20),
        ClaudePrices(name: "claude-sonnet-5-5", input: 2, output: 10, cacheRead: 0.20),
        ClaudePrices(name: "claude-haiku-5-5", input: 0.10, output: 0.50, cacheRead: 0.01),
    ]

    static func forModel(_ model: String) -> ClaudePrices? {
        known.first { model.hasPrefix($0.name) }
    }

    func dollars(input: Double, output: Double, cacheRead: Double = 0, cacheWrite: Double = 0) -> Double {
        (input * self.input + output * self.output + cacheRead * self.cacheRead + cacheWrite * self.input * 1.25) / 1_000_000
    }
}

/// Rough token counts for scoring `requests` windows: the system prompt
/// (~1,000 tokens with the schema since prompt v2's eleven moods), ~1.4
/// tokens per passage word, and ~250 output tokens of thinking plus the JSON
/// answer at low effort. Too short to be cached, so no cache discount.
struct ClaudeCostEstimate {
    let inputTokens: Double
    let outputTokens: Double

    init(requests: Int, passageWords: Int) {
        inputTokens = Double(requests) * 1_000 + Double(passageWords) * 1.4
        outputTokens = Double(requests) * 250
    }

    func dollars(_ prices: ClaudePrices) -> Double {
        prices.dollars(input: inputTokens, output: outputTokens)
    }
}

/// Prints what the Claude engines used in this process, and its list-price cost.
func reportClaudeUsage() {
    let t = EngineFactory.claudeUsage.totals
    guard t.responses > 0 || t.retries > 0 else { return }
    var line = "  claude usage: \(t.responses) responses, \(t.inputTokens) input + \(t.outputTokens) output tokens"
    if t.cacheReadTokens + t.cacheWriteTokens > 0 {
        line += ", cache \(t.cacheReadTokens) read / \(t.cacheWriteTokens) written"
    }
    line += ", \(t.retries) retries, \(t.refusals) refusals"
    if t.otherModel > 0 { line += ", \(t.otherModel) served by a fallback model" }
    note(line)
    if let model = ProcessInfo.processInfo.environment["LOFI_CLAUDE_PRICE_MODEL"] ?? lastClaudeModel(),
       let prices = ClaudePrices.forModel(model) {
        let cost = prices.dollars(
            input: Double(t.inputTokens), output: Double(t.outputTokens),
            cacheRead: Double(t.cacheReadTokens), cacheWrite: Double(t.cacheWriteTokens)
        )
        note(String(format: "  about $%.3f at %@ list prices ($%.4f per response)", cost, prices.name, cost / Double(max(1, t.responses))))
    }
}

/// The model of the Claude engine named on the command line, if any.
func lastClaudeModel() -> String? {
    guard let name = args.string("engine"), name.hasPrefix("claude") else { return nil }
    guard let colon = name.firstIndex(of: ":") else { return "claude-opus-5-5" }
    let model = String(name[name.index(after: colon)...])
    return model.hasPrefix("claude-") ? model : "claude-" + model
}
