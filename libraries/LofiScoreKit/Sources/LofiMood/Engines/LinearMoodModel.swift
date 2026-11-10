import Foundation
import LofiScoreCore
#if canImport(Accelerate)
import Accelerate
#endif

/// Which of Apple's on-device text embeddings feeds a `LinearMoodModel`.
/// The kinds themselves need NaturalLanguage (`TextFeaturizer`); naming and
/// combining them works anywhere.
public enum TextFeatureKind: String, CaseIterable, Sendable {
    /// `NLEmbedding.sentenceEmbedding`: one vector per sentence (iOS 14+).
    case sentence
    /// `NLEmbedding.wordEmbedding`: averaged word vectors (iOS 13+).
    case word
    /// `NLContextualEmbedding`: Apple's BERT-style model, mean-pooled (iOS 17+,
    /// needs its assets on the device).
    case contextual

    /// The kinds in a spec such as "word" or "word+contextual" (side by side
    /// in one feature vector), or nil if a part is unknown or repeated.
    public static func kinds(spec: String) -> [TextFeatureKind]? {
        let kinds = spec.split(separator: "+", omittingEmptySubsequences: false).map { TextFeatureKind(rawValue: String($0)) }
        guard !kinds.isEmpty, kinds.allSatisfy({ $0 != nil }) else { return nil }
        let found = kinds.compactMap { $0 }
        return Set(found).count == found.count ? found : nil
    }

    /// The kinds a model's feature id was built from, e.g. "word.en/1+contextual.en/1".
    public static func kinds(featureID: String) -> [TextFeatureKind]? {
        kinds(spec: featureID.split(separator: "+", omittingEmptySubsequences: false)
            .map { String($0.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }
            .joined(separator: "+"))
    }
}

/// A softmax (multinomial logistic regression) mood classifier over a fixed
/// feature vector, such as a sentence embedding of the newest words.
///
/// Pure Swift, so it trains and runs anywhere; only the features may need an
/// Apple framework. Inputs are standardised with the training set's mean and
/// spread before the linear layer, and the whole model is a small JSON file.
public struct LinearMoodModel: Codable, Sendable, Equatable {
    public static let currentFormat = 1

    public var format: Int
    /// Which features the model expects, e.g. "contextual.en/1".
    public var features: String
    /// Mood names in the order of `weights` and `bias`.
    public var classes: [String]
    public var mean: [Double]
    public var scale: [Double]
    /// One row of `mean.count` weights per class.
    public var weights: [[Double]]
    public var bias: [Double]
    /// How it was trained, for the record.
    public var training: TrainingOptions
    /// How much the words just before the newest ones count (0 to 1), chosen
    /// with the model; nil leaves it to the engine.
    public var previousChunkWeight: Double?

    public var dimension: Int { mean.count }

    public struct TrainingOptions: Codable, Sendable, Equatable {
        /// L2 penalty on the weights (after standardising the inputs).
        public var l2: Double
        /// Full-batch Adam steps.
        public var iterations: Int
        public var learningRate: Double
        /// Weight each mood's examples so every mood counts equally in the loss.
        public var balanced: Bool
        /// After training, subtract this much of each mood's log share of the
        /// labels from its bias ("logit adjustment"): 0 or nil changes
        /// nothing, 1 removes the pull towards common moods entirely. A gentle
        /// version of `balanced`, which over-corrects (round 8: 4.8 points
        /// lower agreement).
        public var priorShift: Double?
        /// With `alternatives`, the share of each example's target spread over
        /// the other moods that would also suit it (best mood keeps the rest).
        public var alternativeWeight: Double?

        public init(l2: Double = 1e-3, iterations: Int = 300, learningRate: Double = 0.05, balanced: Bool = true,
                    priorShift: Double? = nil, alternativeWeight: Double? = nil) {
            self.l2 = l2
            self.iterations = iterations
            self.learningRate = learningRate
            self.balanced = balanced
            self.priorShift = priorShift
            self.alternativeWeight = alternativeWeight
        }
    }

