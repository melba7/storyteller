import Foundation

/// Which recordings an app build plays. Mo's own builds may use recordings that are free
/// for personal use only (a CC BY-NC licence, or found through Freesound's API, which is
/// free for non-commercial use); a build for the App Store must not.
public enum SoundEdition: String, Codable, Sendable, Hashable, CaseIterable {
    /// Plays personal-use recordings, and skips the stand-bys kept only for publishing
    /// when a sound has better ones.
    case personal
    /// Never plays a personal-use recording.
    case publish
}

/// One recording of an ambient sound: a seamless loop.
public struct AmbienceRecording: Codable, Sendable, Hashable {
    public var id: String
    /// Path inside the library folder, e.g. "Rain/rain-1.m4a".
    public var file: String
    public var sound: AmbientSound
    /// The ``SoundVariant`` it is a recording of ("churchBells"), or nil for the plain sound.
    public var variant: String?
    /// Integrated loudness in LUFS, measured on import. Nil means unmeasured.
    public var loudness: Double?
    public var duration: Double?
    public var title: String?
    public var author: String?
    /// Where it came from (a page URL) and under what licence, for the credits.
    public var source: String?
    public var license: String?
    /// Which builds may play it: "personal" (personal use only: never in a published
    /// build), "publish" (a stand-by for published builds; Mo's builds play the better
    /// personal-use ones instead), or nil for both.
    public var use: String?

    public init(
        id: String, file: String, sound: AmbientSound, variant: String? = nil, loudness: Double? = nil, duration: Double? = nil,
        title: String? = nil, author: String? = nil, source: String? = nil, license: String? = nil, use: String? = nil
    ) {
        self.id = id
        self.file = file
        self.sound = sound
        self.variant = variant
        self.loudness = loudness
        self.duration = duration
        self.title = title
        self.author = author
        self.source = source
        self.license = license
        self.use = use
    }

    public var isPersonalUseOnly: Bool { use?.lowercased() == SoundEdition.personal.rawValue }
    public var isPublishStandBy: Bool { use?.lowercased() == SoundEdition.publish.rawValue }
}

/// A folder of ambient recordings, one subfolder per sound, with an optional
/// `sounds.json` that adds measured loudness and credits:
///
/// ```
/// Atmosphere/
///   Rain/                 rain-1.m4a  rain-2.m4a
///   Fireplace/            fireplace-1.m4a
///   OldTown.ChurchBells/  bells-1.m4a     a variant: church bells, a kind of oldTown
///   ...
///   sounds.json           (written by the fetch script; optional)
/// ```
///
/// Folder names match loosely ("HeavyRain", "heavy rain", "heavy_rain"). Files that
/// `sounds.json` does not list still play, at an assumed loudness, unless it lists them
/// as rejected. A plain sound plays
/// only its own recordings, never a variant's.
public struct AmbienceLibrary: Sendable, Hashable {
    public static let manifestName = "sounds.json"
    public static let audioExtensions: Set<String> = ["m4a", "aac", "mp3", "wav", "aif", "aiff", "caf", "flac"]
    /// What an unmeasured file is taken to be.
    public static let assumedLoudness = -23.0

    public struct Manifest: Codable, Sendable, Hashable {
        public var version: Int
        public var sounds: [AmbienceRecording]
        /// Files in the folder that are not to be played: the fetch script found them to
        /// be poor recordings (a drip under a running tap, a sound that comes and goes).
        /// They stay in the folder, because nothing deletes from the copy in iCloud.
        public var rejected: [Rejected]?

        public struct Rejected: Codable, Sendable, Hashable {
            public var file: String
            public var why: String?

            public init(file: String, why: String? = nil) {
                self.file = file
                self.why = why
            }
        }

        public init(version: Int = 1, sounds: [AmbienceRecording], rejected: [Rejected]? = nil) {
            self.version = version
            self.sounds = sounds
            self.rejected = rejected
        }
    }

    public let folder: URL
    public private(set) var recordings: [AmbienceRecording]
    /// Where each recording's file is, by id (recordings merged from another library keep
    /// their own folder).
    private var urls: [String: URL]

    public init(folder: URL, recordings: [AmbienceRecording]) {
        self.folder = folder
        self.recordings = recordings.sorted { $0.file < $1.file }
        urls = Dictionary(recordings.map { ($0.id, folder.appendingPathComponent($0.file)) }, uniquingKeysWith: { first, _ in first })
    }

    public static func empty(at folder: URL) -> AmbienceLibrary {
        AmbienceLibrary(folder: folder, recordings: [])
    }

    /// This library, plus `fallback`'s recordings of every sound this one has none of:
    /// imported recordings first, synthesised stand-ins for the gaps.
    public func filling(from fallback: AmbienceLibrary) -> AmbienceLibrary {
        var merged = self
        let have = sounds
        for recording in fallback.recordings where !have.contains(recording.sound) && merged.urls[recording.id] == nil {
            merged.recordings.append(recording)
            merged.urls[recording.id] = fallback.url(for: recording)
        }
        merged.recordings.sort { $0.file < $1.file }
        return merged
    }

