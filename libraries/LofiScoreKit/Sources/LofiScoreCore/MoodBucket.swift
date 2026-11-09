import Foundation

/// A point in valence/arousal space.
///
/// - `valence` runs from -1 (negative, unpleasant) to 1 (positive, pleasant).
/// - `arousal` runs from 0 (low energy, still) to 1 (high energy, urgent).
public struct MoodPoint: Sendable, Hashable, Codable {
    public var valence: Double
    public var arousal: Double

    public init(valence: Double, arousal: Double) {
        self.valence = min(1, max(-1, valence))
        self.arousal = min(1, max(0, arousal))
    }

    /// Euclidean distance, with arousal stretched to the same -1...1 span as valence.
    public func distance(to other: MoodPoint) -> Double {
        let dv = valence - other.valence
        let da = (arousal - other.arousal) * 2
        return (dv * dv + da * da).squareRoot()
    }
}

/// The moods the music library is sorted into. One folder of tracks per bucket.
///
/// The first eight are the plan's original buckets; romantic, dreamy and
/// adventurous were added on 9 Nov 2026 at Mo's request. New cases go at the
/// end, so existing orderings (confusion tables, classifier label lists) keep
/// their meaning.
public enum MoodBucket: String, CaseIterable, Codable, Sendable, Hashable, CodingKeyRepresentable {
    case calm
    case cozy
    case playful
    case hopeful
    case melancholy
    case mysterious
    case tense
    case somber
    case romantic
    case dreamy
    case adventurous

    /// The bucket used when nothing else is known (start of a book, unreadable text).
    public static let neutral: MoodBucket = .calm

    /// "Calm", "Cozy", and so on. Matches the folder names in the music library.
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// A starting point for each bucket's centre in valence/arousal space, taken
    /// from the plan's mood table. Tune these in the listening test.
    ///
    /// | Bucket     | Valence  | Arousal     |
    /// |------------|----------|-------------|
    /// | Calm       | positive | low         |
    /// | Cozy       | positive | low to mid  |
    /// | Playful    | positive | mid to high |
    /// | Hopeful    | positive | high        |
    /// | Melancholy | negative | low         |
    /// | Mysterious | neutral  | mid         |
    /// | Tense      | negative | high        |
    /// | Somber     | negative | mid         |
    /// | Romantic   | positive | low to mid  |
    /// | Dreamy     | positive | mid         |
    /// | Adventurous| positive | high        |
    public var anchor: MoodPoint {
        switch self {
        case .calm: MoodPoint(valence: 0.25, arousal: 0.15)
        case .cozy: MoodPoint(valence: 0.55, arousal: 0.30)
        case .playful: MoodPoint(valence: 0.60, arousal: 0.62)
        case .hopeful: MoodPoint(valence: 0.70, arousal: 0.82)
        case .melancholy: MoodPoint(valence: -0.50, arousal: 0.20)
        case .mysterious: MoodPoint(valence: -0.10, arousal: 0.50)
        case .tense: MoodPoint(valence: -0.55, arousal: 0.85)
        case .somber: MoodPoint(valence: -0.70, arousal: 0.45)
        case .romantic: MoodPoint(valence: 0.75, arousal: 0.40)
        case .dreamy: MoodPoint(valence: 0.45, arousal: 0.45)
        case .adventurous: MoodPoint(valence: 0.35, arousal: 0.78)
        }
    }

    /// The bucket whose anchor is closest to `point`.
    public static func nearest(to point: MoodPoint) -> MoodBucket {
        var best = MoodBucket.neutral
        var bestDistance = Double.infinity
        for bucket in allCases {
            let d = bucket.anchor.distance(to: point)
            if d < bestDistance {
                best = bucket
                bestDistance = d
            }
        }
        return best
    }

    /// Parses a bucket name, tolerating case, surrounding punctuation, and a
    /// handful of near-synonyms that language models like to answer with.
    public init?(lenient raw: String) {
        let cleaned = raw
            .lowercased()
            .trimmingCharacters(in: CharacterSet.letters.inverted)
        if let exact = MoodBucket(rawValue: cleaned) {
            self = exact
            return
        }
        if cleaned == "sombre" { self = .somber; return }
        guard let mapped = MoodBucket.synonyms[cleaned] else { return nil }
        self = mapped
    }

