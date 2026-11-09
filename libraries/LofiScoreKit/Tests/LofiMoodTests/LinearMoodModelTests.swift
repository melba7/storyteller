import Foundation
import Testing
@testable import LofiMood
import LofiScoreCore

@Suite struct LinearMoodModelTests {
    /// Three moods, each a cluster around its own corner of a 4-d space.
    static func clusters(perClass: Int, seed: UInt64) -> ([[Double]], [String]) {
        var state = seed
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        let centres: [(String, [Double])] = [("calm", [2, 0, 0, 5]), ("tense", [0, 2, 0, 5]), ("cozy", [0, 0, 2, 5])]
        var x: [[Double]] = [], y: [String] = []
        for (label, centre) in centres {
            for _ in 0..<perClass {
                x.append(centre.map { $0 + noise() })
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

    @Test func agreementScores() {
        let s = AgreementScores(gold: ["calm", "calm", "tense", "cozy"], predicted: ["calm", "tense", "tense", "cozy"])
        #expect(s.count == 4)
        #expect(abs(s.exact - 0.75) < 1e-12)
        // chance = (2*1 + 1*2 + 1*1) / 16 = 5/16; kappa = (0.75 - 0.3125) / 0.6875
        #expect(abs(s.kappa - (0.75 - 0.3125) / 0.6875) < 1e-12)
        #expect(s.macroF1 > 0.7 && s.macroF1 < 0.8)
    }
}
