import Foundation
import LofiMood
import LofiScoreCore
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(CoreML)
import CoreML
#endif

// lofi-train embed [--data DIR] [--kinds sentence,word,contextual] [--blend MODEL.mlmodel]
//                  [--version V] [--out-dir Models] [--iterations N] [--all]
//     macOS only (Apple's embeddings). For each kind of on-device embedding,
//     computes features for every exported window (cached in
//     DIR/features-<kind>.json), trains a softmax model on DIR/train.json for
//     a few settings, picks the one that does best on DIR/valid.json (export
//     with --validation-books), and reports it on DIR/test.json. With --blend,
//     also tries averaging its probabilities with a Create ML model's, again
//     choosing the mix on the validation books. Writes the chosen model,
//     retrained on train + valid (+ test with --all), to
//     OUT/LofiMood-embed-<kind>-<V>.json with a .report.json beside it.

struct EmbedReport: Codable {
    struct Trial: Codable {
        var balanced: Bool
        var l2: Double
        var valid: AgreementScores
        var test: AgreementScores
    }
    struct Blend: Codable {
        var embeddingWeight: Double
        var valid: AgreementScores
        var test: AgreementScores
    }
    var kind: String
    var features: String
    var dimension: Int
    var trainExamples: Int
    var validExamples: Int
    var testExamples: Int
    var iterations: Int
    var trials: [Trial]
    var chosen: Trial
    var blendModel: String?
    var blends: [Blend]
    var chosenBlend: Blend?
    var trainedOnTestBooks: Bool
}

func embedCommand(_ options: Options) throws {
    let dataDir = URL(fileURLWithPath: options.string("data") ?? "Tools/data/work/train", isDirectory: true)
    let kinds = (options.string("kinds") ?? "sentence,word,contextual").split(separator: ",").map(String.init)
    let version = options.string("version") ?? "1"
    let outDir = URL(fileURLWithPath: options.string("out-dir") ?? "Models", isDirectory: true)
    let iterations = options.int("iterations", default: 300)
    #if canImport(NaturalLanguage) && canImport(CoreML)
    try embedExperiment(dataDir: dataDir, kinds: kinds, version: version, outDir: outDir, iterations: iterations,
                        blendPath: options.string("blend"), includeTest: options.flag("all"))
    #else
    _ = (dataDir, kinds, version, outDir, iterations)
    fail("embed needs Apple's NaturalLanguage embeddings; run it on the Mac")
    #endif
}

/// Distinct examples by id, in file order (train.json repeats rows when exported with --balance).
func distinctExamples(_ url: URL) throws -> [Example] {
    var seen: Set<String> = []
    return try JSONDecoder().decode([Example].self, from: Data(contentsOf: url)).filter { seen.insert($0.id).inserted }
}

#if canImport(NaturalLanguage) && canImport(CoreML)
struct FeatureCache: Codable {
    var features: String
    var vectors: [String: [Float]]
}