    private static let synonyms: [String: MoodBucket] = [
        "neutral": .calm, "peaceful": .calm, "serene": .calm, "quiet": .calm, "tranquil": .calm, "relaxed": .calm,
        "warm": .cozy, "comforting": .cozy, "homely": .cozy, "intimate": .cozy, "snug": .cozy,
        "funny": .playful, "humorous": .playful, "whimsical": .playful, "lighthearted": .playful, "light": .playful,
        "comic": .playful, "mischievous": .playful, "joyful": .playful, "cheerful": .playful,
        "uplifting": .hopeful, "triumphant": .hopeful, "optimistic": .hopeful, "inspiring": .hopeful,
        "joyous": .hopeful,
        "sad": .melancholy, "wistful": .melancholy, "nostalgic": .melancholy, "lonely": .melancholy,
        "bittersweet": .melancholy, "sorrowful": .melancholy, "melancholic": .melancholy,
        "eerie": .mysterious, "suspicious": .mysterious, "uncanny": .mysterious, "enigmatic": .mysterious,
        "curious": .mysterious, "ominous": .mysterious, "strange": .mysterious, "mystery": .mysterious,
        "suspenseful": .tense, "anxious": .tense, "scary": .tense, "frightening": .tense, "action": .tense,
        "dangerous": .tense, "urgent": .tense, "fearful": .tense, "violent": .tense,
        "grim": .somber, "solemn": .somber, "dark": .somber, "grave": .somber, "mournful": .somber,
        "tragic": .somber, "bleak": .somber, "heavy": .somber, "dread": .somber,
        // Nouns small models write instead of the bucket word ("bucket=tension").
        "calmness": .calm, "peace": .calm, "reflective": .calm, "reflection": .calm,
        "warmth": .cozy, "comfort": .cozy, "affection": .cozy,
        "humor": .playful, "humour": .playful, "playfulness": .playful, "fun": .playful,
        "hope": .hopeful, "relief": .hopeful, "joy": .hopeful, "triumph": .hopeful,
        "sadness": .melancholy, "longing": .melancholy, "loneliness": .melancholy, "regret": .melancholy,
        "melancholia": .melancholy,
        "mysteriousness": .mysterious, "secret": .mysterious, "intrigue": .mysterious,
        "tension": .tense, "suspense": .tense, "fear": .tense, "danger": .tense, "conflict": .tense,
        "tenseness": .tense,
        "grief": .somber, "death": .somber, "mourning": .somber, "somberness": .somber, "sombreness": .somber,
        // The three moods added on 9 Nov 2026.
        "love": .romantic, "loving": .romantic, "romance": .romantic, "tender": .romantic, "tenderness": .romantic,
        "passionate": .romantic, "passion": .romantic, "amorous": .romantic, "lovestruck": .romantic, "adoring": .romantic,
        "dream": .dreamy, "dreamlike": .dreamy, "dreaming": .dreamy, "wonder": .dreamy, "wondrous": .dreamy,
        "awe": .dreamy, "awestruck": .dreamy, "magic": .dreamy, "magical": .dreamy, "enchanted": .dreamy,
        "enchanting": .dreamy, "enchantment": .dreamy, "ethereal": .dreamy, "otherworldly": .dreamy,
        "reverie": .dreamy, "fantastical": .dreamy, "surreal": .dreamy, "wonderment": .dreamy,
        "adventure": .adventurous, "exciting": .adventurous, "excitement": .adventurous, "excited": .adventurous,
        "thrilling": .adventurous, "quest": .adventurous, "journey": .adventurous, "bold": .adventurous,
        "daring": .adventurous, "heroic": .adventurous, "epic": .adventurous, "exploration": .adventurous,
        "expedition": .adventurous, "adventuresome": .adventurous, "swashbuckling": .adventurous,
    ]
}

extension MoodBucket: CustomStringConvertible {
    public var description: String { rawValue }
}

