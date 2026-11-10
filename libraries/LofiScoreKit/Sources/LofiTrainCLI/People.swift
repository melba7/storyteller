#if canImport(NaturalLanguage)
import Foundation
import LofiMood
import LofiScoreCore

// lofi-train people --in people.jsonl [--kind word] [--out Tools/data/work/people-word.json]
//     macOS only. people.jsonl comes from `Tools/eval/emobank.py people FOLDER`:
//     every EmoBank sentence with its document, genre and mean ratings (1 to
//     5). Learns how pleasant (valence) and how energetic (arousal) people
//     rate a text, by ridge regression on Apple's word-embedding features of
//     the NON-fiction sentences only: the fiction sentences are the test in
//     `emobank.py score`, so they never train anything. The penalty is chosen
//     by 5-fold cross-validation over whole documents. Reports the
//     correlation on held-out documents and on the fiction sentences, and
//     writes PeopleScores for the "people" recipes (Recipes.swift), which
//     lean the moods towards these ratings. EmoBank is CC BY-SA 4.0: a model
//     leaned this way carries its attribution (Docs/MoodDetection.md).

struct PeopleRow: Decodable {
    var id: String
    var doc: String
    var category: String
    var v: Double
    var a: Double
    var text: String
}

func pearson(_ x: [Double], _ y: [Double]) -> Double {
    let n = Double(x.count)
    guard n > 1 else { return 0 }
    let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
    var sxy = 0.0, sxx = 0.0, syy = 0.0
    for (a, b) in zip(x, y) {
        sxy += (a - mx) * (b - my)
        sxx += (a - mx) * (a - mx)
        syy += (b - my) * (b - my)
    }
    return sxx > 0 && syy > 0 ? sxy / sqrt(sxx * syy) : 0
}

func peopleCommand(_ options: Options) throws {
    guard let input = options.string("in") else { fail("give --in people.jsonl (from Tools/eval/emobank.py people FOLDER)") }
    let kindName = options.string("kind") ?? "word"
    guard let kind = TextFeatureKind(rawValue: kindName) else { fail("unknown kind \(kindName)") }
    let out = URL(fileURLWithPath: options.string("out") ?? "Tools/data/work/people-\(kind.rawValue).json")
    let rows = try readLines(PeopleRow.self, path: input)
    let featurizer = try TextFeaturizer(kind: kind)
    var x: [[Double]] = []
    var kept: [PeopleRow] = []
    for row in rows {
        guard let v = try? featurizer.features(for: row.text) else { continue }
        x.append(v)
        kept.append(row)
    }
    let train = kept.indices.filter { kept[$0].category != "fiction" }
    let fiction = kept.indices.filter { kept[$0].category == "fiction" }
    note("people: \(kept.count) of \(rows.count) sentences have features (\(featurizer.id)); learning on \(train.count) non-fiction, checking on \(fiction.count) fiction")
    guard train.count > 100 else { fail("too few non-fiction sentences in \(input)") }

    var rng = Mix64(seed: 11)
    let docs = Array(Set(train.map { kept[$0].doc })).sorted().shuffled(using: &rng)
    let foldOf = Dictionary(uniqueKeysWithValues: docs.enumerated().map { ($1, $0 % 5) })
    let penalties = [0.01, 0.03, 0.1, 0.3, 1.0, 3.0]

    func fit(_ name: String, _ target: (PeopleRow) -> Double) -> LinearScore {
        var best: (l2: Double, r: Double) = (penalties[0], -2)
        for l2 in penalties {
            var predicted = [Double](repeating: 0, count: kept.count)
            for f in 0..<5 {
                let fitIdx = train.filter { foldOf[kept[$0].doc]! != f }
                let score = LinearScore.ridge(features: featurizer.id, x: fitIdx.map { x[$0] }, y: fitIdx.map { target(kept[$0]) }, l2: l2)
                for i in train where foldOf[kept[i].doc]! == f { predicted[i] = score.score(x[i]) }
            }
            let r = pearson(train.map { predicted[$0] }, train.map { target(kept[$0]) })
            note(String(format: "  %@ l2=%g: r %.3f on held-out documents", name, l2, r))
            if r > best.r { best = (l2, r) }
        }
        let score = LinearScore.ridge(features: featurizer.id, x: train.map { x[$0] }, y: train.map { target(kept[$0]) }, l2: best.l2)
        let rf = pearson(fiction.map { score.score(x[$0]) }, fiction.map { target(kept[$0]) })
        note(String(format: "%@: l2 %g, r %.3f on held-out non-fiction documents, r %.3f on the %d fiction sentences (never trained on)",
                    name, best.l2, best.r, rf, fiction.count))
        return score
    }
    let valence = fit("valence", \.v)
    let arousal = fit("arousal", \.a)
    let scores = PeopleScores(
        features: featurizer.id, valence: valence, arousal: arousal,
        source: "EmoBank (JULIELab, CC BY-SA 4.0): mean reader ratings of \(train.count) non-fiction sentences"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(scores).write(to: out)
    note("wrote \(out.path)")
}
#endif