func embedExperiment(dataDir: URL, kinds: [String], version: String, outDir: URL, iterations: Int, blendPath: String?, includeTest: Bool) throws {
    let train = try distinctExamples(dataDir.appendingPathComponent("train.json"))
    let validURL = dataDir.appendingPathComponent("valid.json")
    guard FileManager.default.fileExists(atPath: validURL.path) else {
        fail("no \(validURL.path): export with --validation-books 3 so settings are chosen on books the model never saw")
    }
    let valid = try distinctExamples(validURL)
    let test = try distinctExamples(dataDir.appendingPathComponent("test.json"))
    note("embed: \(train.count) train, \(valid.count) valid, \(test.count) test windows")

    // The Create ML model to blend with, as probabilities per mood name.
    var blendModel: NLModel?
    if let blendPath {
        var url = URL(fileURLWithPath: blendPath)
        if url.pathExtension == "mlmodel" { url = try MLModel.compileModel(at: url) }
        blendModel = try NLModel(contentsOf: url)
    }
    func blendScores(_ text: String) -> [String: Double] {
        guard let blendModel else { return [:] }
        let raw = blendModel.predictedLabelHypotheses(for: text, maximumCount: 32)
        let total = raw.values.reduce(0, +)
        return total > 0 ? raw.mapValues { $0 / total } : raw
    }
    let blendValid = valid.map { blendScores($0.text) }
    let blendTest = test.map { blendScores($0.text) }

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    var summary: [String] = []
    if blendModel != nil {
        let v = AgreementScores(gold: valid.map(\.label), predicted: blendValid.map { argmax($0) })
        let t = AgreementScores(gold: test.map(\.label), predicted: blendTest.map { argmax($0) })
        summary.append("blend model alone: valid \(v.summary) | test \(t.summary)")
    }

    for kindName in kinds {
        guard let kind = TextFeatureKind(rawValue: kindName) else { fail("unknown kind \(kindName); use sentence, word or contextual") }
        let featurizer: TextFeaturizer
        do {
            featurizer = try TextFeaturizer(kind: kind)
        } catch {
            note("\(kindName): skipped (\(error))")
            summary.append("\(kindName): unavailable (\(error))")
            continue
        }

        // Features, cached per featurizer id.
        let cacheURL = dataDir.appendingPathComponent("features-\(kindName).json")
        var cache = (try? JSONDecoder().decode(FeatureCache.self, from: Data(contentsOf: cacheURL))) ?? FeatureCache(features: featurizer.id, vectors: [:])
        if cache.features != featurizer.id { cache = FeatureCache(features: featurizer.id, vectors: [:]) }
        let all = train + valid + test
        let missing = all.filter { cache.vectors[$0.id] == nil }
        if !missing.isEmpty {
            note("\(kindName): computing \(missing.count) feature vectors (\(featurizer.id), \(featurizer.dimension) values each)…")
            let started = Date()
            for (n, example) in missing.enumerated() {
                if let v = try? featurizer.features(for: example.text) { cache.vectors[example.id] = v.map { Float($0) } }
                if (n + 1) % 250 == 0 { note("  \(n + 1)/\(missing.count)") }
            }
            note(String(format: "  %.1f ms per window", Date().timeIntervalSince(started) * 1000 / Double(missing.count)))
            try JSONEncoder().encode(cache).write(to: cacheURL)
        }
        func xy(_ examples: [Example]) -> ([[Double]], [String], [Int]) {
            var x: [[Double]] = [], y: [String] = [], kept: [Int] = []
            for (i, e) in examples.enumerated() {
                guard let v = cache.vectors[e.id] else { continue }
                x.append(v.map { Double($0) }); y.append(e.label); kept.append(i)
            }
            return (x, y, kept)
        }
        let (trX, trY, _) = xy(train)
        let (vaX, vaY, vaKept) = xy(valid)
        let (teX, teY, teKept) = xy(test)
        if vaKept.count < valid.count || teKept.count < test.count {
            note("\(kindName): no features for \(valid.count - vaKept.count) valid and \(test.count - teKept.count) test windows; they are left out")
        }

        var trials: [EmbedReport.Trial] = []
        var models: [LinearMoodModel] = []
        for balanced in [true, false] {
            for l2 in [1e-4, 1e-3, 1e-2, 1e-1] {
                let opts = LinearMoodModel.TrainingOptions(l2: l2, iterations: iterations, balanced: balanced)
                let model = LinearMoodModel.train(features: featurizer.id, x: trX, labels: trY, options: opts)
                let trial = EmbedReport.Trial(
                    balanced: balanced, l2: l2,
                    valid: AgreementScores(gold: vaY, predicted: vaX.map(model.predict)),
                    test: AgreementScores(gold: teY, predicted: teX.map(model.predict))
                )
                note("\(kindName) balanced=\(balanced) l2=\(l2): valid \(trial.valid.summary) | test \(trial.test.summary)")
                trials.append(trial)
                models.append(model)
            }
        }
        let best = trials.indices.max { a, b in
            (trials[a].valid.exact, trials[a].valid.macroF1) < (trials[b].valid.exact, trials[b].valid.macroF1)
        }!
        let chosen = trials[best]
        summary.append("\(kindName) (\(featurizer.id), balanced=\(chosen.balanced), l2=\(chosen.l2)): valid \(chosen.valid.summary) | test \(chosen.test.summary)")

        // Blend with the Create ML model, mix chosen on the validation books.
        var blends: [EmbedReport.Blend] = []
        if blendModel != nil {
            let model = models[best]
            func mixed(_ x: [[Double]], _ kept: [Int], _ other: [[String: Double]], _ a: Double) -> [String] {
                zip(x, kept).map { v, i in
                    var p: [String: Double] = [:]
                    for (name, q) in zip(model.classes, model.probabilities(v)) { p[name, default: 0] += a * q }
                    for (name, q) in other[i] { p[name, default: 0] += (1 - a) * q }
                    return argmax(p)
                }
            }
            for a in [0.25, 0.5, 0.75] {
                let blend = EmbedReport.Blend(
                    embeddingWeight: a,
                    valid: AgreementScores(gold: vaY, predicted: mixed(vaX, vaKept, blendValid, a)),
                    test: AgreementScores(gold: teY, predicted: mixed(teX, teKept, blendTest, a))
                )
                note("\(kindName) blended \(a) with \(blendPath ?? ""): valid \(blend.valid.summary) | test \(blend.test.summary)")
                blends.append(blend)
            }
        }
        let chosenBlend = blends.max { ($0.valid.exact, $0.valid.macroF1) < ($1.valid.exact, $1.valid.macroF1) }
        if let chosenBlend {
            summary.append("  blended \(chosenBlend.embeddingWeight): valid \(chosenBlend.valid.summary) | test \(chosenBlend.test.summary)")
        }

        // The model to keep: the chosen settings, retrained on more books.
        var finalX = trX + vaX, finalY = trY + vaY
        if includeTest { finalX += teX; finalY += teY }
        let finalModel = LinearMoodModel.train(
            features: featurizer.id, x: finalX, labels: finalY,
            options: .init(l2: chosen.l2, iterations: iterations, balanced: chosen.balanced)
        )
        let out = outDir.appendingPathComponent("LofiMood-embed-\(kindName)-\(version).json")
        try finalModel.encoded().write(to: out)
        let report = EmbedReport(
            kind: kindName, features: featurizer.id, dimension: featurizer.dimension,
            trainExamples: trX.count, validExamples: vaX.count, testExamples: teX.count, iterations: iterations,
            trials: trials, chosen: chosen, blendModel: blendPath, blends: blends, chosenBlend: chosenBlend,
            trainedOnTestBooks: includeTest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: out.deletingPathExtension().appendingPathExtension("report.json"))
        note("wrote \(out.path)")
    }

    note("\nsummary (settings chosen on the validation books; test = the 320 held-out windows)")
    summary.forEach { note("  " + $0) }
}

func argmax(_ scores: [String: Double]) -> String {
    scores.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "calm"
}
#endif
