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
