import Foundation
import LofiMood
import LofiText

/// What ``ClaudeSceneEngine`` sends: the rules and the sound list as the system prompt;
/// the book's world, the current scene, the places visited so far, the more specific
/// sounds available and the passage as the user message; and a JSON schema for the answer.
public enum ClaudeScenePrompt {
    /// Bump when the wording or schema changes; engine ids and saved tracks record it.
    public static let version = 3

    /// Places listed with each passage, most recent first.
    public static let maxPlacesListed = 15
    /// Variants listed: the shared ones in the system prompt, the book's own with each passage.
    public static let maxVariantsListed = 80

    /// The system prompt without shared variants.
    public static var system: String { system(sharedVariants: []) }

    /// The system prompt. `sharedVariants` (the starter set and other books' variants) are
    /// the same for a whole run, so they sit here, where the prompt cache keeps them.
    public static func system(sharedVariants: [SoundVariant]) -> String {
        let sounds = AmbientSound.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
        let oneShots = OneShotSound.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
        let shared = sharedVariants.isEmpty
            ? "none"
            : "\n" + sharedVariants.prefix(maxVariantsListed).map(describe).joined(separator: "\n")
        return """
            You design the background soundscape for an audiobook: quiet, steady sounds of the \
            place where the story is, played softly under the narrator's voice and some gentle \
            music. Each message gives what is known so far (the book's world, the current scene \
            and the places visited before) and the passage that has just been read aloud, oldest \
            sentence first. Decide the soundscape for the moment the passage ends: where the \
            characters are now and what that place sounds like.

            Judge only the words given. Do not use anything you know about the book, its author \
            or its plot, and never set up a scene, weather or sound before the text reaches it.

            How to decide:
            - Where are the characters physically at the end of the passage? A place that is only \
            remembered, imagined, dreamed, written about in a letter or talked about does not \
            count: keep the current scene.
            - Infer the sounds a listener would expect there even when the text does not mention \
            them: a ship at sea creaks and has water around it; woods by day have leaves and \
            birds; a busy school corridor has a crowd. Fit the book's world and era: no traffic \
            before cars, no engines in a medieval town.
            - Weather carries over from place to place until the text says it changed. Indoors, \
            rain becomes rainIndoors. Thunder only while a storm is actually going on.
            - Returning to a known place: answer with its id and start from the sounds remembered \
            there, changing only what the text says changed (the fire burned low, a storm \
            arrived, night fell, the hall emptied).
            - A place not in the list: place "new" and a short name ("the Weasleys' kitchen"). \
            The same place under another name is still the known place.
            - Keep it subtle: usually one to three sounds. No sounds at all is right when the \
            place has no sound of its own (an ordinary quiet room, an office), when the passage \
            is all talk with no setting, or when you cannot tell where the characters are.
            - Levels: faint (barely there), soft (in the background), full (the place's main sound).
            - crowd is for many people right around the characters whose words cannot be made \
            out. The music pauses while it plays, so use it only where a crowd is clearly there.
            - If the passage ends on a chapter heading, or jumps to a new time or place that the \
            text has not described yet, answer with no sounds, place "none" and confidence below 0.3.

            The sounds:
            \(sounds)

            More specific sounds (variants):
            - A sound may name a variant: a more specific kind of it, from the specific sounds \
            available (listed below, and with the passage when the book has added its own). Use \
            one when it fits the place clearly better than the plain sound; otherwise variant is "".
            - When the place clearly calls for a steady sound that is a distinctly more specific \
            kind of one of the sounds above and no available variant fits (church bells across a \
            town square, a waterfall, a busy cafe, a blizzard), add it to newSounds: id (a short \
            camelCase name such as churchBells), of (the sound above it is a kind of; that sound \
            plays until a recording is found), about (what it is, up to ten words) and search \
            (two to five words to search a sound library with). Then use it as that sound's variant.
            - Only for a place the characters are in, not a passing mention; only a steady sound \
            that can loop (no single bangs or footsteps, no words that can be followed, no music); \
            at most one new sound per answer, and never one that is already available. Usually \
            newSounds is empty.

            Specific sounds available in every book (variant (the sound it is a kind of): what it is): \(shared)

            Moments:
            - moment is "swell" when the passage's last sentence is the very moment the \
            characters walk into a much louder place or a big steady sound starts around them: \
            entering a crowded hall, a market or a busy inn; stepping out into a storm, or a storm \
            breaking overhead; coming out onto a beach, a cliff top or a ship's deck; a train, \
            coach or ship setting off, an engine starting; coming upon a waterfall, a rushing \
            river or a roaring bonfire.
            - "hush" when the last sentence is the moment the sound around them suddenly drops \
            away: a door shutting on a noisy room, the rain stopping, an engine cutting out, \
            stepping into a silent church or a snowy field.
            - Otherwise "none". The narration pauses for under a second at a moment, so keep \
            them for clear, audible arrivals, a few per chapter at most, and never for a place \
            that is only remembered or talked about.

            One-off sounds:
            - oneShot is a single, distinct sound that the passage says happens, right then and \
            where the characters are: a clap of thunder, a knock at the door, a clock striking. \
            It plays once, on the sentence that says so, if the listener has turned them on.
            - Only when the text says the sound itself happens at that moment. Not a sound that \
            is remembered, expected, imagined, compared to ("a laugh like breaking glass"), talked \
            about or heard in a dream; not one that goes on and on (that is a steady sound above); \
            not a sound that is only implied.
            - quote: copy, word for word, the fewest words (at most eight) from the passage that \
            say the sound happens, ending on the word for the sound, e.g. "there came a knock at \
            the door". If several happen, take the last one in the passage.
            - They are rare: most passages have none. Then sound is "none" and quote is "".

            The one-off sounds:
            \(oneShots)

            Also answer:
            - setting: indoors, outdoors, vehicle (a carriage, train, ship, spaceship) or unclear.
            - world: a few words on the book's setting so far (era, region, season, technology), \
            updated from the passage; repeat the previous note when nothing new is learned.
            - cue: up to ten words copied from the passage that best show the scene, or "" if the \
            scene is inferred.
            - confidence: from 0 to 1, how sure you are of the place and its sounds.
            """
    }

