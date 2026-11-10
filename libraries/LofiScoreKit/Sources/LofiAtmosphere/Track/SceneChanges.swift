import Foundation
import LofiText

extension AmbientLevel {
    /// How much of a scene a sound at this level is, for comparing scenes.
    var weight: Double {
        switch self {
        case .faint: 1
        case .soft: 2
        case .full: 3
        case .loud: 4
        }
    }
}

extension StoryScene {
    /// Another place with the very same sounds: other recordings, little else.
    static let otherPlaceDifference = 0.2

    /// How different this scene sounds from `other`, from 0 (the listener hears no
    /// difference) to 1 (nothing in common).
    ///
    /// Half of it compares the exact sounds and half their families, each sound counted
    /// by its level, so a café for a crowd, or the same sounds a step louder, is a small
    /// difference. Two scenes with no sound at all are the same whatever their places.
    public func difference(from other: StoryScene) -> Double {
        if isSilent && other.isSilent { return 0 }
        if soundsLike(other) { return 0 }
        func weights(_ scene: StoryScene, families: Bool) -> [String: Double] {
            var out: [String: Double] = [:]
            for layer in scene.layers {
                let key = families ? layer.sound.rawValue : layer.key
                out[key] = max(out[key] ?? 0, layer.level.weight)
            }
            return out
        }
        // Shared weight over all the weight there is (a weighted Jaccard).
        func shared(_ a: [String: Double], _ b: [String: Double]) -> Double {
            var both = 0.0
            var either = 0.0
            for key in Set(a.keys).union(b.keys) {
                both += min(a[key] ?? 0, b[key] ?? 0)
                either += max(a[key] ?? 0, b[key] ?? 0)
            }
            return either > 0 ? both / either : 1
        }
        let same = 0.5 * shared(weights(self, families: false), weights(other, families: false))
            + 0.5 * shared(weights(self, families: true), weights(other, families: true))
        let place = placeID == other.placeID ? 0 : Self.otherPlaceDifference
        return min(1, place + (1 - place) * (1 - same))
    }
}

/// Finds the changes of sound a listener would hear in a track, and the sentence to
/// score next to pin each one to where it happens.
///
/// It follows ``AtmosphereDirector``: an entry the scorer was less sure of than
/// `minConfidence` never replaces the scene playing, and a scene more than
/// `maxLagSentences` old has faded out. So a change is heard only at a confident entry
/// whose scene differs from the one playing on the sentence before it. Two neighbouring
/// entries that differ on paper but not to the ear (both without sound, or the later one
/// too unsure to be played) are not changes, and no request is spent on them.
///
/// Where to score next, between the entry before the change and the entry that brings
/// it: the sentence the later entry's own answer says its scene began on
/// (``AtmosphereTrack/Entry/sceneStart``), when it lies between the two; otherwise the
/// sentence halfway. A change counts as pinned when the two entries are within
/// `resolutionSentences` of each other (one sentence for a swell, hush or transition), or when the
/// later entry's answer, made from the text up to its own sentence, says the scene
/// begins on that very sentence.
///
/// Spoiler safety is the builder's and is not changed here: a hint only chooses which
/// sentence is scored. That sentence is then judged from its own window, so a sound
/// still starts only where the text up to that sentence gives it.
public struct SceneChangeFinder: Sendable, Hashable {
    public var minConfidence: Double
    public var maxLagSentences: Int
    public var resolutionSentences: Int

    public init(
        minConfidence: Double = AtmosphereConfig().minConfidence,
        maxLagSentences: Int = AtmosphereConfig().maxLagSentences,
        resolutionSentences: Int = 3
    ) {
        self.minConfidence = minConfidence
        self.maxLagSentences = max(0, maxLagSentences)
        self.resolutionSentences = max(1, resolutionSentences)
    }

    public struct Change: Sendable, Hashable {
        /// Global index of the entry just before the change, and of the entry that brings it.
        public let from: Int
        public let at: Int
        /// What plays on the sentence before `at`, and from `at` on.
        public let before: StoryScene
        public let after: StoryScene
        /// ``StoryScene/difference(from:)`` between the two.
        public let difference: Double
        /// The sentence to score next, strictly between `from` and `at`. Nil when pinned.
        public let probe: Int?
        /// The probe is where the later entry's answer says its scene began.
        public let hinted: Bool
        /// Pinned because the later entry's own answer says its scene begins on its sentence.
        public let pinnedByAnswer: Bool
        /// The change plays something on its own sentence (a swell, a hush, a door or an
        /// engine), so it is narrowed to that sentence and counts for more.
        public let onItsSentence: Bool

        public var gap: Int { at - from }
        public var isPinned: Bool { probe == nil }
        /// What narrowing it is worth: how much the listener hears times how far off it
        /// may be, and half as much again when a late start would play a door late.
        public var value: Double { difference * Double(gap) * (onItsSentence ? 1.5 : 1) }
    }

