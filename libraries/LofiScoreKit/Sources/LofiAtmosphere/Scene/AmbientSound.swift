import Foundation

/// The background sounds a scene can have. One folder of recordings per sound in the
/// atmosphere library (see ``AmbienceLibrary``).
///
/// Every sound is a steady bed that loops seamlessly. There are no one-shot effects
/// (a door slam, a single thunderclap): listening research on the "irrelevant sound
/// effect" finds that sudden, changing sounds pull attention away from what you are
/// following, while smooth, steady sounds do the least harm. Sounds that would clash
/// with the music, such as a crowd, make the music step aside while they play
/// (``musicPolicy``).
///
/// New cases go at the end, so saved tracks and libraries keep their meaning.
public enum AmbientSound: String, CaseIterable, Codable, Sendable, Hashable, CodingKeyRepresentable {
    // Weather
    case rain
    case heavyRain
    case rainIndoors
    case thunder
    case wind
    case strongWind
    case snow
    // Fire
    case fireplace
    case campfire
    // Water
    case seaShore
    case openSea
    case river
    case dripping
    // Nature
    case forest
    case birdsong
    case nightInsects
    case nightForest
    case swamp
    // People, places and travel
    case crowd
    case city
    case oldTown
    case horses
    case train
    case ship
    case machinery
    case clock

    /// Sounds that belong to the weather rather than to a place.
    public enum Scope: String, Codable, Sendable {
        /// Rain is the same rain whichever street you are in, so the same recording
        /// keeps playing as the story moves between places.
        case weather
        /// A fireplace belongs to its room: each place gets its own recording, and the
        /// same one every time the story comes back.
        case place
    }

    /// What the music does while this sound plays.
    public enum MusicPolicy: String, Codable, Sendable {
        /// The sound sits under the music.
        case underMusic
        /// The music fades out while this sound plays and comes back after: a crowd and
        /// music together would be two layers of busy sound under the voice.
        case replacesMusic
    }

    public var scope: Scope {
        switch self {
        case .rain, .heavyRain, .rainIndoors, .thunder, .wind, .strongWind, .snow: .weather
        default: .place
        }
    }

    public var musicPolicy: MusicPolicy {
        switch self {
        case .crowd: .replacesMusic
        default: .underMusic
        }
    }

    /// Folder name in the atmosphere library, e.g. "HeavyRain".
    public var folderName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// When to use the sound. This is what Claude reads when it picks sounds, so it
    /// describes situations, not recordings.
    public var guidance: String {
        switch self {
        case .rain: "steady rain, heard outdoors or under a light shelter"
        case .heavyRain: "a downpour or storm rain, outdoors"
        case .rainIndoors: "rain heard from inside: on a roof, a window or a tent"
        case .thunder: "distant rolling thunder; only while a storm is actually going on"
        case .wind: "a breeze in the open: fields, hills, a ship's deck, through trees"
        case .strongWind: "a gale or howling wind: storms, mountain tops, blizzards, a moor at night"
        case .snow: "the hush of a snowy day outdoors: very soft, muffled air"
        case .fireplace: "a fire in a hearth, stove or brazier, indoors"
        case .campfire: "an outdoor fire: a camp, a bonfire, torches"
        case .seaShore: "waves on a beach or rocks: a coast, a harbour, cliffs"
        case .openSea: "aboard or beside a boat at sea: water against the hull, the swell"
        case .river: "running water nearby: a stream, a brook, a river, a fountain"
        case .dripping: "drips echoing in a cave, cellar, dungeon, mine, tunnel or sewer"
        case .forest: "woods by day: leaves, branches, birds in the distance"
        case .birdsong: "a garden, park, meadow or countryside by day: birdsong"
        case .nightInsects: "a warm night outdoors: crickets and insects"
        case .nightForest: "woods or countryside at night: an owl now and then, a soft breeze"
        case .swamp: "a marsh, bog, swamp or lake shore: frogs and insects"
        case .crowd: "many people around whose words cannot be made out: a busy school corridor, a market, a feast or dining hall, a station, a busy inn"
        case .city: "a modern town or city around you: distant traffic, no single voices"
        case .oldTown: "a town or village street before cars: hooves, carts, footsteps, distant bells"
        case .horses: "riding, or travelling in a horse-drawn carriage or cart: hooves and wheels"
        case .train: "inside a moving train: wheels and rails"
        case .ship: "aboard a wooden sailing ship: creaking timbers and ropes"
        case .machinery: "engines or machines running: a spaceship, an engine room, a factory, a car's cabin"
        case .clock: "a quiet room where a clock ticks: a study, a parlour, a waiting room"
        }
    }

    /// Level of the sound relative to the atmosphere's bed level, in dB, at "full".
    /// Some sounds carry further than others at the same measured loudness: a ticking
    /// clock or a crowd is noticed at a much lower level than rain.
    public var levelOffsetDB: Double {
        switch self {
        case .clock: -8
        case .crowd: -3
        case .dripping, .nightForest, .thunder: -2
        case .machinery, .train: -1
        case .heavyRain, .strongWind: 1
        default: 0
        }
    }

    /// Accepts the folder spelling ("HeavyRain", "heavy rain", "heavy_rain") as well as the raw value.
    public init?(lenient text: String) {
        let squashed = text.lowercased().filter { $0.isLetter }
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == squashed }) else { return nil }
        self = match
    }
}

/// How loud a sound is in its scene.
public enum AmbientLevel: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    /// Barely there: rain behind closed shutters, a far-off river.
    case faint
    /// Clearly there but in the background.
    case soft
    /// The scene's main sound.
    case full

    /// Offset from the sound's full level, in dB.
    public var offsetDB: Double {
        switch self {
        case .faint: -10
        case .soft: -5
        case .full: 0
        }
    }

    public static func < (lhs: AmbientLevel, rhs: AmbientLevel) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .faint: 0
        case .soft: 1
        case .full: 2
        }
    }
}