    /// Reads the folder, keeping the recordings `edition` may play. Missing folders give an
    /// empty library.
    public static func load(from folder: URL, edition: SoundEdition = .personal, fileManager: FileManager = .default) throws -> AmbienceLibrary {
        var byFile: [String: AmbienceRecording] = [:]
        var rejected: Set<String> = []
        let manifestURL = folder.appendingPathComponent(manifestName)
        if let data = try? Data(contentsOf: manifestURL) {
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            rejected = Set((manifest.rejected ?? []).map(\.file))
            for var recording in manifest.sounds where isSafePath(recording.file) && !rejected.contains(recording.file) {
                if let variant = recording.variant {
                    guard let id = SoundVariant.normalizedID(variant) else { continue }
                    recording.variant = id
                }
                if fileManager.fileExists(atPath: folder.appendingPathComponent(recording.file).path) {
                    byFile[recording.file] = recording
                }
            }
        }
        let folders = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for subfolder in folders {
            guard (try? subfolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = subfolder.lastPathComponent
            let sound: AmbientSound
            let variant: String?
            if let plain = AmbientSound(lenient: name) {
                (sound, variant) = (plain, nil)
            } else if let parsed = SoundVariant.parseFolder(name) {
                (sound, variant) = (parsed.sound, parsed.id)
            } else {
                continue
            }
            let files = (try? fileManager.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: nil)) ?? []
            for file in files where audioExtensions.contains(file.pathExtension.lowercased()) {
                let relative = name + "/" + file.lastPathComponent
                guard byFile[relative] == nil, !rejected.contains(relative) else { continue }
                byFile[relative] = AmbienceRecording(
                    id: sound.rawValue + (variant.map { "." + $0 } ?? "") + "/" + file.deletingPathExtension().lastPathComponent,
                    file: relative,
                    sound: sound,
                    variant: variant
                )
            }
        }
        return AmbienceLibrary(folder: folder, recordings: select(Array(byFile.values), for: edition))
    }

    /// The recordings `edition` plays. A published build never gets a personal-use one.
    /// Mo's build skips a sound's publishing stand-bys when it has other recordings.
    static func select(_ recordings: [AmbienceRecording], for edition: SoundEdition) -> [AmbienceRecording] {
        switch edition {
        case .publish:
            return recordings.filter { !$0.isPersonalUseOnly }
        case .personal:
            let groups = Dictionary(grouping: recordings) { "\($0.sound.rawValue).\($0.variant ?? "")" }
            return groups.values.flatMap { group in
                let preferred = group.filter { !$0.isPublishStandBy }
                return preferred.isEmpty ? group : preferred
            }
        }
    }

    /// The plain sound's recordings, without its variants'.
    public func recordings(of sound: AmbientSound) -> [AmbienceRecording] {
        recordings(of: sound, variant: nil)
    }

    public func recordings(of sound: AmbientSound, variant: String?) -> [AmbienceRecording] {
        recordings.filter { $0.sound == sound && $0.variant == variant }
    }

    /// The plain sounds that have recordings.
    public var sounds: Set<AmbientSound> { Set(recordings.filter { $0.variant == nil }.map(\.sound)) }

    /// The variants that have recordings, as "oldTown.churchBells".
    public var variants: Set<String> {
        Set(recordings.compactMap { recording in recording.variant.map { "\(recording.sound.rawValue).\($0)" } })
    }

    public func url(for recording: AmbienceRecording) -> URL {
        urls[recording.id] ?? folder.appendingPathComponent(recording.file)
    }

    public func loudness(of recording: AmbienceRecording) -> Double {
        recording.loudness ?? Self.assumedLoudness
    }

    /// The recording to use for `sound` under a stable key, so the same key always gets
    /// the same recording: a place keeps its own fire, a book keeps its own rain.
    public func recording(of sound: AmbientSound, variant: String? = nil, key: String) -> AmbienceRecording? {
        let candidates = recordings(of: sound, variant: variant)
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(StableHash.fnv1a(key) % UInt64(candidates.count))]
    }

    /// The recording for a scene's layer: its variant's when there is one, otherwise the
    /// plain sound's.
    public func recording(for layer: SceneLayer, key: String) -> AmbienceRecording? {
        if let variant = layer.variant {
            if let recording = recording(of: layer.sound, variant: variant, key: key) { return recording }
            // Variant ids are unique across families, so recordings fetched when the kind
            // belonged to another family (an older catalogue) still play.
            let moved = recordings.filter { $0.variant == variant }
            if !moved.isEmpty { return moved[Int(StableHash.fnv1a(key) % UInt64(moved.count))] }
        }
        return recording(of: layer.sound, key: key)
    }

    static func isSafePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..") && !path.isEmpty
    }
}

/// 64-bit FNV-1a, for picking recordings deterministically.
public enum StableHash {
    public static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
