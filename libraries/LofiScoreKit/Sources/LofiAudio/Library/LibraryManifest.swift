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
    /// The track's name and artist, for the music panel's "now playing" line. Filled in from
    /// `SOURCES.csv` when `library.json` leaves them out (see ``MusicLibrary/load(from:fileManager:)``),
    /// and guessed from a "Title - Artist" file name when neither has them (``displayTitle``).
    public var title: String?
    public var artist: String?
    /// The license's short name, such as "CC BY 4.0".
    public var licenseName: String?

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
        seed: LooseString? = nil,
        title: String? = nil,
        artist: String? = nil,
        licenseName: String? = nil
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
        self.title = title
        self.artist = artist
        self.licenseName = licenseName
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
        title = try container.decodeIfPresent(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        licenseName = try container.decodeIfPresent(String.self, forKey: .licenseName)
    }

    /// The name to show: `title`, else the file name before " - Artist", else the file name.
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { return title }
        return Self.fileNameParts(file).title
    }

    /// The artist to show: `artist`, else the part of a "Title - Artist" file name after the
    /// last " - ", else nil.
    public var displayArtist: String? {
        if let artist = artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty { return artist }
        return Self.fileNameParts(file).artist
    }

    /// "Calm/Calm Waters - Purrple Cat.mp3" → ("Calm Waters", "Purrple Cat").
    static func fileNameParts(_ file: String) -> (title: String, artist: String?) {
        let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let range = name.range(of: " - ", options: .backwards) else { return (name, nil) }
        let title = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let artist = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !artist.isEmpty else { return (name, nil) }
        return (title, artist)
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
