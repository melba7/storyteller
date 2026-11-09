import Foundation
import LofiScoreCore

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

    public var dimension: Int { mean.count }

    public struct TrainingOptions: Codable, Sendable, Equatable {
        /// L2 penalty on the weights (after standardising the inputs).
        public var l2: Double
        /// Full-batch Adam steps.
        public var iterations: Int
        public var learningRate: Double
        /// Weight each mood's examples so every mood counts equally in the loss.
        public var balanced: Bool

        public init(l2: Double = 1e-3, iterations: Int = 300, learningRate: Double = 0.05, balanced: Bool = true) {
            self.l2 = l2
            self.iterations = iterations
            self.learningRate = learningRate
            self.balanced = balanced
        }
    }

    public init(features: String, classes: [String], mean: [Double], scale: [Double], weights: [[Double]], bias: [Double], training: TrainingOptions) {
        self.format = Self.currentFormat
        self.features = features
        self.classes = classes
        self.mean = mean
        self.scale = scale
        self.weights = weights
        self.bias = bias
        self.training = training
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
    public static func train(features: String, x: [[Double]], labels: [String], options: TrainingOptions = TrainingOptions()) -> LinearMoodModel {
        precondition(!x.isEmpty && x.count == labels.count, "need one label per example")
        let n = x.count
        let d = x[0].count
        let classes = Array(Set(labels)).sorted()
        let k = classes.count
        let index = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        let y = labels.map { index[$0]! }

        // Standardise.
        var mean = [Double](repeating: 0, count: d)
        var scale = [Double](repeating: 0, count: d)
        for row in x { for j in 0..<d { mean[j] += row[j] } }
        for j in 0..<d { mean[j] /= Double(n) }
        for row in x { for j in 0..<d { let v = row[j] - mean[j]; scale[j] += v * v } }
        for j in 0..<d { scale[j] = max(sqrt(scale[j] / Double(n)), 1e-8) }
        var z = [Double](repeating: 0, count: n * d)
        for i in 0..<n { for j in 0..<d { z[i * d + j] = (x[i][j] - mean[j]) / scale[j] } }

        // Example weights: balanced moods count equally; weights sum to 1.
        var w = [Double](repeating: 1, count: n)
        if options.balanced {
            var counts = [Double](repeating: 0, count: k)
            for c in y { counts[c] += 1 }
            for i in 0..<n { w[i] = 1 / (Double(k) * counts[y[i]]) }
        } else {
            for i in 0..<n { w[i] = 1 / Double(n) }
        }

        var W = [Double](repeating: 0, count: k * d)
        var b = [Double](repeating: 0, count: k)
        var mW = W, vW = W, mb = b, vb = b
        let beta1 = 0.9, beta2 = 0.999, eps = 1e-8
        var gW = [Double](repeating: 0, count: k * d)
        var gb = [Double](repeating: 0, count: k)
        var logits = [Double](repeating: 0, count: k)

        for step in 1...max(options.iterations, 1) {
            for q in 0..<(k * d) { gW[q] = 0 }
            for c in 0..<k { gb[c] = 0 }
            z.withUnsafeBufferPointer { Z in
                W.withUnsafeBufferPointer { WP in
                    gW.withUnsafeMutableBufferPointer { G in
                        for i in 0..<n {
                            let row = i * d
                            for c in 0..<k {
                                var s = b[c]
                                let wr = c * d
                                for j in 0..<d { s += WP[wr + j] * Z[row + j] }
                                logits[c] = s
                            }
                            let p = softmax(logits)
                            for c in 0..<k {
                                let g = w[i] * (p[c] - (c == y[i] ? 1 : 0))
                                if g == 0 { continue }
                                gb[c] += g
                                let wr = c * d
                                for j in 0..<d { G[wr + j] += g * Z[row + j] }
                            }
                        }
                    }
                }
            }
            for q in 0..<(k * d) { gW[q] += options.l2 * W[q] }
            let lr = options.learningRate
            let c1 = 1 - pow(beta1, Double(step)), c2 = 1 - pow(beta2, Double(step))
            for q in 0..<(k * d) {
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

        let rows = (0..<k).map { Array(W[($0 * d)..<(($0 + 1) * d)]) }
        return LinearMoodModel(features: features, classes: classes, mean: mean, scale: scale, weights: rows, bias: b, training: options)
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