    public init(features: String, classes: [String], mean: [Double], scale: [Double], weights: [[Double]], bias: [Double], training: TrainingOptions, previousChunkWeight: Double? = nil) {
        self.format = Self.currentFormat
        self.features = features
        self.classes = classes
        self.mean = mean
        self.scale = scale
        self.weights = weights
        self.bias = bias
        self.training = training
        self.previousChunkWeight = previousChunkWeight
    }

    /// Class probabilities for one feature vector, in the order of `classes`.
    public func probabilities(_ x: [Double]) -> [Double] {
        precondition(x.count == dimension, "expected \(dimension) features, got \(x.count)")
        var z = [Double](repeating: 0, count: mean.count)
        for j in 0..<dimension { z[j] = (x[j] - mean[j]) / scale[j] }
        let logits = (0..<classes.count).map { k in
            zip(weights[k], z).reduce(bias[k]) { $0 + $1.0 * $1.1 }
        }
        return Self.softmax(logits)
    }

    /// Probabilities for the newest words, mixed with those for the words
    /// before them (if given) at `earlierWeight`, the way the engine reads a window.
    public func probabilities(recent: [Double], earlier: [Double]?, earlierWeight: Double) -> [Double] {
        let p = probabilities(recent)
        guard let earlier, earlierWeight > 0 else { return p }
        return zip(p, probabilities(earlier)).map { (1 - earlierWeight) * $0 + earlierWeight * $1 }
    }

    /// The probabilities keyed by mood; classes that are not moods are dropped.
    public func scores(_ x: [Double]) -> [MoodBucket: Double] {
        var out: [MoodBucket: Double] = [:]
        for (name, p) in zip(classes, probabilities(x)) {
            if let bucket = MoodBucket(lenient: name) { out[bucket, default: 0] += p }
        }
        return out
    }

