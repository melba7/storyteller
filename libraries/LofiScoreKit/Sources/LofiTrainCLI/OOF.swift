#if canImport(NaturalLanguage)
import Foundation
import LofiMood
import LofiScoreCore

// lofi-train oof [--data DIR] [--kind word] [--folds 10] [--repeats 3] [--out FILE] [--old-books FILE]
//     macOS only (reads the feature cache that `lofi-train embed` wrote).
//     Out-of-fold predictions over EVERY labelled book, training and test
//     alike: the books are shuffled into --folds groups, each group is
//     predicted by models trained on the other groups, and this is repeated
//     --repeats times with different shuffles. Each fixed recipe below sees the
//     same folds, so their predictions can be compared window by window
//     (Tools/eval/oof_compare.py) instead of on 320 windows from 8 books.
//     "nested" re-chooses the settings inside every outer fold by an inner
//     5-fold cross-validation, so its score is not inflated by choosing on the
//     very windows it is scored on.
//     --old-books lists (one per line) the books available before the newest
//     batch; the "-old" recipes train only on those, still scored on every
//     held-out window, to measure what the newer books add.
//     --recipes picks recipes by name (Recipes.swift; "nested-exact" too). By
//     default: the baseline, the prior-shift corrections, the soft-label
//     recipes when --alternatives files are given, the people recipes when
//     --people is given, and the "-old" one with --old-books. Nested runs
//     only when named: it trains 50 models per fold.

struct OOFRow: Codable {
    var id: String
    var book: String
    var gold: String
    var repeatIndex: Int
    var recipe: String
    var predicted: String
}

