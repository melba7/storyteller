import Foundation
import LofiMood
import LofiScoreCore

/// A fixed way to train the word-embedding model, shared by `oof` (which
/// compares recipes on every labelled book) and `embed --recipe` (which
/// trains the one that ships).
struct Recipe {
    var name: String
    var options: LinearMoodModel.TrainingOptions
    /// How much the words before the newest ones count.
    var earlierWeight: Double
    /// Train only on the books listed by `oof --old-books`.
    var oldOnly = false
    /// How far to lean the moods towards people's pleasantness and energy
    /// ratings (`lofi-train people`); 0 leaves them alone.
    var leanValence = 0.0
    var leanArousal = 0.0

    var usesAlternatives: Bool { (options.alternativeWeight ?? 0) > 0 }
    var usesPeople: Bool { leanValence != 0 || leanArousal != 0 }

    /// Trains on `examples`; `alternatives` lines up with them (empty lists
    /// where a window has none).
    func train(features: String, examples: [LinearMoodModelSelection.Example], alternatives: [[String]]?,
               people: PeopleScores?) -> LinearMoodModel {
        var model = LinearMoodModel.train(
            features: features, x: examples.map(\.recent), labels: examples.map(\.label),
            alternatives: usesAlternatives ? alternatives : nil, options: options
        )
        if let people, usesPeople {
            let x = examples.map(\.recent)
            model = model.leaning(on: people.valence, anchor: { $0.anchor.valence }, strength: leanValence, over: x)
            model = model.leaning(on: people.arousal, anchor: { $0.anchor.arousal }, strength: leanArousal, over: x)
        }
        model.previousChunkWeight = earlierWeight
        return model
    }

    /// word-2's settings (unweighted, l2 0.1, earlier words 0.2): the shipped
    /// recipe since round 5 and the baseline every other recipe is compared to.
    static let baseline = Recipe(name: "word2-settings", options: .init(l2: 0.1, iterations: 300, balanced: false), earlierWeight: 0.2)

    static func variant(_ name: String, _ change: (inout Recipe) -> Void) -> Recipe {
        var r = baseline
        r.name = name
        change(&r)
        return r
    }

    static let catalog: [Recipe] = [
        baseline,
        Recipe(name: "word6-settings", options: .init(l2: 0.03, iterations: 300, balanced: false), earlierWeight: 0.35),
        Recipe(name: "balanced-l2-0.1", options: .init(l2: 0.1, iterations: 300, balanced: true), earlierWeight: 0.2),
        variant("word2-settings-old") { $0.oldOnly = true },
        // Gentle corrections of the pull towards tense and calm (round 8: every
        // recipe names them far more often than the labels do).
        variant("prior-0.15") { $0.options.priorShift = 0.15 },
        variant("prior-0.3") { $0.options.priorShift = 0.3 },
        variant("prior-0.5") { $0.options.priorShift = 0.5 },
        // Soft labels: the other moods that would also suit a window share 30%.
        variant("soft-0.3") { $0.options.alternativeWeight = 0.3 },
        variant("soft-0.3-prior-0.3") { $0.options.alternativeWeight = 0.3; $0.options.priorShift = 0.3 },
        // Lean towards people's ratings of how pleasant (and energetic) a text is.
        variant("people-v0.25") { $0.leanValence = 0.25 },
        variant("people-v0.5") { $0.leanValence = 0.5 },
        variant("people-v1") { $0.leanValence = 1 },
        variant("people-va0.5") { $0.leanValence = 0.5; $0.leanArousal = 0.5 },
    ]

    static func named(_ name: String) -> Recipe? { catalog.first { $0.name == name } }
}
