import Foundation

/// The background sounds a scene can have. One folder of recordings per sound in the
/// atmosphere library (see ``AmbienceLibrary``).
///
/// Every sound is a steady bed that loops seamlessly. Listening research on the
/// "irrelevant sound effect" finds that sudden, changing sounds pull attention away from
/// what you are following, while smooth, steady sounds do the least harm. Single sounds
/// (a door slam, a clap of thunder) are a separate, rare extra the listener turns on:
/// ``OneShotSound``. Sounds that would clash
/// with the music, such as a crowd, make the music step aside while they play
/// (``musicPolicy``).
///
/// Each sound is a *family*: the more specific kinds of it (a café is a kind of crowd, a
/// waterfall a kind of river) are ``SoundVariant``s, listed in ``SoundCatalog``. A family
/// decides the behaviour (weather or place, what the music does, the filter, the level,
/// the synthesised stand-in); a variant only changes the recording.
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
    // Rooms, from empty to full of people (added with the big catalogue)
    case roomTone
    case hushedRoom
    case murmur
    case emptyHall
    case electricHum
    case kitchen
    case workshop
    case farmyard
    // More vehicles
    case motorVehicle
    case aircraft
    case spaceship
    // Elsewhere
    case deepDrone
    // What the characters are doing (added with the scene transitions). These follow the
    // characters, not the place: footsteps are the same footsteps in every corridor.
    case footsteps
    case running
    case breathing
    case heartbeat
    case swimming
    case climbing
    case fighting
    case writing
    case meal
    case work

    /// Sounds that belong to the weather, the place, or the characters themselves.
    public enum Scope: String, Codable, Sendable {
        /// Rain is the same rain whichever street you are in, so the same recording
        /// keeps playing as the story moves between places.
        case weather
        /// A fireplace belongs to its room: each place gets its own recording, and the
        /// same one every time the story comes back.
        case place
        /// Footsteps belong to the characters: the same recording follows them from
        /// place to place, and a place does not remember them (see ``PlaceMemory``).
        case activity
    }

    /// What the music does while this sound plays.
    public enum MusicPolicy: String, Codable, Sendable {
        /// The sound sits under the music.
        case underMusic
        /// The music fades out while this sound plays and comes back after: a crowd and
        /// music together would be two layers of busy sound under the voice.
        case replacesMusic
    }

    /// The groups the sounds are listed under, for the scorer and the docs.
    public enum Group: String, CaseIterable, Codable, Sendable {
        case weather
        case fire
        case water
        case nature
        case rooms
        case people
        case places
        case travel
        case elsewhere
        /// What the characters are doing: the sounds of their own actions.
        case doing

        public var title: String {
            switch self {
            case .weather: "Weather"
            case .fire: "Fire"
            case .water: "Water"
            case .nature: "Nature"
            case .rooms: "Rooms"
            case .people: "People"
            case .places: "Towns and places"
            case .travel: "Travel"
            case .elsewhere: "Elsewhere"
            case .doing: "What the characters are doing"
            }
        }
    }

    public var scope: Scope {
        switch self {
        case .rain, .heavyRain, .rainIndoors, .thunder, .wind, .strongWind, .snow: .weather
        case .footsteps, .running, .breathing, .heartbeat, .swimming, .climbing, .fighting, .writing, .meal, .work: .activity
        default: .place
        }
    }

    public var musicPolicy: MusicPolicy {
        switch self {
        case .crowd: .replacesMusic
        default: .underMusic
        }
    }

    /// True for sounds made of human voices, which get the speech-safe filter so no
    /// words can be made out under the narrator.
    public var isVoices: Bool {
        switch self {
        case .crowd, .murmur: true
        default: false
        }
    }

    public var group: Group {
        switch self {
        case .rain, .heavyRain, .rainIndoors, .thunder, .wind, .strongWind, .snow: .weather
        case .fireplace, .campfire: .fire
        case .seaShore, .openSea, .river, .dripping: .water
        case .forest, .birdsong, .nightInsects, .nightForest, .swamp, .farmyard: .nature
        case .roomTone, .hushedRoom, .emptyHall, .electricHum, .clock, .kitchen, .workshop: .rooms
        case .murmur, .crowd: .people
        case .city, .oldTown: .places
        case .horses, .train, .ship, .machinery, .motorVehicle, .aircraft, .spaceship: .travel
        case .deepDrone: .elsewhere
        case .footsteps, .running, .breathing, .heartbeat, .swimming, .climbing, .fighting, .writing, .meal, .work: .doing
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
        case .river: "running water nearby: a stream, a brook, a river, a fountain, a tap"
        case .dripping: "drips echoing in a cave, cellar, dungeon, mine, tunnel or sewer"
        case .forest: "woods by day: leaves, branches, birds in the distance"
        case .birdsong: "a garden, park, meadow or countryside by day: birdsong"
        case .nightInsects: "a warm night outdoors: crickets and insects"
        case .nightForest: "woods or countryside at night: an owl now and then, a soft breeze"
        case .swamp: "a marsh, bog, swamp, pond or lake shore: frogs and insects"
        case .crowd: "many people right around the characters, words not made out: a packed corridor, a market, a feast or dining hall, a station, a busy inn. The music pauses for it"
        case .city: "a modern town or city around you: distant traffic, no single voices"
        case .oldTown: "a town or village street before cars: hooves, carts, footsteps, distant bells"
        case .horses: "riding, or travelling by horse, carriage, cart, caravan or sled: hooves and wheels"
        case .train: "inside a moving train, tram or underground train: wheels and rails"
        case .ship: "aboard a wooden sailing ship: creaking timbers and ropes"
        case .machinery: "engines or machines running: an engine room, a factory, a mill, a generator"
        case .clock: "a quiet room where a clock ticks: a study, a parlour, a waiting room"
        case .roomTone: "an ordinary quiet room with nobody else making a sound: the faint hush and hum of a house or building. The default indoors when nothing else is heard"
        case .hushedRoom: "a quiet room with people keeping quiet, no voices: pages turning, pens, chairs shifting, a cough: a library, a classroom at work, an exam, a church before the service"
        case .murmur: "a few people talking low nearby, words not made out: whispers in a corridor, the next table, voices through a wall, a small group. The music stays"
        case .emptyHall: "a big empty indoor space with an echo: a corridor after hours, a hospital or castle corridor, a stairwell, a cathedral, a museum, a garage: distant footsteps and doors"
        case .electricHum: "the hum of electric light, appliances, monitors or ventilation: an office, a hospital ward, a lab, a server room, a basement, a diner at night"
        case .kitchen: "cooking going on: a sizzle, pots, water, chopping, a kettle: a home kitchen, a restaurant kitchen, a camp cook"
        case .workshop: "hand work going on: a smithy, a carpenter, a sewing room, a garage, a printing shop, a loom"
        case .farmyard: "a farm: hens, cattle, sheep, a dog far off, a breeze: a farmyard, a barn, a stable, a pasture"
        case .motorVehicle: "riding inside a motor vehicle: a car, taxi, bus, truck or motorbike: engine and road"
        case .aircraft: "inside an aircraft: an airliner's cabin, a small plane, a helicopter, an airship"
        case .spaceship: "inside a spacecraft or space station: a deep hum, ventilation, faint instruments"
        case .deepDrone: "a deep steady presence with no natural source: the void outside a hull, a dream, a magical stillness, a dread. Use sparingly, and only where the place has no sound of its own"
        case .footsteps: "the characters walking, while the passage has them on the move: on gravel, a wooden floor, stone, snow, leaves, sand, stairs. Soft or faint, beside the place's own sounds, and dropped the moment they stop or sit"
        case .running: "the characters running or fleeing: fast footsteps, a chase. Only while they run"
        case .breathing: "breathing heard close: heavy after effort, panicked in fear, the slow breath of someone asleep beside them, breath inside a mask or helmet. Faint, and only while the passage dwells on it"
        case .heartbeat: "a heartbeat heard close, in dread, effort or stillness. Faint and rare; only while the passage dwells on it"
        case .swimming: "the characters in the water by their own effort: swimming, wading, treading water. Only while they are in it"
        case .climbing: "the characters climbing: a rock face, a rope, a ladder, a tree, loose scree. Only while they climb"
        case .fighting: "a fight the characters are in or right beside: swords, fists, a battle around them. Only while it goes on"
        case .writing: "the characters writing or reading close by: a quill or pen on paper, a pencil, typing, pages turning. Faint"
        case .meal: "a meal being eaten where the characters sit: cutlery on plates, cups, a table. Beside the place's own sounds"
        case .work: "manual work the characters are doing or standing beside: digging, chopping wood, sweeping, scrubbing, hammering, sawing, harvesting. Only while it goes on"
        }
    }

    /// Level of the sound relative to the atmosphere's bed level, in dB, at "full".
    /// Some sounds carry further than others at the same measured loudness: a ticking
    /// clock or a crowd is noticed at a much lower level than rain.
    public var levelOffsetDB: Double {
        switch self {
        case .clock: -8
        case .roomTone: -6
        case .electricHum: -5
        case .hushedRoom, .murmur, .deepDrone: -4
        case .crowd: -3
        case .dripping, .nightForest, .thunder, .emptyHall, .spaceship: -2
        case .machinery, .train, .kitchen, .motorVehicle, .aircraft: -1
        case .heavyRain, .strongWind: 1
        case .writing: -8
        case .breathing, .heartbeat: -6
        case .footsteps, .climbing, .meal: -4
        case .running, .work: -3
        case .swimming, .fighting: -2
        default: 0
        }
    }

    /// Words to search a sound library with for recordings of the plain sound. The fetch
    /// script reads them from the exported catalogue (``SoundCatalog``).
    public var searchQueries: [String] {
        switch self {
        case .rain: ["light rain ambience", "gentle rain", "steady rain"]
        case .heavyRain: ["heavy rain downpour", "heavy rain ambience", "torrential rain"]
        case .rainIndoors: ["rain on window", "rain on roof interior", "rain inside house"]
        case .thunder: ["distant thunderstorm rain", "thunder rumble rain ambience"]
        case .wind: ["gentle wind ambience", "soft wind", "wind field"]
        case .strongWind: ["strong wind howling", "storm wind gusts", "gale wind"]
        case .snow: ["winter wind snow ambience", "snowy quiet winter ambience", "snow forest winter"]
        case .fireplace: ["fireplace crackling", "fireplace fire crackle", "wood stove crackle"]
        case .campfire: ["campfire crackling outdoors", "campfire night"]
        case .seaShore: ["waves beach ambience", "ocean waves shore", "waves rocks"]
        case .openSea: ["open sea waves boat", "ocean swell", "boat hull water"]
        case .river: ["river stream ambience", "babbling brook", "creek water flowing"]
        case .dripping: ["cave dripping water", "water drips cave ambience"]
        case .forest: ["forest ambience day", "woodland ambience birds wind"]
        case .birdsong: ["birdsong morning", "dawn chorus birds", "garden birds"]
        case .nightInsects: ["crickets night", "night insects ambience"]
        case .nightForest: ["night forest ambience", "forest at night owl"]
        case .swamp: ["swamp frogs night", "marsh frogs ambience"]
        case .crowd: ["crowd murmur indoor", "walla crowd indistinct", "school hallway ambience"]
        case .city: ["city street ambience", "city traffic distant ambience"]
        case .oldTown: ["medieval town ambience", "market square ambience horses", "village square ambience"]
        case .horses: ["horse carriage hooves cobblestones", "horse drawn carriage"]
        case .train: ["train interior ambience", "steam train journey"]
        case .ship: ["ship creaking wood", "sailing ship ambience"]
        case .machinery: ["factory machinery ambience", "engine room ambience"]
        case .clock: ["clock ticking", "grandfather clock ticking"]
        case .roomTone: ["room tone quiet house", "empty room ambience quiet", "house interior room tone"]
        case .hushedRoom: ["library ambience quiet pages", "quiet classroom ambience", "exam hall ambience"]
        case .murmur: ["quiet conversation murmur distant", "people whispering ambience", "muffled voices next room"]
        case .emptyHall: ["empty corridor ambience footsteps", "large hall reverb ambience", "hospital corridor ambience"]
        case .electricHum: ["fluorescent light hum", "air conditioning hum room", "electrical hum ambience"]
        case .kitchen: ["kitchen cooking ambience", "restaurant kitchen ambience", "frying pan sizzle kitchen"]
        case .workshop: ["workshop ambience tools", "blacksmith hammering ambience", "carpentry workshop"]
        case .farmyard: ["farm ambience animals", "farmyard chickens cows", "barn ambience"]
        case .motorVehicle: ["car interior driving", "driving car ambience interior", "bus interior ambience"]
        case .aircraft: ["airplane cabin ambience", "aircraft cabin interior flight"]
        case .spaceship: ["spaceship interior hum", "sci-fi spaceship ambience hum", "space station ambience"]
        case .deepDrone: ["deep space ambience", "dark ambience low rumble", "eerie ambience low hum"]
        case .footsteps: ["footsteps walking loop", "walking footsteps gravel", "footsteps wooden floor walking"]
        case .running: ["running footsteps loop", "footsteps running outdoor", "running footsteps corridor"]
        case .breathing: ["heavy breathing", "breathing close loop", "breathing slow"]
        case .heartbeat: ["heartbeat loop", "heart beat slow", "heartbeat fast"]
        case .swimming: ["swimming strokes water", "swimming loop", "wading water walking"]
        case .climbing: ["rock climbing sounds", "climbing rope ladder", "scrambling rocks loose"]
        case .fighting: ["sword fight ambience", "medieval battle ambience", "fist fight sounds"]
        case .writing: ["writing quill on paper", "pen writing paper", "pencil writing paper"]
        case .meal: ["cutlery plates dinner ambience", "dinner table dishes cutlery", "tea cups saucers"]
        case .work: ["digging shovel dirt loop", "chopping wood axe", "hammering nails"]
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
    /// The sound presses in on the characters: a hall in uproar, a storm at its height,
    /// a waterfall beside them, a factory floor. Rare.
    case loud

    /// Offset from the sound's full level, in dB.
    public var offsetDB: Double {
        switch self {
        case .faint: -8
        case .soft: -3
        case .full: 0
        case .loud: 4
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
        case .loud: 3
        }
    }

    /// One step quieter (faint stays faint).
    public var quieter: AmbientLevel {
        switch self {
        case .faint, .soft: .faint
        case .full: .soft
        case .loud: .full
        }
    }

    /// A level from an answer's spelling; unknown words give nil.
    public init?(lenient text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
