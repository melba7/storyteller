import Foundation
import LofiScoreCore

/// A chord: its root in semitones above the key's tonic, and its notes above that root.
public struct Chord: Sendable, Hashable, Codable {
    public var degree: Int
    public var intervals: [Int]

    public init(_ degree: Int, _ intervals: [Int]) {
        self.degree = degree
        self.intervals = intervals
    }

    public static let maj7 = [0, 4, 7, 11]
    public static let maj9 = [0, 4, 7, 11, 14]
    public static let add9 = [0, 4, 7, 14]
    public static let sixNine = [0, 4, 7, 9, 14]
    public static let dom7 = [0, 4, 7, 10]
    public static let dom7flat9 = [0, 4, 7, 10, 13]
    public static let sus2 = [0, 2, 7, 14]
    public static let min7 = [0, 3, 7, 10]
    public static let min9 = [0, 3, 7, 10, 14]
    public static let min6 = [0, 3, 7, 9]
    public static let minMaj7 = [0, 3, 7, 11]
    public static let halfDim = [0, 3, 6, 10]
    public static let dim7 = [0, 3, 6, 9]
    public static let maj7sharp11 = [0, 4, 7, 11, 18]
}

/// How the drums play.
public enum DrumStyle: String, Sendable, Hashable, Codable {
    case none
    /// Quiet kick and a rim click on 2 and 4.
    case soft
    /// The classic head-nod pattern.
    case boomBap
    /// Busier kick and sixteenth hats.
    case driving
    /// Kick on 1, snare on 3: slow and heavy.
    case halfTime
}

/// How the bass plays.
public enum BassStyle: String, Sendable, Hashable, Codable {
    case none
    case whole
    case halves
    case syncopated
    case eighths
}

/// Everything that makes one placeholder track: tempo, key, chords, groove and texture.
///
/// The recipes are original, written for this project. They only need to sound like the
/// right mood of lofi until Mo's real tracks replace them.
public struct PlaceholderRecipe: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var bucket: MoodBucket
    public var bpm: Double
    /// Human-readable key, such as "F major".
    public var key: String
    /// MIDI note of the key's tonic (any octave; voicings are placed automatically).
    public var tonic: Int
    public var minor: Bool
    /// One chord per bar, repeated for the length of the track.
    public var progression: [Chord]
    public var bars: Int
    /// 0 is straight; 0.33 is a full triplet swing.
    public var swing: Double
    public var drums: DrumStyle
    /// How many of the possible hi-hat hits play, 0...1.
    public var hats: Double
    public var bass: BassStyle
    /// How busy the melody is, 0...1.
    public var melody: Double
    /// Low-pass cutoff of the whole mix, in Hz. Lower is warmer and duller.
    public var brightness: Double
    /// Vinyl crackle and hiss, 0...1.
    public var crackle: Double
    /// Tape wobble depth, in cents.
    public var wobble: Double
    /// Restrikes the chord on the "and" of beat 2.
    public var chordStabs: Bool
    public var intensity: Double
    public var seed: UInt64

    public var barLength: TimeInterval { 4 * 60 / bpm }
    public var duration: TimeInterval { Double(bars) * barLength }

    /// A one-line description, stored as the track's "prompt" in library.json.
    public var summary: String {
        "\(bucket.rawValue) placeholder: \(Int(bpm)) BPM, \(key), \(drums.rawValue) drums, \(bass.rawValue) bass"
    }

    public init(
        id: String, bucket: MoodBucket, bpm: Double, key: String, tonic: Int, minor: Bool,
        progression: [Chord], bars: Int, swing: Double, drums: DrumStyle, hats: Double,
        bass: BassStyle, melody: Double, brightness: Double, crackle: Double, wobble: Double,
        chordStabs: Bool = false, intensity: Double, seed: UInt64
    ) {
        self.id = id
        self.bucket = bucket
        self.bpm = bpm
        self.key = key
        self.tonic = tonic
        self.minor = minor
        self.progression = progression
        self.bars = bars
        self.swing = swing
        self.drums = drums
        self.hats = hats
        self.bass = bass
        self.melody = melody
        self.brightness = brightness
        self.crackle = crackle
        self.wobble = wobble
        self.chordStabs = chordStabs
        self.intensity = intensity
        self.seed = seed
    }
}

