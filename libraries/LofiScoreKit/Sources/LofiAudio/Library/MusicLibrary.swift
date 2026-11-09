import Foundation
import LofiScoreCore

/// The music the player can choose from: tracks sorted into the eight mood buckets.
///
/// Load it from a folder that holds either a `library.json` (written by the import script)
/// or simply one subfolder per mood ("Calm", "Cozy", ... "Somber"), as Mo keeps them on
/// the Mac. Nothing in here is ever committed to git.
public struct MusicLibrary: Sendable {
    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case notAFolder(String)
        case noTracks(String)
        case unsafePath(String)

        public var description: String {
            switch self {
            case let .notAFolder(path): return "\(path) is not a folder"
            case let .noTracks(path): return "No audio files found in \(path) (expected library.json or one folder per mood)"
            case let .unsafePath(file): return "Track path \"\(file)\" points outside the library folder"
            }
        }
    }

    /// File extensions the scanner picks up.
    public static let audioExtensions: Set<String> = ["m4a", "aac", "mp3", "wav", "aif", "aiff", "aifc", "caf", "flac"]

    public let root: URL
    public let tracks: [LibraryTrack]
    /// Loudness assumed for tracks without a measured value, in LUFS.
    public let defaultLoudness: Double

    public init(root: URL, tracks: [LibraryTrack], defaultLoudness: Double = -16) {
        self.root = root
        self.tracks = tracks
        self.defaultLoudness = defaultLoudness
    }

    public func tracks(in bucket: MoodBucket) -> [LibraryTrack] {
        tracks.filter { $0.bucket == bucket }
    }

    public func url(for track: LibraryTrack) -> URL {
        root.appendingPathComponent(track.file)
    }

    public func loudness(of track: LibraryTrack) -> Double {
        track.loudness ?? defaultLoudness
    }

    /// Buckets with no tracks at all.
    public var emptyBuckets: [MoodBucket] {
        MoodBucket.allCases.filter { bucket in !tracks.contains { $0.bucket == bucket } }
    }

    /// The buckets to try for `bucket`, best first: itself, then the others by distance on
    /// the valence/arousal map. Lets the player cope with a library that is still filling up.
    public func fallbackOrder(for bucket: MoodBucket) -> [MoodBucket] {
        let others = MoodBucket.allCases
            .filter { $0 != bucket }
            .sorted { $0.anchor.distance(to: bucket.anchor) < $1.anchor.distance(to: bucket.anchor) }
        return [bucket] + others
    }

    // MARK: - Loading

    /// Loads `library.json` from `folder` if there is one, otherwise scans its mood subfolders.
    public static func load(from folder: URL, fileManager: FileManager = .default) throws -> MusicLibrary {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LoadError.notAFolder(folder.path)
        }
        let manifestURL = folder.appendingPathComponent(LibraryManifest.fileName)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let manifest = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: manifestURL))
            for track in manifest.tracks where !isSafeRelativePath(track.file) {
                throw LoadError.unsafePath(track.file)
            }
            guard !manifest.tracks.isEmpty else { throw LoadError.noTracks(folder.path) }
            return MusicLibrary(root: folder, tracks: manifest.tracks, defaultLoudness: manifest.targetLoudness ?? -16)
        }
        return try scan(folder: folder, fileManager: fileManager)
    }

    /// Builds a library from one subfolder per mood. Folder names match buckets loosely
    /// ("Calm", "calm", "Sombre"...). A tempo in the file name ("rainy-day 72bpm.m4a") is
    /// picked up for bar-aligned crossfades.
    public static func scan(folder: URL, fileManager: FileManager = .default) throws -> MusicLibrary {
        let children = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var tracks: [LibraryTrack] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory, let bucket = MoodBucket(lenient: child.lastPathComponent) else { continue }
            let files = try fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where audioExtensions.contains(file.pathExtension.lowercased()) {
                let relative = child.lastPathComponent + "/" + file.lastPathComponent
                tracks.append(LibraryTrack(
                    id: "\(bucket.rawValue)/\(file.deletingPathExtension().lastPathComponent)",
                    file: relative,
                    bucket: bucket,
                    bpm: tempo(inFileName: file.lastPathComponent),
                    source: "folder scan"
                ))
            }
        }
        guard !tracks.isEmpty else { throw LoadError.noTracks(folder.path) }
        return MusicLibrary(root: folder, tracks: tracks)
    }

    /// A tempo written into a file name, such as "72bpm" or "72 BPM".
    static func tempo(inFileName name: String) -> Double? {
        let lower = name.lowercased()
        guard let range = lower.range(of: "bpm") else { return nil }
        var digits = ""
        var index = range.lowerBound
        while index > lower.startIndex {
            let previous = lower.index(before: index)
            let character = lower[previous]
            if character == " " || character == "_" || character == "-", digits.isEmpty {
                index = previous
                continue
            }
            guard character.isNumber else { break }
            digits.insert(character, at: digits.startIndex)
            index = previous
        }
        guard let value = Double(digits), value >= 30, value <= 300 else { return nil }
        return value
    }

    /// Rejects absolute paths and `..`, so a manifest cannot point outside its folder.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return !path.split(separator: "/").contains("..")
    }
}