    public func predict(_ x: [Double]) -> String {
        let p = probabilities(x)
        return classes[p.indices.max { p[$0] < p[$1] }!]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func load(from url: URL) throws -> LinearMoodModel {
        let model = try JSONDecoder().decode(LinearMoodModel.self, from: Data(contentsOf: url))
        guard model.format == currentFormat else { throw LinearMoodModelError.unsupportedFormat(model.format) }
        guard model.weights.count == model.classes.count, model.bias.count == model.classes.count,
              model.scale.count == model.mean.count, model.weights.allSatisfy({ $0.count == model.mean.count })
        else { throw LinearMoodModelError.malformed }
        return model
    }

    // MARK: Training

    /// Fits the model by full-batch Adam on softmax cross-entropy plus an L2
    /// penalty. Deterministic: the weights start at zero and there is no sampling.
    ///
    /// `alternatives` (one list per example, possibly empty) names other moods
    /// that would also suit each example; with `options.alternativeWeight`
    /// they share that much of its target ("soft labels").
    public static func train(features: String, x: [[Double]], labels: [String], alternatives: [[String]]? = nil,
                             options: TrainingOptions = TrainingOptions()) -> LinearMoodModel {
        precondition(!x.isEmpty && x.count == labels.count, "need one label per example")
        precondition(alternatives == nil || alternatives!.count == labels.count, "need one list of alternatives per example")
        let n = x.count
        let d = x[0].count
        let softShare = min(max(options.alternativeWeight ?? 0, 0), 1)
        let others: [[String]] = softShare > 0 && alternatives != nil
            ? zip(labels, alternatives!).map { label, alts in alts.filter { $0 != label } }
            : []
        let classes = Array(Set(labels).union(others.joined())).sorted()
        let k = classes.count
        let index = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        let y = labels.map { index[$0]! }
        // Soft targets only where an example has alternatives: (index, share) pairs.
        var soft: [[(Int, Double)]] = []
        if !others.isEmpty {
            soft = others.enumerated().map { i, alts in
                guard !alts.isEmpty else { return [] }
                return [(y[i], 1 - softShare)] + alts.map { (index[$0]!, softShare / Double(alts.count)) }
            }
        }

        // Standardise. z is n×d and zt its transpose, both row-major.
        var mean = [Double](repeating: 0, count: d)
        var scale = [Double](repeating: 0, count: d)
        for row in x { for j in 0..<d { mean[j] += row[j] } }
        for j in 0..<d { mean[j] /= Double(n) }
        for row in x { for j in 0..<d { let v = row[j] - mean[j]; scale[j] += v * v } }
        for j in 0..<d { scale[j] = max(sqrt(scale[j] / Double(n)), 1e-8) }
        var z = [Double](repeating: 0, count: n * d)
        var zt = [Double](repeating: 0, count: d * n)
        for i in 0..<n {
            for j in 0..<d {
                let v = (x[i][j] - mean[j]) / scale[j]
                z[i * d + j] = v
                zt[j * n + i] = v
            }
        }

        // Example weights: balanced moods count equally; weights sum to 1.
        var w = [Double](repeating: 1, count: n)
        if options.balanced {
            var counts = [Double](repeating: 0, count: k)
            for c in y { counts[c] += 1 }
            for i in 0..<n { w[i] = 1 / (Double(k) * counts[y[i]]) }
        } else {
            for i in 0..<n { w[i] = 1 / Double(n) }
        }

        // W is d×k (one column per class) so both products are plain matrix multiplies.
        var W = [Double](repeating: 0, count: d * k)
        var b = [Double](repeating: 0, count: k)
        var mW = W, vW = W, mb = b, vb = b
        let beta1 = 0.9, beta2 = 0.999, eps = 1e-8
        var gW = [Double](repeating: 0, count: d * k)
        var gb = [Double](repeating: 0, count: k)
        var r = [Double](repeating: 0, count: n * k)  // logits, then weighted residuals

        for step in 1...max(options.iterations, 1) {
            multiply(z, W, into: &r, m: n, n: k, p: d)
            for c in 0..<k { gb[c] = 0 }
            for i in 0..<n {
                let row = i * k
                var top = -Double.infinity
                for c in 0..<k { r[row + c] += b[c]; top = max(top, r[row + c]) }
                var total = 0.0
                for c in 0..<k { let e = exp(r[row + c] - top); r[row + c] = e; total += e }
                for c in 0..<k { r[row + c] /= total }
                if !soft.isEmpty, !soft[i].isEmpty {
                    for (c, t) in soft[i] { r[row + c] -= t }
                } else {
                    r[row + y[i]] -= 1
                }
                for c in 0..<k {
                    let g = w[i] * r[row + c]
                    r[row + c] = g
                    gb[c] += g
                }
            }
            multiply(zt, r, into: &gW, m: d, n: k, p: n)
            for q in 0..<(d * k) { gW[q] += options.l2 * W[q] }
            let lr = options.learningRate
            let c1 = 1 - pow(beta1, Double(step)), c2 = 1 - pow(beta2, Double(step))
            for q in 0..<(d * k) {
                mW[q] = beta1 * mW[q] + (1 - beta1) * gW[q]
                vW[q] = beta2 * vW[q] + (1 - beta2) * gW[q] * gW[q]
                W[q] -= lr * (mW[q] / c1) / (sqrt(vW[q] / c2) + eps)
            }
            for c in 0..<k {
                mb[c] = beta1 * mb[c] + (1 - beta1) * gb[c]
                vb[c] = beta2 * vb[c] + (1 - beta2) * gb[c] * gb[c]
                b[c] -= lr * (mb[c] / c1) / (sqrt(vb[c] / c2) + eps)
            }
        }

        if let shift = options.priorShift, shift != 0 {
            var counts = [Double](repeating: 0, count: k)
            for c in y { counts[c] += 1 }
            // A mood seen only as an alternative counts as half an example.
            for c in 0..<k { b[c] -= shift * log(max(counts[c], 0.5) / Double(n)) }
        }
        let rows = (0..<k).map { c in (0..<d).map { j in W[j * k + c] } }
        return LinearMoodModel(features: features, classes: classes, mean: mean, scale: scale, weights: rows, bias: b, training: options)
    }

    /// This model with `perClass[mood] × (a·x + c)` added to each mood's
    /// logit, folded into the weights and biases, so the result is an
    /// ordinary model file that any engine reads. `a` and `c` act on the raw
    /// (unstandardised) features. Used to lean the moods towards a score
    /// learned elsewhere, such as how pleasant people rate a text.
    public func addingLinearScore(weights a: [Double], bias c: Double, perClass: [String: Double]) -> LinearMoodModel {
        precondition(a.count == dimension, "expected \(dimension) weights, got \(a.count)")
        var out = self
        // a·x = Σ a_j (z_j scale_j + mean_j), with z the standardised input.
        let offset = zip(a, mean).reduce(c) { $0 + $1.0 * $1.1 }
        for (k, name) in classes.enumerated() {
            guard let f = perClass[name], f != 0 else { continue }
            for j in 0..<dimension { out.weights[k][j] += f * a[j] * scale[j] }
            out.bias[k] += f * offset
        }
        return out
    }

    /// c (m×n) = a (m×p) · b (p×n), all row-major. Accelerate on Apple platforms.
    static func multiply(_ a: [Double], _ b: [Double], into c: inout [Double], m: Int, n: Int, p: Int) {
        precondition(a.count == m * p && b.count == p * n && c.count == m * n)
        a.withUnsafeBufferPointer { A in
            b.withUnsafeBufferPointer { B in
                c.withUnsafeMutableBufferPointer { C in
                    #if canImport(Accelerate)
                    vDSP_mmulD(A.baseAddress!, 1, B.baseAddress!, 1, C.baseAddress!, 1, vDSP_Length(m), vDSP_Length(n), vDSP_Length(p))
                    #else
                    for t in 0..<(m * n) { C[t] = 0 }
                    for i in 0..<m {
                        let ci = i * n
                        for q in 0..<p {
                            let v = A[i * p + q]
                            if v == 0 { continue }
                            let bq = q * n
                            for j in 0..<n { C[ci + j] += v * B[bq + j] }
                        }
                    }
                    #endif
                }
            }
        }
    }

    static func softmax(_ logits: [Double]) -> [Double] {
        let top = logits.max() ?? 0
        let e = logits.map { exp($0 - top) }
        let total = e.reduce(0, +)
        return e.map { $0 / total }
    }
}

public enum LinearMoodModelError: Error, Sendable, Equatable {
    case unsupportedFormat(Int)
    case malformed
}

/// Exact agreement, macro-F1 and Cohen's kappa between two label lists.
public struct AgreementScores: Sendable, Equatable, Codable {
    public var count: Int
    public var exact: Double
    public var macroF1: Double
    public var kappa: Double