func oofCommand(_ options: Options) throws {
    let dataDir = URL(fileURLWithPath: options.string("data") ?? "Tools/data/work/train", isDirectory: true)
    let kind = options.string("kind") ?? "word"
    let folds = options.int("folds", default: 10)
    let repeats = options.int("repeats", default: 3)
    let out = URL(fileURLWithPath: options.string("out") ?? "Tools/data/work/oof-\(kind).jsonl")
    var oldBooks: Set<String>? = nil
    if let path = options.string("old-books") {
        oldBooks = Set(try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init))
    }

    let pool = try distinctExamples(dataDir.appendingPathComponent("train.json"))
        + ((try? distinctExamples(dataDir.appendingPathComponent("valid.json"))) ?? [])
    let test = try distinctExamples(dataDir.appendingPathComponent("test.json"))
    let all = pool + test
    let earlierText = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: dataDir.appendingPathComponent("earlier.json")))) ?? [:]

    struct Cache: Codable { var features: String; var vectors: [String: [Float]] }
    let cacheURL = dataDir.appendingPathComponent("features-\(kind).json")
    guard let cache = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)) else {
        fail("no feature cache at \(cacheURL.path); run `lofi-train embed --kinds \(kind)` first")
    }
    var examples: [LinearMoodModelSelection.Example] = []
    var meta: [(id: String, book: String)] = []
    for e in all {
        guard let r = cache.vectors[e.id] else { continue }
        let earlier = earlierText[e.id] == nil ? nil : cache.vectors[e.id + "|earlier"].map { $0.map(Double.init) }
        examples.append(.init(group: e.book, label: e.label, recent: r.map(Double.init), earlier: earlier))
        meta.append((e.id, e.book))
    }
    let books = Array(Set(examples.map(\.group))).sorted()
    note("oof: \(examples.count) windows from \(books.count) books (\(test.count) of them from the \(Set(test.map(\.book)).count) test books), \(folds) folds × \(repeats) repeats, features \(cache.features)")
    if let oldBooks { note("old books: \(books.filter { oldBooks.contains($0) }.count) of \(books.count)") }

    let alternativesByID = try alternativeMoods(options.strings("alternatives"))
    var people: PeopleScores? = nil
    if let path = options.string("people") {
        let loaded = try PeopleScores.load(from: URL(fileURLWithPath: path))
        guard loaded.features == cache.features else {
            fail("\(path) was learned on \(loaded.features) features, not \(cache.features)")
        }
        people = loaded
    }
    var recipes: [Recipe]
    var nested = false
    if let names = options.string("recipes") {
        recipes = []
        for name in names.split(separator: ",").map(String.init) {
            if name == "nested-exact" { nested = true; continue }
            guard let r = Recipe.named(name) else {
                fail("unknown recipe \(name); known: \((Recipe.catalog.map(\.name) + ["nested-exact"]).joined(separator: ", "))")
            }
            recipes.append(r)
        }
    } else {
        recipes = Recipe.catalog.filter { r in
            if r.name == Recipe.baseline.name || r.name.hasPrefix("prior-") { return true }
            if r.oldOnly { return oldBooks != nil }
            if r.usesAlternatives { return !alternativesByID.isEmpty && !r.name.contains("prior") }
            if r.usesPeople { return people != nil }
            return false
        }
        if !alternativesByID.isEmpty { recipes += Recipe.catalog.filter { $0.name == "soft-0.3-prior-0.3" } }
    }
    if recipes.contains(where: \.oldOnly), oldBooks == nil { fail("the -old recipes need --old-books") }
    if recipes.contains(where: \.usesPeople), people == nil { fail("the people recipes need --people FILE (lofi-train people)") }
    let alternatives = meta.map { alternativesByID[$0.id] ?? [] }
    if !alternativesByID.isEmpty {
        note("alternatives: \(alternatives.filter { !$0.isEmpty }.count) of \(examples.count) windows have other moods that would also suit them")
    }
    note("recipes: \((recipes.map(\.name) + (nested ? ["nested-exact"] : [])).joined(separator: ", "))")
    let grid = [true, false].flatMap { b in [0.01, 0.03, 0.1, 0.3, 1.0].map { LinearMoodModel.TrainingOptions(l2: $0, iterations: 300, balanced: b) } }
    let weights = [0.0, 0.2, 0.35, 0.5]

    var rows: [OOFRow] = []
    var rng = Mix64(seed: 2026)
    let started = Date()
    for rep in 0..<repeats {
        let shuffled = books.shuffled(using: &rng)
        let foldOf = Dictionary(uniqueKeysWithValues: shuffled.enumerated().map { ($1, $0 % folds) })
        for f in 0..<folds {
            let trainIdx = examples.indices.filter { foldOf[examples[$0].group]! != f }
            let heldIdx = examples.indices.filter { foldOf[examples[$0].group]! == f }
            for recipe in recipes {
                let idx = recipe.oldOnly ? trainIdx.filter { oldBooks!.contains(examples[$0].group) } : trainIdx
                let model = recipe.train(features: cache.features, examples: idx.map { examples[$0] },
                                         alternatives: idx.map { alternatives[$0] }, people: people)
                for i in heldIdx {
                    rows.append(OOFRow(id: meta[i].id, book: meta[i].book, gold: examples[i].label, repeatIndex: rep, recipe: recipe.name,
                                       predicted: LinearMoodModelSelection.predict(model, examples[i], earlierWeight: recipe.earlierWeight)))
                }
            }
            guard nested else {
                note(String(format: "  repeat %d fold %d: %d held-out windows, %.0f s", rep + 1, f + 1, heldIdx.count, Date().timeIntervalSince(started)))
                continue
            }
            // Nested: choose settings on the outer-training books only.
            let inner = trainIdx.map { examples[$0] }
            let candidates = LinearMoodModelSelection.crossValidate(inner, features: cache.features, settings: grid,
                                                                    earlierWeights: weights, folds: 5, criterion: .exact)
            let chosen = LinearMoodModelSelection.best(candidates, by: .exact)!
            let model = LinearMoodModel.train(features: cache.features, x: inner.map(\.recent), labels: inner.map(\.label),
                                              options: .init(l2: chosen.l2, iterations: 300, balanced: chosen.balanced))
            for i in heldIdx {
                rows.append(OOFRow(id: meta[i].id, book: meta[i].book, gold: examples[i].label, repeatIndex: rep, recipe: "nested-exact",
                                   predicted: LinearMoodModelSelection.predict(model, examples[i], earlierWeight: chosen.previousChunkWeight)))
            }
            note(String(format: "  repeat %d fold %d: %d held-out windows; nested chose balanced=%@ l2=%g weight %g (inner exact %.1f%%), %.0f s",
                        rep + 1, f + 1, heldIdx.count, chosen.balanced ? "true" : "false", chosen.l2, chosen.previousChunkWeight,
                        chosen.scores.exact * 100, Date().timeIntervalSince(started)))
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try rows.map { String(data: try encoder.encode($0), encoding: .utf8)! }.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
    for name in recipes.map(\.name) + (nested ? ["nested-exact"] : []) {
        let r = rows.filter { $0.recipe == name }
        let s = AgreementScores(gold: r.map(\.gold), predicted: r.map(\.predicted))
        note("  \(name): \(s.summary) (pooled over \(repeats) repeats)")
    }
    note("wrote \(out.path)")
}

/// SplitMix64, seeded, so the folds repeat exactly.
struct Mix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
