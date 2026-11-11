import Foundation
import LofiText

/// A single sound at one moment of the story: a clap of thunder, a knock at the door, a
/// clock striking. One-off sounds are an extra, off by default (a setting in the app).
///
/// They are kept rare and well under the voice, because sudden sounds pull attention
/// from what you are following far more than steady ones (see ``AmbientSound``). Each is
/// tied to the exact sentence that says it happens, found the same spoiler-safe way as
/// everything else: the sentence's own text and what came before it, never what follows.
///
/// Recordings live in `Atmosphere/OneShots/<Sound>/` (``OneShotLibrary``). New cases go at
/// the end, so saved tracks keep their meaning.
public enum OneShotSound: String, CaseIterable, Codable, Sendable, Hashable {
    case thunderClap
    case doorKnock
    case doorSlam
    case doorCreak
    case doorbell
    case phoneRing
    case bellToll
    case clockChime
    case glassBreak
    case dogBark
    case owlHoot
    case wolfHowl
    case horseNeigh
    case trainWhistle
    case shipHorn
    case schoolBell
    case roosterCrow
    case catMeow
    case carHorn
    // Added with the scene transitions and the theatrical extras
    case doorOpen
    case doorClose
    case carDoor
    case engineStart
    case engineStop
    case carDrivesOff
    case trainPullsAway
    case hoovesAway
    case splash
    case windowSlide
    case gateCreak
    case keyInLock
    case swordDraw
    case swordClash
    case matchStrike
    case glassClink
    case chairScrape
    case paperRustle
    case keysJingle
    case applause
    case cheer
    case laughter
    case thump
    case whipCrack
    case arrowWhoosh
    case kettleWhistle
    case bookClose
    case bedCreak
    case footstepsApproach
    case footstepsLeave
    case windGust
    case coinsClink
    case bottleUncork
    case pouringDrink
    case sirenPasses
    case elevatorDing
    case seagullCry
    case crowCaw
    case wingsFlutter
    case slap
    case shopBell
    case gavel
    case babyCry
    case chainsRattle

    /// Its folder under `Atmosphere/OneShots/`, e.g. "DoorKnock".
    public var folderName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// What it is, for Claude.
    public var guidance: String {
        switch self {
        case .thunderClap: "a single clap or crack of thunder"
        case .doorKnock: "knocking at a door"
        case .doorSlam: "a door slamming shut"
        case .doorCreak: "a door creaking open"
        case .doorbell: "a doorbell ringing"
        case .phoneRing: "a telephone ringing"
        case .bellToll: "a large bell tolling (a church or tower bell)"
        case .clockChime: "a clock striking or chiming the hour"
        case .glassBreak: "glass breaking or shattering"
        case .dogBark: "a dog barking"
        case .owlHoot: "an owl hooting"
        case .wolfHowl: "a wolf howling"
        case .horseNeigh: "a horse neighing or whinnying"
        case .trainWhistle: "a train whistle"
        case .shipHorn: "a ship's horn or foghorn"
        case .schoolBell: "a school bell ringing for the end of a lesson"
        case .roosterCrow: "a rooster crowing"
        case .catMeow: "a cat meowing"
        case .carHorn: "a car horn, once"
        case .doorOpen: "a door opening (the latch, the swing)"
        case .doorClose: "a door closing, not slammed"
        case .carDoor: "a car door shutting"
        case .engineStart: "an engine starting"
        case .engineStop: "an engine switched off"
        case .carDrivesOff: "a car driving away"
        case .trainPullsAway: "a train pulling out of a station"
        case .hoovesAway: "a horse or carriage going off at a trot"
        case .splash: "a splash: something or someone into water"
        case .windowSlide: "a window or shutter opened or closed"
        case .gateCreak: "an iron gate creaking"
        case .keyInLock: "a key turning in a lock, a bolt drawn"
        case .swordDraw: "a sword drawn from its scabbard"
        case .swordClash: "two blades meeting, once"
        case .matchStrike: "a match struck, a lamp or candle lit"
        case .glassClink: "glasses touched in a toast, a glass set down"
        case .chairScrape: "a chair pushed back, scraping the floor"
        case .paperRustle: "paper unfolded, a letter opened, pages shuffled"
        case .keysJingle: "keys jingling"
        case .applause: "applause"
        case .cheer: "a crowd cheering, once"
        case .laughter: "a burst of laughter from several people"
        case .thump: "a heavy thump, a fall, a body or a sack hitting the floor"
        case .whipCrack: "a whip cracked"
        case .arrowWhoosh: "an arrow loosed, flying past"
        case .kettleWhistle: "a kettle coming to the boil and whistling"
        case .bookClose: "a book shut"
        case .bedCreak: "a bed or floorboard creaking under weight"
        case .footstepsApproach: "footsteps coming nearer and stopping"
        case .footstepsLeave: "footsteps going away"
        case .windGust: "a single gust of wind, a draught through a door"
        case .coinsClink: "coins counted out or dropped"
        case .bottleUncork: "a bottle uncorked"
        case .pouringDrink: "a drink poured"
        case .sirenPasses: "a siren going past"
        case .elevatorDing: "a lift arriving, its bell"
        case .seagullCry: "a gull crying"
        case .crowCaw: "a crow or raven cawing"
        case .wingsFlutter: "a bird taking off, a flutter of wings"
        case .slap: "a slap"
        case .shopBell: "a bell over a shop door, a hand bell rung"
        case .gavel: "a gavel struck"
        case .babyCry: "a baby starting to cry"
        case .chainsRattle: "chains rattling"
        }
    }

