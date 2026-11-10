import Foundation
import LofiMood
import LofiText

/// What ``ClaudeSceneEngine`` sends: the rules, the sound catalogue and the place guide as
/// the system prompt; the book's world, the current scene, the places visited so far (with
/// their state), the book's own more specific sounds and the passage as the user message;
/// and a JSON schema for the answer.
public enum ClaudeScenePrompt {
    /// Bump when the wording or schema changes; engine ids and saved tracks record it.
    public static let version = 5

    /// Places listed with each passage, most recent first.
    public static let maxPlacesListed = 15
    /// Extra variants listed beyond the built-in catalogue: other books' in the system
    /// prompt, the book's own with each passage.
    public static let maxVariantsListed = 80

    /// The system prompt without other books' variants.
    public static var system: String { system(sharedVariants: []) }

    /// The system prompt. The built-in catalogue (``SoundCatalog``) is always in it;
    /// `sharedVariants` (other books' requests from the Mac's catalogue) are added. It is
    /// the same for a whole run, so the prompt cache keeps it.
    public static func system(sharedVariants: [SoundVariant]) -> String {
        let builtIn = Set(SoundCatalog.variants.map(\.id))
        let extra = sharedVariants.filter { !builtIn.contains($0.id) }.prefix(maxVariantsListed)
        let shared = extra.isEmpty ? "none" : "\n" + extra.map(describe).joined(separator: "\n")
        let oneShots = OneShotSound.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
        let transitions = SceneTransition.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
        return """
            You design the background soundscape for an audiobook: steady sounds of the place \
            where the story is, played under the narrator's voice the whole time, with some \
            gentle music. Each message gives what is known so far (the book's world, the current \
            scene and the places visited before, with what each was like last time) and the \
            passage that has just been read aloud, oldest sentence first. Decide the soundscape \
            for the moment the passage ends: where the characters are now, what that place is \
            like right now, and what it sounds like.

            Judge only the words given. Do not use anything you know about the book, its author \
            or its plot, and never set up a scene, weather or sound before the text reaches it.

            How to decide:
            - Where are the characters physically at the end of the passage? A place that is only \
            remembered, imagined, dreamed, written about in a letter or talked about does not \
            count: keep the current scene.
            - Every place has a sound. Infer what a listener would hear there even when the text \
            does not mention it: a ship at sea creaks and has water around it; woods by day have \
            leaves and birds; a packed school corridor has a crowd; an ordinary quiet room has \
            roomTone. Fit the book's world and era: no traffic before cars, no engines in a \
            medieval town. Answer with no sounds only when you cannot tell where the characters \
            are at all, or the passage ends on a chapter heading or a jump the text has not \
            described yet (then place "none" and confidence below 0.3).
            - Pick the most specific sound that fits. Each sound below is a family (crowd, river, \
            roomTone) with more specific kinds listed under it (crowd.schoolCorridor, \
            river.waterfall). Use the kind when the place clearly is that; otherwise the plain \
            family. A kind inherits everything from its family, so a kind of crowd still pauses \
            the music.
            - People make a ladder: roomTone (nobody else heard), hushedRoom (people keeping \
            quiet, no voices), murmur (a few low voices; the music stays), crowd (many voices \
            right around the characters; the music pauses). Climb or descend it as the place \
            fills, empties, hushes or erupts.
            - The state of a place changes its sound. When the text says what the place is like \
            now (empty, between lessons, everyone whispering about her, the fire dying, the hall \
            in uproar, the rain stopping), change the sounds to match and say that state in \
            `state`. The place guide below shows typical states and the sounds that go with \
            them; when the same state comes back later, give it the same sounds.
            - Weather carries over from place to place until the text says it changed. Indoors, \
            rain becomes rainIndoors. Thunder only while a storm is actually going on.
            - Returning to a known place: answer with its id and start from the sounds remembered \
            there (listed with the state they had), changing only what the text says changed. \
            A place not in the list: place "new" and a short name ("the Weasleys' kitchen"). \
            The same place under another name is still the known place.
            - Usually two or three sounds, at most five: one main sound and a few quieter ones \
            behind it (a hall: crowd full, fireplace faint; a street in rain: rain soft, city \
            faint). Never more than one kind of the same family.
            - Levels: faint (barely there), soft (in the background), full (the place's main \
            sound), loud (the sound presses in on the characters: a hall in uproar, a storm at \
            its height, beside a waterfall; rare).
            - crowd is for many people right around the characters whose words cannot be made \
            out. The music pauses while it plays, so use it only where a crowd is clearly there; \
            a few voices are murmur.
            - The sounds under "\(AmbientSound.Group.doing.title)" are what the characters are \
            doing, on top of the place's own sounds: footsteps while they walk, running in a \
            chase, breathing or a heartbeat when the passage dwells on it, swimming, climbing, a \
            fight, writing, a meal, work. Add one (at most one, soft or faint) only while the \
            passage has them doing it right now, and drop it the moment they stop, sit, arrive \
            or the passage moves on. They belong to the characters, not the place: a place is \
            never remembered with them.

            \(soundList)

            \(placeGuide)

            Specific sounds other books have added (kind (family): what it is): \(shared)

            New specific sounds:
            - When the place clearly calls for a steady sound that is a distinctly more specific \
            kind of one of the families and no listed kind fits, add it to newSounds: id (a \
            short camelCase name such as churchBells), of (the family it is a kind of; that \
            family's sound plays until a recording is found), about (what it is, up to ten words) \
            and search (two to five words to search a sound library with). Then use it as that \
            family's variant.
            - Only for a place the characters are in, not a passing mention; only a steady sound \
            that can loop (no single bangs or footsteps, no words that can be followed, no music); \
            at most one new sound per answer, and never one that is already listed. Almost always \
            newSounds is empty: the catalogue is large.

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

            Transitions:
            - transition says how the sound moves from the current scene to the new one when \
            the passage's last sentence is the very moment the characters move: out of a party \
            through a door (the door opens, the noise follows them, the door shuts on it and it \
            fades behind them), into a crowded room, out of a house into the open, into a car, \
            a carriage, a train or a boat, out of one, left standing as a train pulls away, \
            under water, asleep. The player plays it out over the next seconds, with the door, \
            the engine or the splash as one-off sounds.
            - Pick the one that fits the text; "none" when the scene does not change, when the \
            change is a plain cut (a new chapter somewhere else: quickCut is for a jump the \
            text itself makes), or when the characters were already there. Choosing one is \
            not a one-off sound: a knock before the door opens is still a oneShot.
            - A transition and a moment can go together: enterThroughDoor with swell when the \
            hall's noise floods in; stepInside with hush when a door shuts on a storm.

            The transitions:
            \(transitions)

            Also answer:
            - setting: indoors, outdoors, vehicle (a carriage, train, ship, spaceship) or unclear.
            - state: a few words on what the place is like right now ("between lessons", "after \
            hours, empty", "everyone whispering about her", "fire dying, late"), or "" when \
            nothing marks it out.
            - world: a few words on the book's setting so far (era, region, season, technology), \
            updated from the passage; repeat the previous note when nothing new is learned.
            - cue: up to ten words copied from the passage that best show the scene, or "" if the \
            scene is inferred.
            - confidence: from 0 to 1, how sure you are of the place and its sounds.
            """
    }

