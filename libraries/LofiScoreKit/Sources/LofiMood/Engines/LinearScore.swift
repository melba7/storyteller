import Foundation
import LofiScoreCore

/// A number read off a feature vector by a linear map, such as how pleasant
/// people would rate a text, learned by ridge regression.
public struct LinearScore: Codable, Sendable, Equatable {
    /// Which features it expects, as in `LinearMoodModel.features`.
    public var features: String
    /// One weight per raw (unstandardised) feature.
    public var weights: [Double]
    public var bias: Double

    public init(features: String, weights: [Double], bias: Double) {
        self.features = features
        self.weights = weights
        self.bias = bias
    }

    public func score(_ x: [Double]) -> Double {
        precondition(x.count == weights.count, "expected \(weights.count) features, got \(x.count)")
        return zip(weights, x).reduce(bias) { $0 + $1.0 * $1.1 }
    }

    /// Ridge regression: minimises mean squared error plus `l2` times the
    /// squared weights, on standardised inputs (so `l2` means the same for
    /// every feature), then maps the weights back to the raw features.
    public static func ridge(features: String, x: [[Double]], y: [Double], l2: Double) -> LinearScore {
        precondition(!x.isEmpty && x.count == y.count, "need one target per example")
        let n = x.count
        let d = x[0].count
        var mean = [Double](repeating: 0, count: d)
        var scale = [Double](repeating: 0, count: d)
        for row in x { for j in 0..<d { mean[j] += row[j] } }
        for j in 0..<d { mean[j] /= Double(n) }
        for row in x { for j in 0..<d { let v = row[j] - mean[j]; scale[j] += v * v } }
        for j in 0..<d { scale[j] = max(sqrt(scale[j] / Double(n)), 1e-8) }
        let yMean = y.reduce(0, +) / Double(n)

        var z = [Double](repeating: 0, count: n * d)
        var zt = [Double](repeating: 0, count: d * n)
        for i in 0..<n {
            for j in 0..<d {
                let v = (x[i][j] - mean[j]) / scale[j]
                z[i * d + j] = v
                zt[j * n + i] = v
            }
        }
        // (ZᵀZ/n + l2·I) w = Zᵀ(y - ȳ)/n
        var gram = [Double](repeating: 0, count: d * d)
        LinearMoodModel.multiply(zt, z, into: &gram, m: d, n: d, p: n)
        for q in 0..<(d * d) { gram[q] /= Double(n) }
        for j in 0..<d { gram[j * d + j] += max(l2, 1e-9) }
        var rhs = [Double](repeating: 0, count: d)
        for i in 0..<n {
            let t = y[i] - yMean
            for j in 0..<d { rhs[j] += z[i * d + j] * t }
        }
        for j in 0..<d { rhs[j] /= Double(n) }
        let w = solveSymmetricPositiveDefinite(gram, rhs, size: d)

        var raw = [Double](repeating: 0, count: d)
        var bias = yMean
        for j in 0..<d {
            raw[j] = w[j] / scale[j]
            bias -= raw[j] * mean[j]
        }
        return LinearScore(features: features, weights: raw, bias: bias)
    }

    /// Solves A·x = b for a symmetric positive definite A (row-major) by Cholesky.
    static func solveSymmetricPositiveDefinite(_ a: [Double], _ b: [Double], size d: Int) -> [Double] {
        var l = [Double](repeating: 0, count: d * d)
        for i in 0..<d {
            for j in 0...i {
                var sum = a[i * d + j]
                for k in 0..<j { sum -= l[i * d + k] * l[j * d + k] }
                if i == j {
                    l[i * d + i] = sqrt(max(sum, 1e-12))
                } else {
                    l[i * d + j] = sum / l[j * d + j]
                }
            }
        }
        var yv = [Double](repeating: 0, count: d)
        for i in 0..<d {
            var sum = b[i]
            for k in 0..<i { sum -= l[i * d + k] * yv[k] }
            yv[i] = sum / l[i * d + i]
        }
        var x = [Double](repeating: 0, count: d)
        for i in stride(from: d - 1, through: 0, by: -1) {
            var sum = yv[i]
            for k in (i + 1)..<d { sum -= l[k * d + i] * x[k] }
            x[i] = sum / l[i * d + i]
        }
        return x
    }
}

/// How pleasant (valence) and how energetic (arousal) people rate a text,
/// as two `LinearScore`s learned from human ratings (EmoBank's non-fiction
/// sentences; see `lofi-train people`).
public struct PeopleScores: Codable, Sendable, Equatable {
    public var features: String
    public var valence: LinearScore
    public var arousal: LinearScore
    /// Where the ratings came from, for the record (and the licence).
    public var source: String

    public init(features: String, valence: LinearScore, arousal: LinearScore, source: String) {
        self.features = features
        self.valence = valence
        self.arousal = arousal
        self.source = source
    }

    public static func load(from url: URL) throws -> PeopleScores {
        try JSONDecoder().decode(PeopleScores.self, from: Data(contentsOf: url))
    }
}

extension LinearMoodModel {
    /// Leans the moods towards what a score says: a text that scores one
    /// spread above its usual level (measured over `x`, typically the
    /// training windows) gains `strength` × the mood's standardised anchor on
    /// that axis in its logit, so pleasant-sounding text favours the
    /// pleasant moods. Folded into the weights: the result is an ordinary model.
    public func leaning(on score: LinearScore, anchor: (MoodBucket) -> Double, strength: Double, over x: [[Double]]) -> LinearMoodModel {
        guard strength != 0, !x.isEmpty else { return self }
        let values = x.map(score.score)
        let mu = values.reduce(0, +) / Double(values.count)
        let sigma = sqrt(values.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / Double(values.count))
        guard sigma > 1e-12 else { return self }
        let moods = MoodBucket.allCases
        let anchors = moods.map(anchor)
        let am = anchors.reduce(0, +) / Double(anchors.count)
        let asd = max(sqrt(anchors.reduce(0) { $0 + ($1 - am) * ($1 - am) } / Double(anchors.count)), 1e-12)
        var perClass: [String: Double] = [:]
        for name in classes {
            guard let mood = MoodBucket(lenient: name) else { continue }
            perClass[name] = strength * (anchor(mood) - am) / asd / sigma
        }
        return addingLinearScore(weights: score.weights, bias: score.bias - mu, perClass: perClass)
    }
}