    /// Two scenes the listener would hear as different: another place or other sounds (a
    /// variant counts as its own sound), unless neither has any sound.
    public static func differ(_ a: StoryScene, _ b: StoryScene) -> Bool {
        if a.isSilent && b.isSilent { return false }
        return a.placeID != b.placeID || Set(a.layers.map(\.key)) != Set(b.layers.map(\.key))
    }

    /// The changes of sound in `entries` (sorted by position), in order.
    public func changes(in entries: [AtmosphereTrack.Entry]) -> [Change] {
        var out: [Change] = []
        // The newest entry sure enough to be played.
        var playing: AtmosphereTrack.Entry?
        for (index, entry) in entries.enumerated() {
            guard entry.scene.confidence >= minConfidence else { continue }
            defer { playing = entry }
            guard index > 0 else { continue }
            let previous = entries[index - 1]
            let before = playing.flatMap { entry.globalIndex - 1 - $0.globalIndex <= maxLagSentences ? $0.scene : nil } ?? .silent
            let after = entry.scene
            guard Self.differ(before, after) else { continue }

            let gap = entry.globalIndex - previous.globalIndex
            // A swell or hush pauses the narration right after its sentence, and a
            // transition (named by the scorer, or the plain one the player infers from
            // the two scenes) plays its door or engine on it, so those are pinned to the
            // sentence itself. Being narrow already, they are narrowed after the rest.
            let onItsSentence = after.moment != nil || after.transition != nil
                || SceneTransition.inferred(from: before, to: after) != nil
            let needed = onItsSentence ? 1 : resolutionSentences
            let byAnswer = entry.sceneStart == entry.globalIndex
            var probe: Int?
            var hinted = false
            if !byAnswer, gap > needed {
                if let start = entry.sceneStart, start > previous.globalIndex, start < entry.globalIndex {
                    probe = start
                    hinted = true
                } else {
                    probe = previous.globalIndex + gap / 2
                }
            }
            out.append(Change(
                from: previous.globalIndex, at: entry.globalIndex, before: before, after: after,
                difference: after.difference(from: before), probe: probe, hinted: hinted, pinnedByAnswer: byAnswer,
                onItsSentence: onItsSentence
            ))
        }
        return out
    }

    /// The line of `window` that the quoted first words of a sentence belong to: the
    /// newest line that starts with them; else the newest that has them anywhere; else
    /// the newest line the quote starts with in full (an answer that ran on into the next
    /// sentence). Nil when the quote is under two words or not in the window.
    public static func line(startingWith quote: String, in window: CausalWindow) -> Int? {
        // The first words are enough to tell a sentence.
        let wanted = Array(OneShotMention.words(quote).prefix(6))
        guard wanted.count >= 2 else { return nil }
        var inside: Int?
        var runOn: Int?
        for index in window.lines.indices.reversed() {
            let words = OneShotMention.words(window.lines[index].text)
            if words.count >= wanted.count {
                if Array(words.prefix(wanted.count)) == wanted { return index }
                if inside == nil, words.count > wanted.count,
                   (1...(words.count - wanted.count)).contains(where: { Array(words[$0..<($0 + wanted.count)]) == wanted }) {
                    inside = index
                }
            } else if runOn == nil, words.count >= 3, Array(wanted.prefix(words.count)) == words {
                runOn = index
            }
        }
        return inside ?? runOn
    }
}

extension AtmosphereTrack {
    /// Takes a swell, hush or transition off an entry when an earlier entry already made
    /// it: the entry's own answer says its scene began on an earlier sentence, and an
    /// entry at or after that sentence, sure enough to be played, carries the same move.
    /// Returns how many moves were taken off.
    ///
    /// A first-pass entry a few sentences after a door names the door and the sentence it
    /// was on. Once that sentence is scored, its entry plays the door, and the later
    /// entry would play it a second time whenever its sounds differ a little. A move on
    /// an entry whose scene began earlier is kept when no earlier entry made it (it is
    /// then the first to say so), and a hush or swell inside a scene that is already
    /// going is kept too.
    @discardableResult
    public mutating func dropRepeatedMoves(minConfidence: Double = AtmosphereConfig().minConfidence) -> Int {
        var dropped = 0
        for (index, entry) in entries.enumerated() {
            guard entry.scene.moment != nil || entry.scene.transition != nil,
                  let start = entry.sceneStart, start < entry.globalIndex
            else { continue }
            var scene = entry.scene
            for earlier in entries[..<index].reversed() {
                guard earlier.globalIndex >= start else { break }
                guard earlier.scene.confidence >= minConfidence else { continue }
                if scene.transition != nil, earlier.scene.transition == scene.transition {
                    scene.transition = nil
                    dropped += 1
                }
                if scene.moment != nil, earlier.scene.moment == scene.moment {
                    scene.moment = nil
                    dropped += 1
                }
            }
            if scene != entry.scene { insert(Entry(copying: entry, scene: scene)) }
        }
        return dropped
    }
}
