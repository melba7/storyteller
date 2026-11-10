import Foundation
import LofiScoreCore

/// Per-bucket mood evidence that fades with listening time.
///
/// Each reading adds a share to every bucket (see ``MoodReading/evidence(config:)``),
/// and everything fades exponentially, so recent readings count most. Smoothing the
/// buckets themselves, instead of one valence/arousal point, means a story moving from
/// Tense to Calm never passes through Mysterious on the way just because Mysterious sits
/// between them on the map.
public struct MoodEvidence: Sendable, Hashable {
    public private(set) var weights: [MoodBucket: Double] = [:]

    /// The listening time the weights were last brought up to date at.
    public private(set) var updatedAt: TimeInterval?

    public init() {}

    public func weight(of bucket: MoodBucket) -> Double {
        weights[bucket] ?? 0
    }

    public var total: Double {
        weights.values.reduce(0, +)
    }

    /// Fades the evidence to `time`. Time never runs backwards; an earlier time is ignored.
    public mutating func decay(to time: TimeInterval, timeConstant: TimeInterval) {
        guard let last = updatedAt else {
            updatedAt = time
            return
        }
        guard time > last else { return }
        if timeConstant > 0 {
            let factor = exp(-(time - last) / timeConstant)
            weights = weights.mapValues { $0 * factor }
        }
        updatedAt = time
    }

    /// Fades to `time`, then adds `contribution`.
    public mutating func add(
        _ contribution: [MoodBucket: Double],
        at time: TimeInterval,
        timeConstant: TimeInterval
    ) {
        decay(to: time, timeConstant: timeConstant)
        for (bucket, value) in contribution where value.isFinite && value > 0 {
            weights[bucket, default: 0] += value
        }
    }

    /// Keeps only `factor` of every bucket's evidence.
    public mutating func scale(by factor: Double) {
        let kept = min(1, max(0, factor))
        weights = weights.mapValues { $0 * kept }
    }

    /// Drops all evidence. The time stays, so later fading continues from here.
    public mutating func removeAll() {
        weights.removeAll()
    }

    /// Evidence plus the neutral prior, as shares that sum to 1.
    public func shares(neutralPrior: Double) -> [MoodBucket: Double] {
        var scored = weights
        scored[MoodBucket.neutral, default: 0] += max(0, neutralPrior)
        let total = scored.values.reduce(0, +)
        guard total > 0 else { return [MoodBucket.neutral: 1] }
        return scored.mapValues { $0 / total }
    }

    /// The bucket the evidence favours, with hysteresis.
    ///
    /// Returns `current` unless another bucket leads it by at least `switchMargin` of
    /// all evidence (prior included). Ties go to `current`, then to the neutral bucket.
    public func leader(current: MoodBucket, config: DirectorConfig) -> MoodBucket {
        let shares = shares(neutralPrior: config.neutralPrior)
        let currentShare = shares[current] ?? 0
        var best = current
        var bestShare = currentShare
        for bucket in MoodBucket.allCases {
            let share = shares[bucket] ?? 0
            if share > bestShare + 1e-12 {
                best = bucket
                bestShare = share
            }
        }
        guard best != current else { return current }
        return bestShare - currentShare >= config.switchMargin ? best : current
    }

    /// The evidence-weighted average of the bucket anchors, for display.
    public func centroid(neutralPrior: Double) -> MoodPoint {
        var valence = 0.0
        var arousal = 0.0
        for (bucket, share) in shares(neutralPrior: neutralPrior) {
            valence += bucket.anchor.valence * share
            arousal += bucket.anchor.arousal * share
        }
        return MoodPoint(valence: valence, arousal: arousal)
    }
}

extension MoodReading {
    /// How much this reading adds to each bucket's evidence.
    ///
    /// The shares come from the engine's per-bucket `scores` when it has them. Otherwise
    /// they blend the engine's own label (``DirectorConfig/labelWeight``) with a soft match
    /// of the reading's valence and arousal against every bucket's anchor. The whole
    /// contribution is scaled by confidence, so an unsure reading moves the music less.
    public func evidence(config: DirectorConfig) -> [MoodBucket: Double] {
        let weight = max(config.confidenceFloor, confidence)
        var shares: [MoodBucket: Double] = [:]
        if let scores, scores.values.contains(where: { $0 > 0 }) {
            shares = scores
        } else {
            let spread = max(0.01, config.anchorSpread)
            var soft: [MoodBucket: Double] = [:]
            var softTotal = 0.0
            for bucket in MoodBucket.allCases {
                let distance = bucket.anchor.distance(to: point)
                let match = exp(-(distance * distance) / (2 * spread * spread))
                soft[bucket] = match
                softTotal += match
            }
            let labelWeight = min(1, max(0, config.labelWeight))
            for bucket in MoodBucket.allCases {
                let label = bucket == self.bucket ? 1.0 : 0.0
                let match = softTotal > 0 ? (soft[bucket] ?? 0) / softTotal : 0
                shares[bucket] = labelWeight * label + (1 - labelWeight) * match
            }
        }
        return shares.mapValues { $0 * weight }
    }
}
