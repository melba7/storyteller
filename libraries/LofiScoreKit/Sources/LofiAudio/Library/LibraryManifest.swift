import Foundation
import LofiScoreCore

/// One track in the music library: an entry in `library.json`.
///
/// Only `id`, `file` and `bucket` are required. The import script (thread 4 of the plan)
/// fills in the rest; the player uses `loudness` to set the bed level per track, `bpm`,
/// `beatsPerBar` and `downbeat` to start crossfades on a bar line, and `duration` when it
/// has not opened the file yet. The provenance fields (`source`, `license`, `prompt`,
/// `seed`) are kept on record for a shared build.
public struct LibraryTrack: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Path relative to the library folder, such as `"Calm/rain-on-glass.m4a"`.
    public var file: String
    public var bucket: MoodBucket
    public var valence: Double?
    public var arousal: Double?
    /// 0 (sparse) ... 1 (full).
    public var intensity: Double?
    public var bpm: Double?
    public var beatsPerBar: Int?
    /// Seconds into the file of the first downbeat. Defaults to 0.
    public var downbeat: Double?
    public var key: String?
    /// Seconds.
    public var duration: Double?
    /// Integrated loudness in LUFS.
    public var loudness: Double?
    /// True peak in dBTP.
    public var truePeak: Double?
    public var source: String?
    public var license: String?
    public var prompt: String?
    public var seed: LooseString?

    public init(
        id: String,
        file: String,
        bucket: MoodBucket,
        valence: Double? = nil,
        arousal: Double? = nil,
        intensity: Double? = nil,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil,
        downbeat: Double? = nil,
        key: String? = nil,
        duration: Double? = nil,
        loudness: Double? = nil,
        truePeak: Double? = nil,
        source: String? = nil,
        license: String? = nil,
        prompt: String? = nil,
        seed: LooseString? = nil
    ) {
        self.id = id
        self.file = file
        self.bucket = bucket
        self.valence = valence
        self.arousal = arousal
        self.intensity = intensity
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.downbeat = downbeat
        self.key = key
        self.duration = duration
        self.loudness = loudness
        self.truePeak = truePeak
        self.source = source
        self.license = license
        self.prompt = prompt
        self.seed = seed
    }

    /// The track's bar grid, when its tempo is known.
    public var barGrid: BarGrid? {
        BarGrid(bpm: bpm, beatsPerBar: beatsPerBar ?? 4, downbeat: downbeat ?? 0)
    }

    /// Accepts the bucket in any case ("Calm" or "calm") and the near-synonyms
    /// ``MoodBucket/init(lenient:)`` knows.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        file = try container.decode(String.self, forKey: .file)
        let rawBucket = try container.decode(String.self, forKey: .bucket)
        guard let bucket = MoodBucket(lenient: rawBucket) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bucket,
                in: container,
                debugDescription: "Unknown mood bucket \"\(rawBucket)\""
            )
        }
        self.bucket = bucket
        valence = try container.decodeIfPresent(Double.self, forKey: .valence)
        arousal = try container.decodeIfPresent(Double.self, forKey: .arousal)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity)
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        beatsPerBar = try container.decodeIfPresent(Int.self, forKey: .beatsPerBar)
        downbeat = try container.decodeIfPresent(Double.self, forKey: .downbeat)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        loudness = try container.decodeIfPresent(Double.self, forKey: .loudness)
        truePeak = try container.decodeIfPresent(Double.self, forKey: .truePeak)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        seed = try container.decodeIfPresent(LooseString.self, forKey: .seed)
    }
}

/// The whole `library.json` file.
public struct LibraryManifest: Codable, Hashable, Sendable {
    public var version: Int
    /// The loudness the import script normalised every track to, in LUFS.
    public var targetLoudness: Double?
    public var tracks: [LibraryTrack]

    public init(version: Int = 1, targetLoudness: Double? = nil, tracks: [LibraryTrack]) {
        self.version = version
        self.targetLoudness = targetLoudness
        self.tracks = tracks
    }

    public static let fileName = "library.json"

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// A value that `library.json` may hold as a string or a number (generator seeds, mostly).
public struct LooseString: Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int64.self) {
            value = String(integer)
        } else if let number = try? container.decode(Double.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a string or a number")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}
