import Foundation
import Testing
@testable import LofiMood
import LofiScoreCore

@Suite struct LinearMoodModelTests {
    /// Three moods, each a cluster around its own corner of a 4-d space.
    static func clusters(perClass: Int, seed: UInt64, spread: Double = 1) -> ([[Double]], [String]) {
        var state = seed
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        let centres: [(String, [Double])] = [("calm", [2, 0, 0, 5]), ("tense", [0, 2, 0, 5]), ("cozy", [0, 0, 2, 5])]
        var x: [[Double]] = [], y: [String] = []
        for (label, centre) in centres {
            for _ in 0..<perClass {
                x.append(centre.map { $0 + spread * noise() })
                y.append(label)
            }
        }
        return (x, y)
    }

    @Test func learnsSeparableMoodsAndRoundTrips() throws {
        let (x, y) = Self.clusters(perClass: 40, seed: 7)
        let model = LinearMoodModel.train(features: "test/1", x: x, labels: y, options: .init(l2: 1e-3, iterations: 200))
        #expect(model.classes == ["calm", "cozy", "tense"])
        let (tx, ty) = Self.clusters(perClass: 20, seed: 99)
        let scores = AgreementScores(gold: ty, predicted: tx.map(model.predict))
        #expect(scores.exact > 0.95)
        let p = model.probabilities(tx[0])
        #expect(abs(p.reduce(0, +) - 1) < 1e-9)
        #expect(model.scores(tx[0])[.calm]! > 0.5)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("linear-\(UUID().uuidString).json")
        try model.encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try LinearMoodModel.load(from: url)
        #expect(loaded == model)
        // A constant feature (the 4th) must not divide by zero.
        #expect(loaded.probabilities([0, 0, 2, 5]).allSatisfy { $0.isFinite })
    }

    @Test func balancedWeightingFindsTheRareMood() {
        // 60 calm, 6 tense: balanced training still predicts tense on tense points.
        var (x, y) = Self.clusters(perClass: 60, seed: 3)
        let keep = y.indices.filter { y[$0] == "calm" || (y[$0] == "tense" && $0 % 10 == 0) }
        x = keep.map { x[$0] }
        y = keep.map { y[$0] }
        let model = LinearMoodModel.train(features: "test/1", x: x, labels: y, options: .init(l2: 1e-2, iterations: 200, balanced: true))
        #expect(model.predict([0, 2, 0, 5]) == "tense")
        #expect(model.predict([2, 0, 0, 5]) == "calm")
    }

    @Test func multiplyMatchesTheDefinition() {
        // (2×3) · (3×2)
        var c = [Double](repeating: 9, count: 4)
        LinearMoodModel.multiply([1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12], into: &c, m: 2, n: 2, p: 3)
        #expect(c == [58, 64, 139, 154])
    }

    @Test func featureKindSpecs() {
        #expect(TextFeatureKind.kinds(spec: "word") == [.word])
        #expect(TextFeatureKind.kinds(spec: "word+contextual") == [.word, .contextual])
        #expect(TextFeatureKind.kinds(spec: "word+word") == nil)
        #expect(TextFeatureKind.kinds(spec: "word+") == nil)
        #expect(TextFeatureKind.kinds(spec: "glove") == nil)
        #expect(TextFeatureKind.kinds(featureID: "word.en/1+contextual.en/1") == [.word, .contextual])
        #expect(TextFeatureKind.kinds(featureID: "sentence.en/3") == [.sentence])
    }

    @Test func earlierWordsWeightIsStoredAndOptional() throws {
        let (x, y) = Self.clusters(perClass: 10, seed: 5)
        var model = LinearMoodModel.train(features: "test/1", x: x, labels: y, options: .init(iterations: 20))
        #expect(model.previousChunkWeight == nil)
        // Models written before the field existed still load.
        let old = try model.encoded()
        #expect(!String(decoding: old, as: UTF8.self).contains("previousChunkWeight"))
        model.previousChunkWeight = 0.2
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("linear-\(UUID().uuidString).json")
        try model.encoded().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try LinearMoodModel.load(from: url).previousChunkWeight == 0.2)

        let p = model.probabilities(x[0])
        let q = model.probabilities(x[25])
        let mixed = model.probabilities(recent: x[0], earlier: x[25], earlierWeight: 0.2)
        for c in p.indices { #expect(abs(mixed[c] - (0.8 * p[c] + 0.2 * q[c])) < 1e-12) }
        #expect(model.probabilities(recent: x[0], earlier: nil, earlierWeight: 0.2) == p)
    }