extension PlaceholderRecipe {
    /// Two hand-written recipes per mood. Asking for more makes transposed variations.
    public static func defaults(perMood: Int = 2) -> [PlaceholderRecipe] {
        let count = max(1, perMood)
        var result: [PlaceholderRecipe] = []
        for bucket in MoodBucket.allCases {
            let base = handWritten.filter { $0.bucket == bucket }
            for index in 0..<count {
                var recipe = base[index % base.count]
                if index >= base.count {
                    let shift = 2 * (index / base.count)
                    recipe.tonic += shift
                    recipe.key = Self.transposedKeyName(recipe.key, by: shift)
                    recipe.bpm += Double(index % 2 == 0 ? 3 : -3)
                    recipe.seed = recipe.seed &* 31 &+ UInt64(index)
                }
                recipe.id = "\(bucket.rawValue)-\(index + 1)"
                result.append(recipe)
            }
        }
        return result
    }

    private static let noteNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    private static func transposedKeyName(_ key: String, by semitones: Int) -> String {
        let parts = key.split(separator: " ", maxSplits: 1)
        guard let name = parts.first, let index = noteNames.firstIndex(of: String(name)) else { return key }
        let mode = parts.count > 1 ? " " + parts[1] : ""
        return noteNames[(index + semitones) % 12] + mode
    }

