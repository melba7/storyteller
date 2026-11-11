import Foundation
import Testing
@testable import LofiMood
import LofiScoreCore

@Suite struct LinearScoreTests {
    typealias Clusters = LinearMoodModelTests

    @Test func priorShiftMovesOnlyTheBiasesTowardsRareMoods() {
        // 60 calm, 12 tense, 60 cozy.
        var (x, y) = Clusters.clusters(perClass: 60, seed: 5, spread: 3)
        let keep = y.indices.filter { y[$0] != "tense" || $0 % 5 == 0 }
        x = keep.map { x[$0] }
        y = keep.map { y[$0] }
        let plain = LinearMoodModel.train(features: "t", x: x, labels: y, options: .init(l2: 0.1, iterations: 150, balanced: false))
        let shifted = LinearMoodModel.train(features: "t", x: x, labels: y, options: .init(l2: 0.1, iterations: 150, balanced: false, priorShift: 0.5))
        #expect(shifted.weights == plain.weights)
        let n = Double(y.count)
        for (k, name) in plain.classes.enumerated() {
            let share = Double(y.filter { $0 == name }.count) / n
            #expect(abs(shifted.bias[k] - (plain.bias[k] - 0.5 * log(share))) < 1e-12)
        }
        // The rare mood gains the most.
        let tense = plain.classes.firstIndex(of: "tense")!
        let calm = plain.classes.firstIndex(of: "calm")!
        #expect(shifted.bias[tense] - plain.bias[tense] > shifted.bias[calm] - plain.bias[calm])
        // Stored, and still decodes without the new fields.
        #expect(shifted.training.priorShift == 0.5)
        let old = #"{"l2":0.1,"iterations":300,"learningRate":0.05,"balanced":false}"#
        let decoded = try? JSONDecoder().decode(LinearMoodModel.TrainingOptions.self, from: Data(old.utf8))
        #expect(decoded?.priorShift == nil && decoded?.alternativeWeight == nil)
    }

    @Test func softTargetsShareTheLabelWithTheAlternatives() {
        let (x, y) = Clusters.clusters(perClass: 30, seed: 9)
        // Every calm example also suits cozy.
        let alts = y.map { $0 == "calm" ? ["cozy"] : [] }
        let hard = LinearMoodModel.train(features: "t", x: x, labels: y, options: .init(l2: 0.01, iterations: 200, balanced: false))
        let soft = LinearMoodModel.train(features: "t", x: x, labels: y, alternatives: alts,
                                         options: .init(l2: 0.01, iterations: 200, balanced: false, alternativeWeight: 0.4))
        let calmPoint = [2.0, 0, 0, 5]
        let cozy = hard.classes.firstIndex(of: "cozy")!
        #expect(soft.probabilities(calmPoint)[cozy] > hard.probabilities(calmPoint)[cozy] + 0.1)
        #expect(soft.predict(calmPoint) == "calm", "the best mood keeps the larger share")
        // Without a weight the alternatives are ignored.
        let ignored = LinearMoodModel.train(features: "t", x: x, labels: y, alternatives: alts,
                                            options: .init(l2: 0.01, iterations: 200, balanced: false))
        #expect(ignored == hard)
        // A mood seen only as an alternative becomes a class.
        let extra = LinearMoodModel.train(features: "t", x: x, labels: y, alternatives: y.map { $0 == "tense" ? ["somber"] : [] },
                                          options: .init(l2: 0.01, iterations: 50, balanced: false, alternativeWeight: 0.3))
        #expect(extra.classes.contains("somber"))
    }

    @Test func foldingAScoreMatchesAddingItToTheLogits() {
        let (x, y) = Clusters.clusters(perClass: 20, seed: 4)
        let model = LinearMoodModel.train(features: "t", x: x, labels: y, options: .init(l2: 0.1, iterations: 100))
        let a = [0.3, -0.2, 0.5, 0.1]
        let c = -0.4
        let perClass = ["calm": 0.7, "tense": -1.2]
        let folded = model.addingLinearScore(weights: a, bias: c, perClass: perClass)
        let point = [1.5, 0.3, -0.2, 4.0]
        let s = zip(a, point).reduce(c) { $0 + $1.0 * $1.1 }
        // softmax(logits + perClass·s) computed directly
        func logits(_ m: LinearMoodModel, _ x: [Double]) -> [Double] {
            let z = (0..<m.dimension).map { (x[$0] - m.mean[$0]) / m.scale[$0] }
            return (0..<m.classes.count).map { k in zip(m.weights[k], z).reduce(m.bias[k]) { $0 + $1.0 * $1.1 } }
        }
        let expected = LinearMoodModel.softmax(zip(model.classes, logits(model, point)).map { $1 + (perClass[$0] ?? 0) * s })
        for (p, q) in zip(folded.probabilities(point), expected) { #expect(abs(p - q) < 1e-9) }
    }

    @Test func ridgeRecoversALinearRule() {
        var state: UInt64 = 42
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        let truth = [1.5, -2.0, 0.0, 0.5]
        let x = (0..<300).map { _ in (0..<4).map { j in 10 * noise() + Double(j) } }
        let y = x.map { row in zip(truth, row).reduce(3.0) { $0 + $1.0 * $1.1 } + 0.01 * noise() }
        let fit = LinearScore.ridge(features: "t", x: x, y: y, l2: 1e-6)
        for (w, t) in zip(fit.weights, truth) { #expect(abs(w - t) < 0.01) }
        #expect(abs(fit.score([1, 1, 1, 1]) - (3 + truth.reduce(0, +))) < 0.05)
        // A heavy penalty shrinks towards the mean.
        let shrunk = LinearScore.ridge(features: "t", x: x, y: y, l2: 1e4)
        #expect(shrunk.weights.map(abs).reduce(0, +) < 0.01)
        let mean = y.reduce(0, +) / Double(y.count)
        #expect(abs(shrunk.score(x[0]) - mean) < 0.2)
    }

    @Test func leaningFavoursThePleasantMoodsForPleasantText() {
        // Feature 0 is "pleasantness"; the model itself cannot tell calm from tense on it.
        let x: [[Double]] = (0..<40).map { i in [Double(i % 10) - 4.5, Double(i % 2)] }
        let y = (0..<40).map { $0 % 2 == 0 ? "cozy" : "tense" }
        let model = LinearMoodModel.train(features: "t", x: x, labels: y, options: .init(l2: 1, iterations: 50, balanced: false))
        let score = LinearScore(features: "t", weights: [1, 0], bias: 0)
        let leaned = model.leaning(on: score, anchor: { $0.anchor.valence }, strength: 1, over: x)
        let pleasant = [4.0, 0.5], unpleasant = [-4.0, 0.5]
        let cozy = model.classes.firstIndex(of: "cozy")!
        #expect(leaned.probabilities(pleasant)[cozy] > model.probabilities(pleasant)[cozy])
        #expect(leaned.probabilities(unpleasant)[cozy] < model.probabilities(unpleasant)[cozy])
        #expect(model.leaning(on: score, anchor: { $0.anchor.valence }, strength: 0, over: x) == model)
    }
}