    /// The families by group, each with its kinds: the catalogue as the scorer reads it.
    static var soundList: String {
        var lines = ["The sounds (family: when to use it; then its kinds as family.kind: what it is):"]
        for group in AmbientSound.Group.allCases {
            let sounds = AmbientSound.allCases.filter { $0.group == group }
            guard !sounds.isEmpty else { continue }
            lines.append("\(group.title):")
            for sound in sounds {
                lines.append("- \(sound.rawValue): \(sound.guidance)")
                let kinds = SoundCatalog.variants(of: sound)
                if !kinds.isEmpty {
                    lines.append("  kinds: " + kinds.map { "\(sound.rawValue).\($0.id): \($0.about)" }.joined(separator: "; "))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The place guide as the scorer reads it.
    static var placeGuide: String {
        var lines = ["What places sound like, and how that changes with their state (typical; the text decides):"]
        for guide in SoundCatalog.placeGuide {
            let states = guide.states.map { "\($0.when) -> \($0.sounds)" }.joined(separator: "; ")
            lines.append("- \(guide.place): \(states)")
        }
        return lines.joined(separator: "\n")
    }

    /// The user message for one window. Variants in the built-in catalogue or already in
    /// the system prompt (`sharedVariants`) are not repeated.
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
            lines.append("Places visited before (most recent first, with what each was like last time):")
            for place in places {
                let state = place.state.map { ", \($0)" } ?? ""
                lines.append("- \(place.id) \"\(place.name)\" (\(place.setting.rawValue)\(state)): \(describe(place.layers))")
            }
        }
        let known = Set(sharedVariants.prefix(maxVariantsListed).map(\.id)).union(SoundCatalog.variants.map(\.id))
        let own = memory.variants.filter { !known.contains($0.id) }.prefix(maxVariantsListed)
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
        let state = scene.state.map { ", \($0)" } ?? ""
        return "\(place) (\(scene.setting.rawValue)\(state)): \(describe(scene.layers))"
    }

    /// "- churchBells (oldTown): church bells ringing across a town".
    static func describe(_ variant: SoundVariant) -> String {
        "- \(variant.id) (\(variant.of.rawValue)): \(variant.about)"
    }

    /// "fireplace soft, oldTown.churchBells faint".
    static func describe(_ layers: [SceneLayer]) -> String {
        guard !layers.isEmpty else { return "no sounds" }
        return layers.map { layer in "\(layer.key) \(layer.level.rawValue)" }.joined(separator: ", ")
    }

    /// The answer's JSON schema, for `output_config.format`. Structured outputs do not
    /// take array length limits, so the engine keeps the loudest five sounds itself.
    public static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "place": ["type": "string"],
                "placeName": ["type": "string"],
                "setting": ["type": "string", "enum": StoryScene.Setting.allCases.map(\.rawValue)],
                "state": ["type": "string"],
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
                "transition": ["type": "string", "enum": ["none"] + SceneTransition.allCases.map(\.rawValue)],
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
            "required": ["place", "placeName", "setting", "state", "sounds", "newSounds", "moment", "transition", "oneShot", "world", "cue", "confidence"],
            "additionalProperties": false,
        ]
    }
}
