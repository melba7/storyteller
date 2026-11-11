import Foundation
import LofiMood
import LofiScoreCore
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// lofi-train embed [--data DIR] [--kinds word,contextual,word+contextual] [--folds 5]
//                  [--choose exact|kappa|macro-f1] [--version V] [--out-dir Models]
//                  [--iterations N] [--all] [--curve]
//     macOS only (Apple's embeddings). For each kind ("+" puts kinds side by
//     side in one feature vector), computes features for the newest words of
//     every exported window and for the words before them (DIR/earlier.json),
//     cached in DIR/features-<kind>.json. Chooses the training settings, and
//     how much the earlier words count, by cross-validation over whole books:
//     the training books (train.json plus valid.json) are dealt into --folds
//     groups, and each setting is scored on every group by a model trained on
//     the others, reading each window exactly as EmbeddingMoodEngine does.
//     --choose says what "best" means (default exact agreement). Choosing by
//     kappa looked fairer to the rarer moods in cross-validation, but in Mac
//     round 6 its pick scored worse on the held-out books by every measure
//     and named hopeful, cozy and the new moods far more often than the
//     labels do.
//     Then trains on all the training books (and the test books too with
//     --all, for the model that ships), scores DIR/test.json, and writes
//     OUT/LofiMood-embed-<kind>-<V>.json with a .report.json beside it.
//     --curve adds a learning curve (test agreement when training on a
//     quarter, half or three quarters of the books) to show whether more
//     labelled windows would help.
//     --recipe NAME skips the search and trains a fixed recipe from
//     Recipes.swift (the one `lofi-train oof` picked), with its settings,
//     earlier-words weight, prior shift, soft labels (from --alternatives
//     FILE ..., label files with `accept` lists) and lean towards people's
//     ratings (from --people FILE, written by `lofi-train people`). Its
//     cross-validation line then scores the settings and prior shift only.

struct EmbedReport: Codable {
    var kind: String
    var features: String
    var dimension: Int
    var trainBooks: Int
    var trainExamples: Int
    var testExamples: Int
    var folds: Int
    var criterion: String
    var iterations: Int
    var candidates: [LinearMoodModelSelection.Candidate]
    var chosen: LinearMoodModelSelection.Candidate
    /// Agreement on the test books; meaningless when `trainedOnTestBooks`.
    var test: AgreementScores
    var trainedOnTestBooks: Bool
    var curve: [LinearMoodModelSelection.CurvePoint]
    var seconds: Double
}

func embedCommand(_ options: Options) throws {
    let dataDir = URL(fileURLWithPath: options.string("data") ?? "Tools/data/work/train", isDirectory: true)
    let kinds = (options.string("kinds") ?? "word,contextual,word+contextual").split(separator: ",").map(String.init)
    for spec in kinds where TextFeatureKind.kinds(spec: spec) == nil {
        fail("unknown kind \(spec); use sentence, word or contextual, joined with + to combine them")
    }
    let version = options.string("version") ?? "1"
    let outDir = URL(fileURLWithPath: options.string("out-dir") ?? "Models", isDirectory: true)
    let iterations = options.int("iterations", default: 300)
    let folds = options.int("folds", default: 5)
    if folds < 2 { fail("--folds must be 2 or more") }
    let choose = options.string("choose") ?? "exact"
    guard let criterion = LinearMoodModelSelection.Criterion(rawValue: choose) else {
        fail("--choose must be exact, kappa or macro-f1")
    }
    var recipe: Recipe? = nil
    if let name = options.string("recipe") {
        guard let r = Recipe.named(name) else {
            fail("unknown recipe \(name); known: \(Recipe.catalog.map(\.name).joined(separator: ", "))")
        }
        if r.oldOnly { fail("\(name) is for comparisons only") }
        recipe = r
    }
    let alternatives = try alternativeMoods(options.strings("alternatives"))
    var people: PeopleScores? = nil
    if let path = options.string("people") { people = try PeopleScores.load(from: URL(fileURLWithPath: path)) }
    if recipe?.usesPeople == true, people == nil { fail("recipe \(recipe!.name) needs --people FILE (lofi-train people)") }
    if recipe?.usesAlternatives == true, alternatives.isEmpty { fail("recipe \(recipe!.name) needs --alternatives FILE") }
    #if canImport(NaturalLanguage)
    try embedExperiment(dataDir: dataDir, kinds: kinds, version: version, outDir: outDir, iterations: iterations,
                        folds: folds, criterion: criterion, includeTest: options.flag("all"), curve: options.flag("curve"),
                        recipe: recipe, alternatives: alternatives, people: people)
    #else
    _ = (dataDir, version, outDir, iterations, criterion, recipe, alternatives, people)
    fail("embed needs Apple's NaturalLanguage embeddings; run it on the Mac")
    #endif
}

