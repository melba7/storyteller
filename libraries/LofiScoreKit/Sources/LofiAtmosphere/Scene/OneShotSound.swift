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
        }
    }

    /// Level relative to the other one-off sounds, in dB, for sounds that carry further
    /// or startle more than their measured loudness says.
    public var levelOffsetDB: Double {
        switch self {
        case .glassBreak, .phoneRing, .doorbell: -4
        case .doorSlam, .dogBark, .trainWhistle: -3
        case .clockChime, .horseNeigh: -2
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