    public init(gold: [String], predicted: [String]) {
        precondition(gold.count == predicted.count)
        let n = Double(gold.count)
        count = gold.count
        guard n > 0 else { exact = 0; macroF1 = 0; kappa = 0; return }
        let pairs = Array(zip(gold, predicted))
        let agree = Double(pairs.filter { $0 == $1 }.count)
        exact = agree / n
        let labels = Array(Set(gold).union(predicted)).sorted()
        let f1s = labels.map { label -> Double in
            let tp = Double(pairs.filter { $0 == label && $1 == label }.count)
            let fp = Double(pairs.filter { $0 != label && $1 == label }.count)
            let fn = Double(pairs.filter { $0 == label && $1 != label }.count)
            return tp == 0 ? 0 : 2 * tp / (2 * tp + fp + fn)
        }
        macroF1 = f1s.reduce(0, +) / Double(f1s.count)
        let chance = labels.reduce(0.0) { sum, label in
            sum + Double(gold.filter { $0 == label }.count) * Double(predicted.filter { $0 == label }.count) / (n * n)
        }
        kappa = chance < 1 ? (exact - chance) / (1 - chance) : 0
    }

    public var summary: String {
        String(format: "%d windows: exact %.1f%%, macro-F1 %.3f, kappa %.3f", count, exact * 100, macroF1, kappa)
    }
}
