import Foundation

/// Choosing a `LinearMoodModel`'s settings by cross-validation over whole
/// books, scored the way `EmbeddingMoodEngine` reads a window: the newest
/// words, mixed with the words before them at some weight.
///
/// A handful of validation books gives noisy choices (one setting swung five
/// points between neighbouring values on three books), so every training book
/// takes a turn as held-out data instead.
public enum LinearMoodModelSelection {
    public struct Example: Sendable {
        /// The book: examples from one book always land in the same fold.
        public var group: String
        public var label: String
        /// Features of the newest words.
        public var recent: [Double]
        /// Features of the words before them, when there are enough of them.
        public var earlier: [Double]?

        public init(group: String, label: String, recent: [Double], earlier: [Double]? = nil) {
            self.group = group
            self.label = label
            self.recent = recent
            self.earlier = earlier
        }
    }

    public struct Candidate: Codable, Sendable, Equatable {
        public var balanced: Bool
        public var l2: Double
        public var previousChunkWeight: Double
        /// Out-of-fold agreement over every training example.
        public var scores: AgreementScores
    }

    /// What "best" means when choosing among candidates.
    public enum Criterion: String, CaseIterable, Codable, Sendable {
        /// Exact agreement, then kappa. The default: in Mac round 6 the
        /// kappa pick (class-weighted) did worse on the held-out books by
        /// every measure, and named the rarer moods far too often.
        case exact
        /// Cohen's kappa, then exact.
        case kappa
        /// Macro-F1 (every mood counts equally), then kappa.
        case macroF1 = "macro-f1"

        func key(_ s: AgreementScores) -> (Double, Double) {
            switch self {
            case .kappa: (s.kappa, s.exact)
            case .exact: (s.exact, s.kappa)
            case .macroF1: (s.macroF1, s.kappa)
            }
        }
    }

    public struct CurvePoint: Codable, Sendable, Equatable {
        public var books: Int
        /// Mean training examples over the repeats.
        public var examples: Double
        /// Mean test agreement over the repeats.
        public var exact: Double
        public var kappa: Double
    }

    /// The fold of each example: the distinct groups, sorted, are dealt round
    /// robin into `count` folds (fewer if there are fewer groups).
    public static func folds(groups: [String], count: Int) -> [Int] {
        let distinct = Array(Set(groups)).sorted()
        let k = max(1, min(count, distinct.count))
        let fold = Dictionary(uniqueKeysWithValues: distinct.enumerated().map { ($1, $0 % k) })
        return groups.map { fold[$0]! }
    }

    /// The mood the engine would pick for this example.
    public static func predict(_ model: LinearMoodModel, _ example: Example, earlierWeight: Double) -> String {
        let p = model.probabilities(recent: example.recent, earlier: example.earlier, earlierWeight: earlierWeight)
        return model.classes[argmax(p)]
    }

    /// Out-of-fold scores for every training setting and earlier-words weight.
    /// Each setting trains one model per fold; the weights reuse its probabilities.
    public static func crossValidate(
        _ examples: [Example],
        features: String,
        settings: [LinearMoodModel.TrainingOptions],
        earlierWeights: [Double],
        folds count: Int,
        criterion: Criterion = .exact,
        progress: ((String) -> Void)? = nil
    ) -> [Candidate] {
        guard !examples.isEmpty else { return [] }
        let fold = folds(groups: examples.map(\.group), count: count)
        let foldCount = Set(fold).count
        let gold = examples.map(\.label)
        let classes = Array(Set(gold)).sorted()
        let classIndex = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        // A fold's model may lack a mood that only its held-out books have.
        func spread(_ p: [Double], _ model: LinearMoodModel) -> [Double] {
            var out = [Double](repeating: 0, count: classes.count)
            for (name, q) in zip(model.classes, p) { out[classIndex[name]!] = q }
            return out
        }

        var candidates: [Candidate] = []
        for options in settings {
            var recentP = [[Double]](repeating: [], count: examples.count)
            var earlierP = [[Double]?](repeating: nil, count: examples.count)
            for f in 0..<foldCount {
                let trainIndexes = examples.indices.filter { fold[$0] != f }
                guard !trainIndexes.isEmpty else { continue }
                let model = LinearMoodModel.train(
                    features: features,
                    x: trainIndexes.map { examples[$0].recent },
                    labels: trainIndexes.map { examples[$0].label },
                    options: options
                )
                for i in examples.indices where fold[i] == f {
                    recentP[i] = spread(model.probabilities(examples[i].recent), model)
                    if let earlier = examples[i].earlier { earlierP[i] = spread(model.probabilities(earlier), model) }
                }
            }
            var best: Candidate?
            for weight in earlierWeights {
                let predicted = examples.indices.map { i -> String in
                    guard !recentP[i].isEmpty else { return "" }
                    var p = recentP[i]
                    if weight > 0, let q = earlierP[i] { p = zip(p, q).map { (1 - weight) * $0 + weight * $1 } }
                    return classes[argmax(p)]
                }
                let candidate = Candidate(
                    balanced: options.balanced, l2: options.l2, previousChunkWeight: weight,
                    scores: AgreementScores(gold: gold, predicted: predicted)
                )
                candidates.append(candidate)
                if best.map({ isBetter(candidate, than: $0, by: criterion) }) ?? true { best = candidate }
            }
            if let best {
                progress?("balanced=\(options.balanced) l2=\(options.l2): best with earlier weight \(best.previousChunkWeight): \(best.scores.summary)")
            }
        }
        return candidates
    }

    /// The best candidate by `criterion` (the first one on a tie).
    public static func best(_ candidates: [Candidate], by criterion: Criterion = .exact) -> Candidate? {
        candidates.reduce(nil) { best, c in best.map { isBetter(c, than: $0, by: criterion) ? c : $0 } ?? c }
    }

    static func isBetter(_ a: Candidate, than b: Candidate, by criterion: Criterion) -> Bool {
        criterion.key(a.scores) > criterion.key(b.scores)
    }

    /// Test agreement when training on only some of the books: for each count,
    /// the mean over `repeats` seeded random choices of books.
    public static func learningCurve(
        train: [Example],
        test: [Example],
        features: String,
        options: LinearMoodModel.TrainingOptions,
        earlierWeight: Double,
        bookCounts: [Int],
        repeats: Int,
        seed: UInt64 = 1
    ) -> [CurvePoint] {
        let books = Array(Set(train.map(\.group))).sorted()
        var generator = SplitMix64(seed: seed)
        var points: [CurvePoint] = []
        for count in bookCounts where count >= 1 && count <= books.count {
            let runs = count == books.count ? 1 : max(repeats, 1)
            var exact = 0.0, kappa = 0.0, examples = 0.0
            for _ in 0..<runs {
                let chosen = Set(books.shuffled(using: &generator).prefix(count))
                let subset = train.filter { chosen.contains($0.group) }
                let model = LinearMoodModel.train(features: features, x: subset.map(\.recent), labels: subset.map(\.label), options: options)
                let scores = AgreementScores(gold: test.map(\.label), predicted: test.map { predict(model, $0, earlierWeight: earlierWeight) })
                exact += scores.exact
                kappa += scores.kappa
                examples += Double(subset.count)
            }
            let n = Double(runs)
            points.append(CurvePoint(books: count, examples: examples / n, exact: exact / n, kappa: kappa / n))
        }
        return points
    }

    static func argmax(_ p: [Double]) -> Int {
        p.indices.max { p[$0] < p[$1] } ?? 0
    }
}

/// A small seeded generator, so learning curves repeat exactly.
struct SplitMix64: RandomNumberGenerator {
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
