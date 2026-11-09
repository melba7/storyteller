import Foundation
import LofiMood
import LofiText

/// What ``ClaudeSceneEngine`` sends: the rules and the sound list as the system prompt;
/// the book's world, the current scene, the places visited so far and the passage as the
/// user message; and a JSON schema for the answer.
public enum ClaudeScenePrompt {
    /// Bump when the wording or schema changes; engine ids and saved tracks record it.
    public static let version = 1

    /// Places listed with each passage, most recent first.
    public static let maxPlacesListed = 15

    public static var system: String {
        let sounds = AmbientSound.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
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

            Also answer:
            - setting: indoors, outdoors, vehicle (a carriage, train, ship, spaceship) or unclear.
            - world: a few words on the book's setting so far (era, region, season, technology), \
            updated from the passage; repeat the previous note when nothing new is learned.
            - cue: up to ten words copied from the passage that best show the scene, or "" if the \
            scene is inferred.
            - confidence: from 0 to 1, how sure you are of the place and its sounds.
            """
    }

    /// The user message for one window.
    public static func message(for window: CausalWindow, memory: PlaceMemory, maxWords: Int = 400) -> String {
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
                let sounds = place.layers.isEmpty ? "no sounds" : place.layers.map { "\($0.sound.rawValue) \($0.level.rawValue)" }.joined(separator: ", ")
                lines.append("- \(place.id) \"\(place.name)\" (\(place.setting.rawValue)): \(sounds)")
            }
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
        let sounds = scene.layers.isEmpty ? "no sounds" : scene.layers.map { "\($0.sound.rawValue) \($0.level.rawValue)" }.joined(separator: ", ")
        return "\(place) (\(scene.setting.rawValue)): \(sounds)"
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
                        ],
                        "required": ["sound", "level"],
                        "additionalProperties": false,
                    ] as [String: Any],
                ] as [String: Any],
                "world": ["type": "string"],
                "cue": ["type": "string"],
                "confidence": ["type": "number"],
            ] as [String: Any],
            "required": ["place", "placeName", "setting", "sounds", "world", "cue", "confidence"],
            "additionalProperties": false,
        ]
    }
}