    /// Words to search a sound library with, and the longest a recording is kept, in
    /// seconds (the rest is trimmed). The fetch script reads them from the exported
    /// catalogue (``SoundCatalog``).
    public var search: (queries: [String], longestSeconds: Double) {
        switch self {
        case .thunderClap: (["thunder clap", "thunder crack", "single thunder strike"], 8)
        case .doorKnock: (["knocking on door", "door knock"], 4)
        case .doorSlam: (["door slam", "door slamming shut"], 3)
        case .doorCreak: (["door creak", "creaky door opening"], 4)
        case .doorbell: (["doorbell ding dong", "doorbell"], 4)
        case .phoneRing: (["old telephone ring", "telephone ringing bell"], 6)
        case .bellToll: (["church bell toll single", "bell toll"], 8)
        case .clockChime: (["clock chime hour", "grandfather clock chime"], 12)
        case .glassBreak: (["glass break", "glass shatter"], 3)
        case .dogBark: (["dog bark", "dog barking"], 4)
        case .owlHoot: (["owl hoot", "tawny owl call"], 4)
        case .wolfHowl: (["wolf howl"], 7)
        case .horseNeigh: (["horse neigh", "horse whinny"], 4)
        case .trainWhistle: (["steam train whistle", "train whistle"], 6)
        case .shipHorn: (["ship horn", "foghorn"], 7)
        case .schoolBell: (["school bell ring", "school bell"], 5)
        case .roosterCrow: (["rooster crow", "cockerel crowing"], 4)
        case .catMeow: (["cat meow", "cat meowing"], 3)
        case .carHorn: (["car horn single", "car horn honk"], 3)
        case .doorOpen: (["door open", "door opening latch"], 3)
        case .doorClose: (["door close", "door closing"], 3)
        case .carDoor: (["car door close", "car door shut"], 2)
        case .engineStart: (["car engine start", "engine starting"], 5)
        case .engineStop: (["engine switch off", "car engine stop"], 4)
        case .carDrivesOff: (["car drives away", "car driving off", "car pulling away"], 12)
        case .trainPullsAway: (["train departing station", "train pulling away", "steam train leaving station"], 20)
        case .hoovesAway: (["horse trotting away", "horse carriage leaving", "horse hooves passing"], 12)
        case .splash: (["water splash", "big splash", "jump into water splash"], 3)
        case .windowSlide: (["window open slide", "window closing", "sash window"], 3)
        case .gateCreak: (["iron gate creak", "gate creaking open"], 4)
        case .keyInLock: (["key in lock turn", "door unlock key", "bolt draw"], 3)
        case .swordDraw: (["sword unsheathe", "sword draw scabbard"], 2)
        case .swordClash: (["sword clash single", "swords clash hit"], 2)
        case .matchStrike: (["match strike", "match light strike"], 3)
        case .glassClink: (["glass clink toast", "wine glasses clink"], 2)
        case .chairScrape: (["chair scrape floor", "chair pushed back"], 2)
        case .paperRustle: (["paper rustle", "letter unfold paper", "paper shuffle"], 3)
        case .keysJingle: (["keys jingle", "keyring jingle"], 3)
        case .applause: (["applause", "audience applause clapping"], 8)
        case .cheer: (["crowd cheer", "crowd cheering short"], 6)
        case .laughter: (["group laughter", "people laughing"], 5)
        case .thump: (["heavy thump", "body fall thud", "thud floor"], 2)
        case .whipCrack: (["whip crack"], 2)
        case .arrowWhoosh: (["arrow whoosh", "arrow release fly"], 2)
        case .kettleWhistle: (["kettle whistle", "kettle boiling whistle"], 8)
        case .bookClose: (["book close", "book closing thud"], 2)
        case .bedCreak: (["bed creak", "floorboard creak"], 3)
        case .footstepsApproach: (["footsteps approaching stop", "footsteps approach"], 6)
        case .footstepsLeave: (["footsteps walking away", "footsteps leaving"], 7)
        case .windGust: (["wind gust single", "wind gust"], 6)
        case .coinsClink: (["coins drop", "coins clink"], 3)
        case .bottleUncork: (["bottle uncork", "cork pop wine"], 2)
        case .pouringDrink: (["pouring drink glass", "pour liquid glass"], 4)
        case .sirenPasses: (["siren passing", "police siren pass by"], 10)
        case .elevatorDing: (["elevator ding", "lift bell arrive"], 3)
        case .seagullCry: (["seagull cry", "gull call single"], 4)
        case .crowCaw: (["crow caw", "raven caw"], 3)
        case .wingsFlutter: (["bird wings flutter take off", "pigeon wings flap"], 3)
        case .slap: (["slap face", "slap"], 1)
        case .shopBell: (["shop door bell", "hand bell ring"], 3)
        case .gavel: (["gavel strike", "judge gavel"], 2)
        case .babyCry: (["baby cry", "baby crying start"], 6)
        case .chainsRattle: (["chains rattle", "chain rattling"], 4)
        }
    }

