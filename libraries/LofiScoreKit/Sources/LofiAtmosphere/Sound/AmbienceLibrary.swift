import Foundation

/// One recording of an ambient sound: a seamless loop.
public struct AmbienceRecording: Codable, Sendable, Hashable {
    public var id: String
    /// Path inside the library folder, e.g. "Rain/rain-1.m4a".
    public var file: String
    public var sound: AmbientSound
    /// Integrated loudness in LUFS, measured on import. Nil means unmeasured.
    public var loudness: Double?
    public var duration: Double?
    public var title: String?
    public var author: String?
    /// Where it came from (a page URL) and under what licence, for the credits.
    public var source: String?
    public var license: String?

    public init(
        id: String, file: String, sound: AmbientSound, loudness: Double? = nil, duration: Double? = nil,
        title: String? = nil, author: String? = nil, source: String? = nil, license: String? = nil
    ) {
        self.id = id
        self.file = file
        self.sound = sound
        self.loudness = loudness
        self.duration = duration
        self.title = title
        self.author = author
        self.source = source
        self.license = license
    }
}

/// A folder of ambient recordings, one subfolder per sound, with an optional
/// `sounds.json` that adds measured loudness and credits:
///
/// ```
/// Atmosphere/
///   Rain/        rain-1.m4a  rain-2.m4a
///   Fireplace/   fireplace-1.m4a
///   ...
///   sounds.json  (written by the import script; optional)
/// ```
///
/// Folder names match loosely ("HeavyRain", "heavy rain", "heavy_rain"). Files that
/// `sounds.json` does not list still play, at an assumed loudness.
public struct AmbienceLibrary: Sendable, Hashable {
    public static let manifestName = "sounds.json"
    public static let audioExtensions: Set<String> = ["m4a", "aac", "mp3", "wav", "aif", "aiff", "caf", "flac"]
    /// What an unmeasured file is taken to be.
    public static let assumedLoudness = -23.0

    public struct Manifest: Codable, Sendable, Hashable {
        public var version: Int
        public var sounds: [AmbienceRecording]

        public init(version: Int = 1, sounds: [AmbienceRecording]) {
            self.version = version
            self.sounds = sounds
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

    /// Reads the folder. Missing folders give an empty library.
    public static func load(from folder: URL, fileManager: FileManager = .default) throws -> AmbienceLibrary {
        var byFile: [String: AmbienceRecording] = [:]
        let manifestURL = folder.appendingPathComponent(manifestName)
        if let data = try? Data(contentsOf: manifestURL) {
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            for recording in manifest.sounds where isSafePath(recording.file) {
                if fileManager.fileExists(atPath: folder.appendingPathComponent(recording.file).path) {
                    byFile[recording.file] = recording
                }
            }
        }
        let folders = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for subfolder in folders {
            guard (try? subfolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let sound = AmbientSound(lenient: subfolder.lastPathComponent)
            else { continue }
            let files = (try? fileManager.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: nil)) ?? []
            for file in files where audioExtensions.contains(file.pathExtension.lowercased()) {
                let relative = subfolder.lastPathComponent + "/" + file.lastPathComponent
                guard byFile[relative] == nil else { continue }
                byFile[relative] = AmbienceRecording(
                    id: sound.rawValue + "/" + file.deletingPathExtension().lastPathComponent,
                    file: relative,
                    sound: sound
                )
            }
        }
        return AmbienceLibrary(folder: folder, recordings: Array(byFile.values))
    }

    public func recordings(of sound: AmbientSound) -> [AmbienceRecording] {
        recordings.filter { $0.sound == sound }
    }

    public var sounds: Set<AmbientSound> { Set(recordings.map(\.sound)) }

    public func url(for recording: AmbienceRecording) -> URL {
        urls[recording.id] ?? folder.appendingPathComponent(recording.file)
    }

    public func loudness(of recording: AmbienceRecording) -> Double {
        recording.loudness ?? Self.assumedLoudness
    }

    /// The recording to use for `sound` under a stable key, so the same key always gets
    /// the same recording: a place keeps its own fire, a book keeps its own rain.
    public func recording(of sound: AmbientSound, key: String) -> AmbienceRecording? {
        let candidates = recordings(of: sound)
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(StableHash.fnv1a(key) % UInt64(candidates.count))]
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
