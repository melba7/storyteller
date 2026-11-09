import Foundation

/// One sound in a scene and how loud it is.
public struct SceneLayer: Codable, Sendable, Hashable {
    public var sound: AmbientSound
    public var level: AmbientLevel

    public init(_ sound: AmbientSound, _ level: AmbientLevel = .soft) {
        self.sound = sound
        self.level = level
    }
}

/// Where the story is and what it sounds like there, at one point in the book.
///
/// A scene is judged only from text that has already been narrated. Its `placeID`
/// ties it to the other times the story was in the same place, so a return to the
/// tavern brings back the tavern's own fire, and a change ("the fire had burned
/// low") is a change of layers in the same place.
public struct StoryScene: Codable, Sendable, Hashable {
    public enum Setting: String, CaseIterable, Codable, Sendable {
        case indoors
        case outdoors
        /// A carriage, a train, a ship, a spaceship.
        case vehicle
        /// Not said or not clear.
        case unclear
    }

    /// The place's id in the book's ``PlaceMemory``, like "p3". Nil when the passage
    /// gives no place (a letter, a dream, pure reflection).
    public var placeID: String?
    /// A short name for the place, for the debug screen and the timeline printout.
    public var placeName: String?
    public var setting: Setting
    /// Sorted by sound, at most one layer per sound.
    public private(set) var layers: [SceneLayer]
    /// How sure the scorer was, 0...1.
    public var confidence: Double
    /// A few words from the passage that set the scene, for reviewing a track. Never played.
    public var cue: String?

    public static let maxLayers = 4

    public init(
        placeID: String?,
        placeName: String? = nil,
        setting: Setting = .unclear,
        layers: [SceneLayer],
        confidence: Double = 1,
        cue: String? = nil
    ) {
        self.placeID = placeID
        self.placeName = placeName
        self.setting = setting
        self.layers = Self.normalized(layers)
        self.confidence = confidence.isFinite ? min(1, max(0, confidence)) : 0
        self.cue = cue
    }

    /// No place and no sound.
    public static let silent = StoryScene(placeID: nil, layers: [], confidence: 1)

    public var isSilent: Bool { layers.isEmpty }

    public var sounds: Set<AmbientSound> { Set(layers.map(\.sound)) }

    public func level(of sound: AmbientSound) -> AmbientLevel? {
        layers.first { $0.sound == sound }?.level
    }

    /// True when the scene would make the music step aside.
    public var replacesMusic: Bool {
        layers.contains { $0.sound.musicPolicy == .replacesMusic && $0.level >= .soft }
    }

    /// Same place and the same sounds at the same levels: nothing to change.
    public func soundsLike(_ other: StoryScene) -> Bool {
        placeID == other.placeID && layers == other.layers
    }

    /// One layer per sound (the loudest wins), loudest first, at most ``maxLayers``.
    static func normalized(_ layers: [SceneLayer]) -> [SceneLayer] {
        var best: [AmbientSound: AmbientLevel] = [:]
        for layer in layers {
            best[layer.sound] = max(best[layer.sound] ?? layer.level, layer.level)
        }
        let order = Dictionary(uniqueKeysWithValues: AmbientSound.allCases.enumerated().map { ($1, $0) })
        let sorted = best.map { SceneLayer($0.key, $0.value) }.sorted {
            if $0.level != $1.level { return $0.level > $1.level }
            return order[$0.sound]! < order[$1.sound]!
        }
        return Array(sorted.prefix(maxLayers))
    }

    private enum CodingKeys: String, CodingKey {
        case placeID, placeName, setting, layers, confidence, cue
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            placeID: try c.decodeIfPresent(String.self, forKey: .placeID),
            placeName: try c.decodeIfPresent(String.self, forKey: .placeName),
            setting: try c.decodeIfPresent(Setting.self, forKey: .setting) ?? .unclear,
            layers: try c.decodeIfPresent([SceneLayer].self, forKey: .layers) ?? [],
            confidence: try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1,
            cue: try c.decodeIfPresent(String.self, forKey: .cue)
        )
    }
}

extension StoryScene: CustomStringConvertible {
    public var description: String {
        let place = placeName.map { "\(placeID ?? "?") \($0)" } ?? (placeID ?? "nowhere")
        let sounds = layers.isEmpty ? "silence" : layers.map { "\($0.sound.rawValue) \($0.level.rawValue)" }.joined(separator: ", ")
        return "\(place) [\(setting.rawValue)]: \(sounds)"
    }
}
