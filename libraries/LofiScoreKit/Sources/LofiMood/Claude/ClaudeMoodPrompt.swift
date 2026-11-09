import Foundation
import LofiScoreCore
import LofiText

/// What `ClaudeMoodEngine` sends: the labelling guidelines as the system
/// prompt, the passage as the user message, and a JSON schema for the answer.
///
/// The system prompt is `Tools/data/labels/GUIDELINES.md` in prompt form, so
/// Claude answers exactly the question the reference labels answer. A JSON
/// schema with an enum (structured outputs) replaces the one-line format the
/// on-device model needs, so there is nothing to parse leniently.
public enum ClaudeMoodPrompt {
    /// Bump when the wording or schema changes; the engine id includes it, and
    /// saved mood tracks record it.
    public static let version = 1

    public static let system = """
        You choose background music for an audiobook. Each message holds the passage that has \
        just been read aloud, oldest sentence first. Decide what music fits the story at the \
        passage's final sentences, the part the listener is hearing now. Earlier sentences are \
        context.

        Judge only the words in the passage. Do not use anything you know about the book, its \
        author or its plot, and never choose a mood for what is about to happen.

        The eight moods, and when to use each (judging the final sentences):
        - calm: quiet, settled or reflective; ordinary talk, travel, description, exposition; \
        nothing at stake right now
        - cozy: warm and safe: home, food, firesides, friendship, gentle affection
        - playful: light, funny, teasing or mischievous; lively banter, comic mishaps
        - hopeful: uplifting: relief, triumph, reunion, love declared, things turning out well
        - melancholy: sad and quiet: loss, longing, loneliness, regret, homesickness
        - mysterious: uncertain or eerie: secrets, puzzles, strange sights or sounds, something \
        unexplained
        - tense: danger, conflict, fear, a chase, a fight, a bitter argument; urgent suspense
        - somber: grave and heavy: death, grief, funerals, solemn ritual, dread, despair

        Tie-breaks:
        - When nothing in particular is going on, the answer is calm. Most of a novel is calm; \
        that is fine.
        - calm vs cozy: cozy needs warmth or affection on the page, not just a quiet room.
        - playful vs hopeful: playful is humour and banter; hopeful is uplift and relief.
        - melancholy vs somber: melancholy is quiet sadness; somber is weight, death or dread.
        - mysterious vs tense: mysterious is not knowing; tense is danger happening now.
        - A heated argument with real stakes is tense; mild disagreement or gossip is calm or \
        playful.
        - If the passage ends on a chapter heading, give the mood the previous scene ended on.

        Also give valence from -1 (very unpleasant) to 1 (very pleasant), arousal from 0 (still) \
        to 1 (frantic), and your confidence in the mood from 0 to 1.
        """

    /// The user message for one window.
    public static func message(for window: CausalWindow, maxWords: Int = 400) -> String {
        """
        Passage (the last sentence is being read aloud now):
        <<<
        \(MoodPrompt.passage(for: window, maxWords: maxWords))
        >>>
        """
    }

    /// The answer's JSON schema, for `output_config.format`.
    public static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "mood": ["type": "string", "enum": MoodBucket.allCases.map(\.rawValue)],
                "valence": ["type": "number"],
                "arousal": ["type": "number"],
                "confidence": ["type": "number"],
            ],
            "required": ["mood", "valence", "arousal", "confidence"],
            "additionalProperties": false,
        ]
    }
}
