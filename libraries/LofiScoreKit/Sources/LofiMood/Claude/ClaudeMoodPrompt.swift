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
    /// saved mood tracks record it. The default for new engines; `versions`
    /// lists every one an engine can be asked for.
    public static let version = 2
    public static let versions = [2, 3]

    public static let system = """
        You choose background music for an audiobook. Each message holds the passage that has \
        just been read aloud, oldest sentence first. Decide what music fits the story at the \
        passage's final sentences, the part the listener is hearing now. Earlier sentences are \
        context.

        Judge only the words in the passage. Do not use anything you know about the book, its \
        author or its plot, and never choose a mood for what is about to happen.

        The eleven moods, and when to use each (judging the final sentences):
        - calm: quiet, settled or reflective; ordinary talk, travel, description, exposition; \
        nothing at stake right now
        - cozy: warm and safe: home, food, firesides, friendship, gentle affection
        - playful: light, funny, teasing or mischievous; lively banter, comic mishaps
        - hopeful: uplifting: relief, triumph, reunion, things turning out well
        - melancholy: sad and quiet: loss, longing, loneliness, regret, homesickness
        - mysterious: uncertain or eerie: secrets, puzzles, strange sights or sounds, something \
        unexplained
        - tense: danger, conflict, fear, a chase, a fight, a bitter argument; urgent suspense
        - somber: grave and heavy: death, grief, funerals, solemn ritual, dread, despair
        - romantic: love between people: courtship, a kiss, tenderness between lovers, love \
        declared, a wedding
        - dreamy: wonder and enchantment: magic, marvels, dreams and reveries, beautiful strange \
        sights; nothing threatening
        - adventurous: bold forward motion, excitement more than fear: setting out, exploring, \
        sailing or riding into the unknown, a daring feat going well, discovery

        Tie-breaks:
        - When nothing in particular is going on, the answer is calm. Most of a novel is calm; \
        that is fine.
        - calm vs cozy: cozy needs warmth or affection on the page, not just a quiet room.
        - playful vs hopeful: playful is humour and banter; hopeful is uplift and relief.
        - melancholy vs somber: melancholy is quiet sadness; somber is weight, death or dread.
        - mysterious vs tense: mysterious is not knowing; tense is danger happening now.
        - A heated argument with real stakes is tense; mild disagreement or gossip is calm or \
        playful.
        - romantic vs cozy: romantic is love or attraction between two people; cozy is the \
        warmth of home, family and friends.
        - romantic vs hopeful: a kiss or a love declared is romantic; relief or triumph without \
        romance is hopeful.
        - Love lost or unreturned, mostly sad, is melancholy, not romantic.
        - dreamy vs mysterious: dreamy is wonder and beauty; mysterious is not knowing, with unease.
        - dreamy vs calm: dreamy needs magic, enchantment or awe on the page, not just a quiet scene.
        - adventurous vs tense: adventurous is excitement and momentum; tense is fear with a real \
        threat now.
        - adventurous vs playful: playful is humour; adventurous is daring and discovery.
        - Ordinary travel described without excitement is calm, not adventurous.
        - If the passage ends on a chapter heading, give the mood the previous scene ended on.

        Also give valence from -1 (very unpleasant) to 1 (very pleasant), arousal from 0 (still) \
        to 1 (frantic), and your confidence in the mood from 0 to 1.
        """

    /// Version 3 adds two fields to version 2's answer. `about` comes first so
    /// the model describes the moment before it names a mood (the schema's
    /// properties are sent in sorted order, which puts it first). `also` lists
    /// other moods whose music would suit too, the "plausible set" the test
    /// labels use, so playback can keep the music when it still fits.
    public static let systemV3 = system + """


        Before the mood, write `about`: one short line on what is happening in the final sentences \
        and what, if anything, is at stake for the people in them. Then choose the mood from that.

        In `also`, list any other moods whose music would clearly suit the final sentences too, \
        best first, at most two. Leave it empty when only one mood fits, which is common.
        """

    public static func system(version: Int) -> String {
        version >= 3 ? systemV3 : system
    }

    /// The user message for one window.
    public static func message(for window: CausalWindow, maxWords: Int = 400) -> String {
        """
        Passage (the last sentence is being read aloud now):
        <<<
        \(MoodPrompt.passage(for: window, maxWords: maxWords))
        >>>
        """
    }

    /// The answer's JSON schema for a prompt version.
    public static func schema(version: Int) -> [String: Any] {
        guard version >= 3 else { return schema }
        let moods = MoodBucket.allCases.map(\.rawValue)
        return [
            "type": "object",
            "properties": [
                "about": ["type": "string"],
                "mood": ["type": "string", "enum": moods],
                "also": ["type": "array", "items": ["type": "string", "enum": moods]],
                "valence": ["type": "number"],
                "arousal": ["type": "number"],
                "confidence": ["type": "number"],
            ],
            "required": ["about", "mood", "also", "valence", "arousal", "confidence"],
            "additionalProperties": false,
        ]
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
