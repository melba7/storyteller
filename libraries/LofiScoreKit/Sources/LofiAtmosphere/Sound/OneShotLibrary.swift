import Foundation

/// One recording of a one-off sound: played once, not looped.
public struct OneShotRecording: Codable, Sendable, Hashable {
    public var id: String
    /// Path inside the one-shot folder, e.g. "DoorKnock/knock-fs123.m4a".
    public var file: String
    public var sound: OneShotSound
    /// Integrated loudness in LUFS. Nil means unmeasured.
    public var loudness: Double?
    public var duration: Double?
    public var title: String?
    public var author: String?
    public var source: String?
    public var license: String?
    /// "personal", "publish" or nil, as for ``AmbienceRecording/use``.
    public var use: String?

    public init(
        id: String, file: String, sound: OneShotSound, loudness: Double? = nil, duration: Double? = nil,
        title: String? = nil, author: String? = nil, source: String? = nil, license: String? = nil, use: String? = nil
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
        self.use = use
    }

    public var isPersonalUseOnly: Bool { use?.lowercased() == SoundEdition.personal.rawValue }
    public var isPublishStandBy: Bool { use?.lowercased() == SoundEdition.publish.rawValue }
}

/// The one-off sounds' recordings: `Atmosphere/OneShots/`, one subfolder per sound, with
/// an optional `sounds.json` written by the fetch script:
///
/// ```
/// Atmosphere/
///   OneShots/
///     DoorKnock/    knock-fs123.m4a
///     ThunderClap/  thunder-c4.m4a
///     sounds.json
/// ```
public struct OneShotLibrary: Sendable, Hashable {
    public static let folderName = "OneShots"
    /// What an unmeasured file is taken to be.
    public static let assumedLoudness = -20.0

    public struct Manifest: Codable, Sendable, Hashable {
        public var version: Int
        public var sounds: [OneShotRecording]

        public init(version: Int = 1, sounds: [OneShotRecording]) {
            self.version = version
            self.sounds = sounds
        }
    }

    public let folder: URL
    public private(set) var recordings: [OneShotRecording]
    private var urls: [String: URL]

    public init(folder: URL, recordings: [OneShotRecording]) {
        self.folder = folder
        self.recordings = recordings.sorted { $0.file < $1.file }
        urls = Dictionary(recordings.map { ($0.id, folder.appendingPathComponent($0.file)) }, uniquingKeysWith: { first, _ in first })
    }

    public static func empty(at folder: URL) -> OneShotLibrary {
        OneShotLibrary(folder: folder, recordings: [])
    }

    /// Reads the folder, keeping what `edition` may play. A missing folder is empty.
    public static func load(from folder: URL, edition: SoundEdition = .personal, fileManager: FileManager = .default) throws -> OneShotLibrary {
        var byFile: [String: OneShotRecording] = [:]
        if let data = try? Data(contentsOf: folder.appendingPathComponent(AmbienceLibrary.manifestName)) {
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            for recording in manifest.sounds where AmbienceLibrary.isSafePath(recording.file)
                && fileManager.fileExists(atPath: folder.appendingPathComponent(recording.file).path) {
                byFile[recording.file] = recording
            }
        }
        let folders = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for subfolder in folders {
            guard (try? subfolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let sound = OneShotSound(lenient: subfolder.lastPathComponent)
            else { continue }
            let files = (try? fileManager.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: nil)) ?? []
            for file in files where AmbienceLibrary.audioExtensions.contains(file.pathExtension.lowercased()) {
                let relative = subfolder.lastPathComponent + "/" + file.lastPathComponent
                guard byFile[relative] == nil else { continue }
                byFile[relative] = OneShotRecording(
                    id: sound.rawValue + "/" + file.deletingPathExtension().lastPathComponent, file: relative, sound: sound
                )
            }
        }
        let all = Array(byFile.values)
        let kept: [OneShotRecording]
        switch edition {
        case .publish:
            kept = all.filter { !$0.isPersonalUseOnly }
        case .personal:
            kept = Dictionary(grouping: all, by: \.sound).values.flatMap { group in
                let preferred = group.filter { !$0.isPublishStandBy }
                return preferred.isEmpty ? group : preferred
            }
        }
        return OneShotLibrary(folder: folder, recordings: kept)
    }

    /// This library plus `fallback`'s recordings of the sounds it has none of.
    public func filling(from fallback: OneShotLibrary) -> OneShotLibrary {
        var merged = self
        let have = sounds
        for recording in fallback.recordings where !have.contains(recording.sound) && merged.urls[recording.id] == nil {
            merged.recordings.append(recording)
            merged.urls[recording.id] = fallback.url(for: recording)
        }
        merged.recordings.sort { $0.file < $1.file }
        return merged
    }

    public var sounds: Set<OneShotSound> { Set(recordings.map(\.sound)) }

    public func recordings(of sound: OneShotSound) -> [OneShotRecording] {
        recordings.filter { $0.sound == sound }
    }

    public func url(for recording: OneShotRecording) -> URL {
        urls[recording.id] ?? folder.appendingPathComponent(recording.file)
    }

    public func loudness(of recording: OneShotRecording) -> Double {
        recording.loudness ?? Self.assumedLoudness
    }

    /// The recording for `sound` under a stable key, so the same moment always sounds the same.
    public func recording(of sound: OneShotSound, key: String) -> OneShotRecording? {
        let candidates = recordings(of: sound)
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(StableHash.fnv1a(key) % UInt64(candidates.count))]
    }
}