/// Distinct examples by id, in file order (train.json repeats rows when exported with --balance).
func distinctExamples(_ url: URL) throws -> [Example] {
    var seen: Set<String> = []
    return try JSONDecoder().decode([Example].self, from: Data(contentsOf: url)).filter { seen.insert($0.id).inserted }
}

#if canImport(NaturalLanguage)
struct FeatureCache: Codable {
    var features: String
    /// By window id for the newest words, and "<id>|earlier" for the words before them.
    var vectors: [String: [Float]]
}

func embedExperiment(dataDir: URL, kinds: [String], version: String, outDir: URL, iterations: Int,
                     folds: Int, criterion: LinearMoodModelSelection.Criterion, includeTest: Bool, curve: Bool,
                     recipe fixed: Recipe? = nil, alternatives: [String: [String]] = [:], people: PeopleScores? = nil) throws {
    let train = try distinctExamples(dataDir.appendingPathComponent("train.json"))
    let validURL = dataDir.appendingPathComponent("valid.json")
    let valid = FileManager.default.fileExists(atPath: validURL.path) ? try distinctExamples(validURL) : []
    let pool = train + valid  // every training book
    let test = try distinctExamples(dataDir.appendingPathComponent("test.json"))
    let earlierURL = dataDir.appendingPathComponent("earlier.json")
    var earlierText: [String: String] = [:]
    if FileManager.default.fileExists(atPath: earlierURL.path) {
        earlierText = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: earlierURL))
    } else {
        note("no \(earlierURL.path) (export again with this lofi-train): the earlier words are left out")
    }
    let poolBooks = Set(pool.map(\.book)).count
    note("embed: \(pool.count) windows from \(poolBooks) training books, \(test.count) test windows; \(earlierText.count) windows have earlier words")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    var caches: [TextFeatureKind: FeatureCache] = [:]
    var unavailable: Set<TextFeatureKind> = []
    func cache(for kind: TextFeatureKind) throws -> FeatureCache? {
        if let cache = caches[kind] { return cache }
        if unavailable.contains(kind) { return nil }
        let featurizer: TextFeaturizer
        do {
            featurizer = try TextFeaturizer(kind: kind)
        } catch {
            note("\(kind.rawValue): unavailable (\(error))")
            unavailable.insert(kind)
            return nil
        }
        let url = dataDir.appendingPathComponent("features-\(kind.rawValue).json")
        var cache = (try? JSONDecoder().decode(FeatureCache.self, from: Data(contentsOf: url))) ?? FeatureCache(features: featurizer.id, vectors: [:])
        if cache.features != featurizer.id { cache = FeatureCache(features: featurizer.id, vectors: [:]) }
        var jobs: [(key: String, text: String)] = []
        for example in pool + test {
            if cache.vectors[example.id] == nil { jobs.append((example.id, example.text)) }
            let key = example.id + "|earlier"
            if let older = earlierText[example.id], cache.vectors[key] == nil { jobs.append((key, older)) }
        }
        if !jobs.isEmpty {
            note("\(kind.rawValue): computing \(jobs.count) feature vectors (\(featurizer.id), \(featurizer.dimension) values each)…")
            let started = Date()
            for (n, job) in jobs.enumerated() {
                if let v = try? featurizer.features(for: job.text) { cache.vectors[job.key] = v.map { Float($0) } }
                if (n + 1) % 500 == 0 { note("  \(n + 1)/\(jobs.count)") }
            }
            note(String(format: "  %.1f ms per text", Date().timeIntervalSince(started) * 1000 / Double(jobs.count)))
            try JSONEncoder().encode(cache).write(to: url)
        }
        caches[kind] = cache
        return cache
    }

    var summary: [String] = []
    for spec in kinds {
        let parts = TextFeatureKind.kinds(spec: spec)!
        var partCaches: [FeatureCache] = []
        for kind in parts {
            guard let c = try cache(for: kind) else { break }
            partCaches.append(c)
        }
        guard partCaches.count == parts.count else {
            summary.append("\(spec): unavailable on this Mac")
            continue
        }
        let started = Date()
        let featureID = partCaches.map(\.features).joined(separator: "+")
        func vector(_ key: String) -> [Double]? {
            var out: [Double] = []
            for c in partCaches {
                guard let v = c.vectors[key] else { return nil }
                out += v.map { Double($0) }
            }
            return out
        }
        func selectionExamples(_ list: [Example]) -> [(id: String, example: LinearMoodModelSelection.Example)] {
            list.compactMap { e in
                guard let recent = vector(e.id) else { return nil }
                let earlier = earlierText[e.id] == nil ? nil : vector(e.id + "|earlier")
                return (e.id, LinearMoodModelSelection.Example(group: e.book, label: e.label, recent: recent, earlier: earlier))
            }
        }
        let poolPairs = selectionExamples(pool)
        let testPairs = selectionExamples(test)
        let poolX = poolPairs.map(\.example)
        let testX = testPairs.map(\.example)
        if poolX.count < pool.count || testX.count < test.count {
            note("\(spec): no features for \(pool.count - poolX.count) training and \(test.count - testX.count) test windows; they are left out")
        }
        guard let dimension = poolX.first?.recent.count else {
            summary.append("\(spec): no features")
            continue
        }

        // Settings by cross-validation over whole training books (or the fixed recipe's).
        var fixedOptions = fixed?.options
        fixedOptions?.iterations = iterations
        let grid: [LinearMoodModel.TrainingOptions] = [true, false].flatMap { balanced in
            [0.01, 0.03, 0.1, 0.3, 1.0, 3.0].map { LinearMoodModel.TrainingOptions(l2: $0, iterations: iterations, balanced: balanced) }
        }
        let settings: [LinearMoodModel.TrainingOptions] = fixedOptions.map { [$0] } ?? grid
        let earlierWeights: [Double] = fixed.map { [$0.earlierWeight] } ?? [0, 0.2, 0.35, 0.5]
        note("\(spec): \(settings.count) settings × \(folds) folds over \(poolBooks) books, \(dimension) features\(fixed.map { " (recipe \($0.name))" } ?? "")")
        let candidates = LinearMoodModelSelection.crossValidate(
            poolX, features: featureID, settings: settings, earlierWeights: earlierWeights, folds: folds, criterion: criterion
        ) { note("  \(spec) " + $0) }
        let chosen = LinearMoodModelSelection.best(candidates, by: criterion)!
        var recipe = fixed ?? Recipe(name: "chosen", options: .init(l2: chosen.l2, iterations: iterations, balanced: chosen.balanced),
                                     earlierWeight: chosen.previousChunkWeight)
        recipe.options.iterations = iterations
        let options = recipe.options
        if recipe.usesPeople, let people, people.features != featureID {
            fail("the --people file was learned on \(people.features) features, not \(featureID)")
        }

        // The model to keep: chosen settings, trained on every training book (and the test books with --all).
        let finalPairs = includeTest ? poolPairs + testPairs : poolPairs
        let finalX = finalPairs.map(\.example)
        let model = recipe.train(features: featureID, examples: finalX,
                                 alternatives: finalPairs.map { alternatives[$0.id] ?? [] }, people: people)
        let testScores = AgreementScores(
            gold: testX.map(\.label),
            predicted: testX.map { LinearMoodModelSelection.predict(model, $0, earlierWeight: chosen.previousChunkWeight) }
        )
        let settingsText = fixed.map { "recipe \($0.name)" } ?? "best \(criterion.rawValue): balanced=\(chosen.balanced), l2=\(chosen.l2), earlier words weight \(chosen.previousChunkWeight)"
        summary.append("\(spec) (\(featureID), \(dimension) features; \(settingsText))")
        summary.append("  cross-validated on \(poolBooks) training books: \(chosen.scores.summary)")
        summary.append("  test\(includeTest ? " (trained on these books too, so not a fair score)" : ""): \(testScores.summary)")

        var points: [LinearMoodModelSelection.CurvePoint] = []
        if curve && !includeTest {
            let counts = Array(Set([poolBooks / 4, poolBooks / 2, 3 * poolBooks / 4, poolBooks].filter { $0 >= 2 })).sorted()
            points = LinearMoodModelSelection.learningCurve(
                train: poolX, test: testX, features: featureID, options: options,
                earlierWeight: chosen.previousChunkWeight, bookCounts: counts, repeats: 4
            )
            for p in points {
                summary.append(String(format: "  learning curve: %d books (%.0f windows): test exact %.1f%%, kappa %.3f", p.books, p.examples, p.exact * 100, p.kappa))
            }
        }

        let out = outDir.appendingPathComponent("LofiMood-embed-\(spec)-\(version).json")
        try model.encoded().write(to: out)
        let report = EmbedReport(
            kind: spec, features: featureID, dimension: dimension,
            trainBooks: poolBooks, trainExamples: poolX.count, testExamples: testX.count, folds: folds,
            criterion: criterion.rawValue, iterations: iterations,
            candidates: candidates, chosen: chosen, test: testScores, trainedOnTestBooks: includeTest, curve: points,
            seconds: Date().timeIntervalSince(started)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: out.deletingPathExtension().appendingPathExtension("report.json"))
        note("wrote \(out.path) (\(Int(report.seconds)) s)")
    }

    note("\nsummary (settings chosen by \(criterion.rawValue) in cross-validation over the training books; test = the held-out books)")
    summary.forEach { note("  " + $0) }
}
#endif