    /// The user message for one window. Variants already in the system prompt
    /// (`sharedVariants`) are not repeated.
    public static func message(
        for window: CausalWindow, memory: PlaceMemory, maxWords: Int = 400, sharedVariants: [SoundVariant] = []
    ) -> String {
        var lines: [String] = []
        lines.append("Book's world so far: \(memory.world ?? "nothing known yet")")
        if let current = memory.current, current.placeID != nil || !current.isSilent {
            lines.append("Current scene before this passage: \(describe(current))")
        } else {
            lines.append("Current scene before this passage: none yet")
        }
        let places = memory.recent(limit: maxPlacesListed)
        if places.isEmpty {
            lines.append("Places visited before: none")
        } else {
            lines.append("Places visited before (most recent first):")
            for place in places {
                lines.append("- \(place.id) \"\(place.name)\" (\(place.setting.rawValue)): \(describe(place.layers))")
            }
        }
        let shared = Set(sharedVariants.prefix(maxVariantsListed).map(\.id))
        let own = memory.variants.filter { !shared.contains($0.id) }.prefix(maxVariantsListed)
        if !own.isEmpty {
            lines.append("Specific sounds this book has added so far:")
            lines.append(contentsOf: own.map(describe))
        }
        lines.append("")
        lines.append("Passage (the last sentence is being read aloud now):")
        lines.append("<<<")
        lines.append(MoodPrompt.passage(for: window, maxWords: maxWords))
        lines.append(">>>")
        return lines.joined(separator: "\n")
    }

    static func describe(_ scene: StoryScene) -> String {
        let place = scene.placeID.map { id in scene.placeName.map { "\(id) \"\($0)\"" } ?? id } ?? "no particular place"
        return "\(place) (\(scene.setting.rawValue)): \(describe(scene.layers))"
    }

    /// "- churchBells (oldTown): church bells ringing across a town".
    static func describe(_ variant: SoundVariant) -> String {
        "- \(variant.id) (\(variant.of.rawValue)): \(variant.about)"
    }

    /// "fireplace soft, oldTown faint (variant churchBells)".
    static func describe(_ layers: [SceneLayer]) -> String {
        guard !layers.isEmpty else { return "no sounds" }
        return layers.map { layer in
            "\(layer.sound.rawValue) \(layer.level.rawValue)" + (layer.variant.map { " (variant \($0))" } ?? "")
        }.joined(separator: ", ")
    }

    /// The answer's JSON schema, for `output_config.format`. Structured outputs do not
    /// take array length limits, so the engine keeps the loudest four sounds itself.
    public static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "place": ["type": "string"],
                "placeName": ["type": "string"],
                "setting": ["type": "string", "enum": StoryScene.Setting.allCases.map(\.rawValue)],
                "sounds": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "sound": ["type": "string", "enum": AmbientSound.allCases.map(\.rawValue)],
                            "level": ["type": "string", "enum": AmbientLevel.allCases.map(\.rawValue)],
                            "variant": ["type": "string"],
                        ],
                        "required": ["sound", "level", "variant"],
                        "additionalProperties": false,
                    ] as [String: Any],
                ] as [String: Any],
                "newSounds": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "of": ["type": "string", "enum": AmbientSound.allCases.map(\.rawValue)],
                            "about": ["type": "string"],
                            "search": ["type": "string"],
                        ],
                        "required": ["id", "of", "about", "search"],
                        "additionalProperties": false,
                    ] as [String: Any],
                ] as [String: Any],
                "moment": ["type": "string", "enum": ["none"] + StoryScene.Moment.allCases.map(\.rawValue)],
                "oneShot": [
                    "type": "object",
                    "properties": [
                        "sound": ["type": "string", "enum": ["none"] + OneShotSound.allCases.map(\.rawValue)],
                        "quote": ["type": "string"],
                    ],
                    "required": ["sound", "quote"],
                    "additionalProperties": false,
                ] as [String: Any],
                "world": ["type": "string"],
                "cue": ["type": "string"],
                "confidence": ["type": "number"],
            ] as [String: Any],
            "required": ["place", "placeName", "setting", "sounds", "newSounds", "moment", "oneShot", "world", "cue", "confidence"],
            "additionalProperties": false,
        ]
    }
}