    @Test func foldsKeepBooksTogether() {
        let groups = ["b", "a", "c", "a", "d", "b", "e"]
        let folds = LinearMoodModelSelection.folds(groups: groups, count: 2)
        // Sorted books a, b, c, d, e dealt into folds 0, 1, 0, 1, 0.
        #expect(folds == [1, 0, 0, 0, 1, 1, 0])
        #expect(Set(LinearMoodModelSelection.folds(groups: ["a", "b"], count: 5)) == [0, 1])
    }

    /// Both chunks are noisy readings of the same mood, so averaging them
    /// beats the newest words alone, and cross-validation must find that.
    @Test func crossValidationScoresEverySettingAndFindsTheUsefulWeight() {
        let (recent, labels) = Self.clusters(perClass: 40, seed: 11, spread: 7)
        let (earlier, _) = Self.clusters(perClass: 40, seed: 12, spread: 7)
        let examples = labels.indices.map { i in
            LinearMoodModelSelection.Example(group: "book\(i % 6)", label: labels[i], recent: recent[i], earlier: earlier[i])
        }
        let settings = [LinearMoodModel.TrainingOptions(l2: 1e-2, iterations: 100), .init(l2: 1, iterations: 100, balanced: false)]
        let candidates = LinearMoodModelSelection.crossValidate(examples, features: "test/1", settings: settings, earlierWeights: [0, 0.5], folds: 3)
        #expect(candidates.count == 4)
        #expect(candidates.allSatisfy { $0.scores.count == examples.count })
        let best = LinearMoodModelSelection.best(candidates)!
        #expect(best.previousChunkWeight == 0.5)
        let alone = candidates.filter { $0.previousChunkWeight == 0 }.map(\.scores.exact).max()!
        #expect(best.scores.exact > alone)
    }

    @Test func criteriaRankCandidatesDifferently() {
        func candidate(_ exact: Double, _ kappa: Double, _ f1: Double) -> LinearMoodModelSelection.Candidate {
            var scores = AgreementScores(gold: [], predicted: [])
            scores.exact = exact; scores.kappa = kappa; scores.macroF1 = f1
            return .init(balanced: false, l2: 0.1, previousChunkWeight: 0, scores: scores)
        }
        let calmHeavy = candidate(0.376, 0.255, 0.229)
        let varied = candidate(0.352, 0.258, 0.291)
        #expect(LinearMoodModelSelection.best([calmHeavy, varied]) == calmHeavy)
        #expect(LinearMoodModelSelection.best([calmHeavy, varied], by: .kappa) == varied)
        #expect(LinearMoodModelSelection.best([calmHeavy, varied], by: .macroF1) == varied)
        #expect(LinearMoodModelSelection.Criterion(rawValue: "macro-f1") == .macroF1)
    }

    @Test func learningCurveRepeatsExactly() {
        let (x, y) = Self.clusters(perClass: 20, seed: 21)
        let examples = y.indices.map { LinearMoodModelSelection.Example(group: "book\($0 % 8)", label: y[$0], recent: x[$0]) }
        let options = LinearMoodModel.TrainingOptions(l2: 1e-2, iterations: 50)
        let a = LinearMoodModelSelection.learningCurve(train: examples, test: examples, features: "t", options: options, earlierWeight: 0, bookCounts: [2, 4, 8], repeats: 3)
        let b = LinearMoodModelSelection.learningCurve(train: examples, test: examples, features: "t", options: options, earlierWeight: 0, bookCounts: [2, 4, 8], repeats: 3)
        #expect(a == b)
        #expect(a.map(\.books) == [2, 4, 8])
        #expect(a.last!.examples == Double(examples.count))
        #expect(a.last!.exact > 0.95)
    }

    @Test func agreementScores() {
        let s = AgreementScores(gold: ["calm", "calm", "tense", "cozy"], predicted: ["calm", "tense", "tense", "cozy"])
        #expect(s.count == 4)
        #expect(abs(s.exact - 0.75) < 1e-12)
        // chance = (2*1 + 1*2 + 1*1) / 16 = 5/16; kappa = (0.75 - 0.3125) / 0.6875
        #expect(abs(s.kappa - (0.75 - 0.3125) / 0.6875) < 1e-12)
        #expect(s.macroF1 > 0.7 && s.macroF1 < 0.8)
    }
}