    /// Level relative to the other one-off sounds, in dB, for sounds that carry further
    /// or startle more than their measured loudness says.
    public var levelOffsetDB: Double {
        switch self {
        case .glassBreak, .phoneRing, .doorbell: -4
        case .doorSlam, .dogBark, .trainWhistle, .carHorn: -3
        case .clockChime, .horseNeigh, .schoolBell: -2
        case .thunderClap, .shipHorn, .bellToll: 1
        case .whipCrack, .slap, .thump, .swordClash, .cheer, .applause, .babyCry, .sirenPasses: -4
        case .doorClose, .carDoor, .engineStart, .glassClink, .keysJingle, .laughter, .gavel, .shopBell, .elevatorDing: -3
        case .doorOpen, .engineStop, .chairScrape, .bookClose, .coinsClink, .chainsRattle, .kettleWhistle, .crowCaw, .seagullCry: -2
        case .matchStrike, .paperRustle, .bedCreak, .pouringDrink, .bottleUncork, .footstepsApproach, .footstepsLeave, .wingsFlutter, .windowSlide, .keyInLock: -1
        default: 0
        }
    }

    /// Accepts the folder spelling ("DoorKnock", "door knock", "door_knock") as well as the raw value.
    public init?(lenient text: String) {
        let squashed = text.lowercased().filter { $0.isLetter }
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == squashed }) else { return nil }
        self = match
    }
}

/// A one-off sound found in a passage: which sound, and the words that say it happens.
public struct OneShotMention: Sendable, Hashable {
    public var sound: OneShotSound
    /// Words copied from the passage, ending where the sound happens.
    public var quote: String

    public init(sound: OneShotSound, quote: String) {
        self.sound = sound
        self.quote = quote
    }

    /// Where the quote is in the window: the line (the newest line that has it) and how
    /// many of that line's words come before the end of the quote, so the sound can be
    /// timed inside the sentence. Nil when the quote is not in the window.
    public func locate(in window: CausalWindow) -> (line: Int, wordsBefore: Int, words: Int)? {
        let wanted = Self.words(quote)
        guard !wanted.isEmpty else { return nil }
        for index in window.lines.indices.reversed() {
            let words = Self.words(window.lines[index].text)
            guard words.count >= wanted.count else { continue }
            for start in stride(from: words.count - wanted.count, through: 0, by: -1)
                where Array(words[start..<(start + wanted.count)]) == wanted {
                // The sound happens around the last quoted word.
                return (index, start + wanted.count - 1, words.count)
            }
        }
        return nil
    }

    /// Lowercased words without punctuation, so a quote matches whatever its quote marks
    /// or dashes were.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            .map { $0.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }
}