    static let handWritten: [PlaceholderRecipe] = [
        // Calm: unhurried major sevenths, soft drums, a little vinyl.
        PlaceholderRecipe(
            id: "calm-a", bucket: .calm, bpm: 72, key: "F major", tonic: 53, minor: false,
            progression: [Chord(0, Chord.maj9), Chord(9, Chord.min9), Chord(2, Chord.min7), Chord(7, Chord.sus2)],
            bars: 12, swing: 0.15, drums: .soft, hats: 0.4, bass: .whole, melody: 0.2,
            brightness: 2800, crackle: 0.4, wobble: 6, intensity: 0.2, seed: 101
        ),
        PlaceholderRecipe(
            id: "calm-b", bucket: .calm, bpm: 68, key: "D major", tonic: 50, minor: false,
            progression: [Chord(0, Chord.maj7), Chord(5, Chord.maj7), Chord(4, Chord.min7), Chord(9, Chord.min7)],
            bars: 10, swing: 0.12, drums: .soft, hats: 0.3, bass: .whole, melody: 0.15,
            brightness: 2600, crackle: 0.35, wobble: 5, intensity: 0.15, seed: 102
        ),
        // Cozy: warm six-nine chords, more crackle, a gentle nod.
        PlaceholderRecipe(
            id: "cozy-a", bucket: .cozy, bpm: 80, key: "Bb major", tonic: 46, minor: false,
            progression: [Chord(0, Chord.sixNine), Chord(9, Chord.min7), Chord(2, Chord.min9), Chord(7, Chord.dom7)],
            bars: 14, swing: 0.2, drums: .boomBap, hats: 0.6, bass: .halves, melody: 0.25,
            brightness: 2400, crackle: 0.7, wobble: 8, chordStabs: true, intensity: 0.3, seed: 201
        ),
        PlaceholderRecipe(
            id: "cozy-b", bucket: .cozy, bpm: 76, key: "Eb major", tonic: 51, minor: false,
            progression: [Chord(5, Chord.maj7), Chord(4, Chord.min7), Chord(2, Chord.min7), Chord(0, Chord.maj9)],
            bars: 12, swing: 0.18, drums: .boomBap, hats: 0.5, bass: .halves, melody: 0.2,
            brightness: 2300, crackle: 0.65, wobble: 7, intensity: 0.3, seed: 202
        ),
        // Playful: bouncier bass, busier hats, a chirpy melody.
        PlaceholderRecipe(
            id: "playful-a", bucket: .playful, bpm: 92, key: "C major", tonic: 48, minor: false,
            progression: [Chord(0, Chord.maj7), Chord(9, Chord.min7), Chord(2, Chord.min7), Chord(7, Chord.dom7)],
            bars: 16, swing: 0.25, drums: .boomBap, hats: 0.9, bass: .syncopated, melody: 0.6,
            brightness: 4200, crackle: 0.3, wobble: 5, chordStabs: true, intensity: 0.6, seed: 301
        ),
        PlaceholderRecipe(
            id: "playful-b", bucket: .playful, bpm: 96, key: "G major", tonic: 55, minor: false,
            progression: [Chord(0, Chord.maj7), Chord(2, Chord.dom7), Chord(5, Chord.maj7), Chord(5, Chord.min6)],
            bars: 16, swing: 0.22, drums: .boomBap, hats: 0.85, bass: .syncopated, melody: 0.55,
            brightness: 4000, crackle: 0.25, wobble: 4, chordStabs: true, intensity: 0.55, seed: 302
        ),
        // Hopeful: open add9 and sus chords, brighter, lifting melody.
        PlaceholderRecipe(
            id: "hopeful-a", bucket: .hopeful, bpm: 88, key: "D major", tonic: 50, minor: false,
            progression: [Chord(0, Chord.add9), Chord(7, Chord.sus2), Chord(9, Chord.min7), Chord(5, Chord.maj7)],
            bars: 14, swing: 0.12, drums: .boomBap, hats: 0.8, bass: .halves, melody: 0.5,
            brightness: 4800, crackle: 0.2, wobble: 4, intensity: 0.6, seed: 401
        ),
        PlaceholderRecipe(
            id: "hopeful-b", bucket: .hopeful, bpm: 84, key: "A major", tonic: 57, minor: false,
            progression: [Chord(5, Chord.maj9), Chord(7, Chord.dom7), Chord(4, Chord.min7), Chord(9, Chord.min9)],
            bars: 14, swing: 0.1, drums: .boomBap, hats: 0.75, bass: .halves, melody: 0.45,
            brightness: 4600, crackle: 0.2, wobble: 4, intensity: 0.55, seed: 402
        ),
        // Melancholy: minor ninths, slow, dusty.
        PlaceholderRecipe(
            id: "melancholy-a", bucket: .melancholy, bpm: 70, key: "A minor", tonic: 57, minor: true,
            progression: [Chord(0, Chord.min9), Chord(8, Chord.maj7), Chord(5, Chord.min7), Chord(7, Chord.min7)],
            bars: 12, swing: 0.15, drums: .soft, hats: 0.5, bass: .whole, melody: 0.35,
            brightness: 2200, crackle: 0.5, wobble: 9, intensity: 0.35, seed: 501
        ),
        PlaceholderRecipe(
            id: "melancholy-b", bucket: .melancholy, bpm: 66, key: "E minor", tonic: 52, minor: true,
            progression: [Chord(0, Chord.min7), Chord(3, Chord.maj7), Chord(10, Chord.add9), Chord(5, Chord.min9)],
            bars: 10, swing: 0.12, drums: .soft, hats: 0.4, bass: .whole, melody: 0.3,
            brightness: 2100, crackle: 0.55, wobble: 10, intensity: 0.3, seed: 502
        ),
        // Mysterious: minor-major and sharp-eleven colours, half-time, wobbly tape.
        PlaceholderRecipe(
            id: "mysterious-a", bucket: .mysterious, bpm: 76, key: "D minor", tonic: 50, minor: true,
            progression: [Chord(0, Chord.minMaj7), Chord(8, Chord.maj7sharp11), Chord(2, Chord.halfDim), Chord(7, Chord.dom7flat9)],
            bars: 12, swing: 0.1, drums: .halfTime, hats: 0.5, bass: .whole, melody: 0.3,
            brightness: 2000, crackle: 0.3, wobble: 14, intensity: 0.45, seed: 601
        ),
        PlaceholderRecipe(
            id: "mysterious-b", bucket: .mysterious, bpm: 72, key: "F# minor", tonic: 54, minor: true,
            progression: [Chord(0, Chord.min9), Chord(1, Chord.maj7), Chord(5, Chord.min7), Chord(7, Chord.dom7flat9)],
            bars: 12, swing: 0.08, drums: .halfTime, hats: 0.45, bass: .whole, melody: 0.25,
            brightness: 1900, crackle: 0.3, wobble: 12, intensity: 0.45, seed: 602
        ),
        // Tense: driving eighth-note bass, sixteenth hats, flat-nine dominants.
        PlaceholderRecipe(
            id: "tense-a", bucket: .tense, bpm: 96, key: "C minor", tonic: 48, minor: true,
            progression: [Chord(0, Chord.min7), Chord(8, Chord.maj7), Chord(2, Chord.dim7), Chord(7, Chord.dom7flat9)],
            bars: 16, swing: 0.05, drums: .driving, hats: 1.0, bass: .eighths, melody: 0.2,
            brightness: 3000, crackle: 0.2, wobble: 5, intensity: 0.85, seed: 701
        ),
        PlaceholderRecipe(
            id: "tense-b", bucket: .tense, bpm: 100, key: "B minor", tonic: 47, minor: true,
            progression: [Chord(0, Chord.min7), Chord(0, Chord.min7), Chord(8, Chord.maj7), Chord(7, Chord.dom7flat9)],
            bars: 16, swing: 0.04, drums: .driving, hats: 0.95, bass: .eighths, melody: 0.15,
            brightness: 3200, crackle: 0.15, wobble: 4, intensity: 0.9, seed: 702
        ),
        // Somber: very slow, no hats, dark low-pass.
        PlaceholderRecipe(
            id: "somber-a", bucket: .somber, bpm: 64, key: "E minor", tonic: 52, minor: true,
            progression: [Chord(0, Chord.min9), Chord(8, Chord.maj7), Chord(5, Chord.min6), Chord(7, Chord.dom7)],
            bars: 10, swing: 0, drums: .halfTime, hats: 0, bass: .whole, melody: 0.25,
            brightness: 1700, crackle: 0.4, wobble: 8, intensity: 0.4, seed: 801
        ),
        PlaceholderRecipe(
            id: "somber-b", bucket: .somber, bpm: 60, key: "G minor", tonic: 55, minor: true,
            progression: [Chord(0, Chord.min7), Chord(5, Chord.min9), Chord(8, Chord.maj7), Chord(7, Chord.min7)],
            bars: 8, swing: 0, drums: .halfTime, hats: 0, bass: .whole, melody: 0.2,
            brightness: 1600, crackle: 0.45, wobble: 9, intensity: 0.35, seed: 802
        ),
        // Romantic: slow, tender major ninths and six-nines, lots of swing, soft drums.
        PlaceholderRecipe(
            id: "romantic-a", bucket: .romantic, bpm: 74, key: "Ab major", tonic: 56, minor: false,
            progression: [Chord(0, Chord.maj9), Chord(4, Chord.min7), Chord(9, Chord.min9), Chord(2, Chord.min7)],
            bars: 12, swing: 0.22, drums: .soft, hats: 0.45, bass: .halves, melody: 0.35,
            brightness: 2700, crackle: 0.45, wobble: 6, intensity: 0.3, seed: 901
        ),
        PlaceholderRecipe(
            id: "romantic-b", bucket: .romantic, bpm: 70, key: "E major", tonic: 52, minor: false,
            progression: [Chord(5, Chord.maj7), Chord(4, Chord.min7), Chord(9, Chord.min7), Chord(0, Chord.sixNine)],
            bars: 12, swing: 0.2, drums: .soft, hats: 0.4, bass: .halves, melody: 0.3,
            brightness: 2600, crackle: 0.5, wobble: 7, intensity: 0.25, seed: 902
        ),
        // Dreamy: floating sharp-eleven and sus colours, no drums or barely any, wide wobble.
        PlaceholderRecipe(
            id: "dreamy-a", bucket: .dreamy, bpm: 70, key: "Db major", tonic: 49, minor: false,
            progression: [Chord(0, Chord.maj7sharp11), Chord(5, Chord.maj9), Chord(7, Chord.sus2), Chord(9, Chord.min9)],
            bars: 10, swing: 0.1, drums: .none, hats: 0, bass: .whole, melody: 0.4,
            brightness: 3200, crackle: 0.3, wobble: 12, intensity: 0.25, seed: 1001
        ),
        PlaceholderRecipe(
            id: "dreamy-b", bucket: .dreamy, bpm: 76, key: "B major", tonic: 59, minor: false,
            progression: [Chord(0, Chord.add9), Chord(4, Chord.min9), Chord(5, Chord.maj7sharp11), Chord(5, Chord.min6)],
            bars: 12, swing: 0.12, drums: .soft, hats: 0.2, bass: .whole, melody: 0.45,
            brightness: 3400, crackle: 0.25, wobble: 11, intensity: 0.3, seed: 1002
        ),
        // Adventurous: forward motion, bright add9 and dominant chords, syncopated bass.
        PlaceholderRecipe(
            id: "adventurous-a", bucket: .adventurous, bpm: 98, key: "E minor", tonic: 52, minor: true,
            progression: [Chord(0, Chord.min9), Chord(8, Chord.maj7), Chord(10, Chord.add9), Chord(5, Chord.sus2)],
            bars: 16, swing: 0.08, drums: .boomBap, hats: 0.9, bass: .syncopated, melody: 0.5,
            brightness: 4200, crackle: 0.15, wobble: 4, chordStabs: true, intensity: 0.7, seed: 1101
        ),
        PlaceholderRecipe(
            id: "adventurous-b", bucket: .adventurous, bpm: 94, key: "G major", tonic: 55, minor: false,
            progression: [Chord(0, Chord.add9), Chord(10, Chord.maj7), Chord(5, Chord.add9), Chord(7, Chord.dom7)],
            bars: 16, swing: 0.1, drums: .driving, hats: 0.8, bass: .syncopated, melody: 0.45,
            brightness: 4400, crackle: 0.15, wobble: 4, intensity: 0.65, seed: 1102
        ),
    ]
}
