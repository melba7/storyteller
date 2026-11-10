import Foundation
import LofiAtmosphere
import LofiAudio

/// Keeping the imported music up to date with the folder it came from, without the
/// listener importing it again: new tracks, scores and sounds put into the folder (by the
/// Mac's scoring, or by hand) are copied the next time the app looks.
extension MusicFolderImport {
    /// What a sync copied, by kind, so the host knows what to reload.
    public struct SyncSummary: Sendable, Hashable, Codable {
        public var folderName: String
        /// Files copied for the first time, and files copied again because they changed.
        public var added = 0
        public var updated = 0
        /// Files still only in iCloud; their download was asked for, for next time.
        public var notDownloaded = 0
        /// Of the files copied: music, the Fast mood models, mood tracks and scores,
        /// atmosphere tracks, atmosphere recordings.
        public var music = 0
        public var models = 0
        public var moodTracks = 0
        public var atmosphereTracks = 0
        public var atmosphereRecordings = 0
        /// The whole folder was imported afresh (nothing was imported before).
        public var fresh = false

        public var changed: Bool { added + updated > 0 }

        public init(folderName: String) {
            self.folderName = folderName
        }

        /// One line for the settings screen: "3 new book scores, 2 new sounds".
        public var description: String {
            var parts: [String] = []
            func add(_ count: Int, _ singular: String, _ plural: String) {
                guard count > 0 else { return }
                parts.append("\(count) \(count == 1 ? singular : plural)")
            }
            add(moodTracks, "book score", "book scores")
            add(atmosphereTracks, "atmosphere track", "atmosphere tracks")
            add(music, "track", "tracks")
            add(atmosphereRecordings, "sound", "sounds")
            add(models, "mood model", "mood models")
            let other = added + updated - music - models - moodTracks - atmosphereTracks - atmosphereRecordings
            add(other, "other file", "other files")
            if parts.isEmpty { return notDownloaded > 0 ? "Nothing new yet; \(notDownloaded) files are still downloading from iCloud" : "Nothing new" }
            var line = (fresh ? "Imported " : "New: ") + parts.joined(separator: ", ")
            if notDownloaded > 0 { line += "; \(notDownloaded) more still downloading from iCloud" }
            return line
        }
    }

    /// A file as it was when copied, to tell whether it changed since.
    struct Stamp: Codable, Equatable {
        var size: Int
        var modified: Double
    }

    typealias Manifest = [String: Stamp]
    static let manifestFileName = ".imported.json"

    /// Copies into `destination` whatever in `source` is new or changed since the last
    /// import or sync, by the same rules as ``importFolder(_:into:fileManager:)``, and never
    /// deletes anything. When nothing has been imported yet, this is a plain import.
    ///
    /// Files still only in iCloud are asked to download, so a later sync gets them.
    public static func sync(_ source: URL, into destination: URL, fileManager: FileManager = .default) throws -> SyncSummary {
        var summary = SyncSummary(folderName: source.lastPathComponent)
        let imported = (try? MusicLibrary.load(from: destination, fileManager: fileManager))?.tracks.isEmpty == false
        guard imported else {
            let full = try importFolder(source, into: destination, fileManager: fileManager)
            summary.fresh = true
            summary.music = full.tracks
            summary.moodTracks = full.moodTracks
            summary.atmosphereTracks = full.atmosphereTracks
            summary.atmosphereRecordings = full.atmosphereRecordings
            summary.models = full.hasClassifier ? 1 : 0
            summary.notDownloaded = full.notDownloaded
            summary.added = (loadManifest(in: destination, fileManager: fileManager) ?? [:]).count
            return summary
        }

        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif

        let plan = try plan(for: source, fileManager: fileManager)
        summary.notDownloaded = plan.notDownloaded
        requestDownloads(plan.placeholders, fileManager: fileManager)
        var manifest = loadManifest(in: destination, fileManager: fileManager) ?? [:]
        var changed = false
        defer { if changed { try? saveManifest(manifest, in: destination, fileManager: fileManager) } }

        for item in plan.items {
            let target = destination.appendingPathComponent(item.relativePath, isDirectory: item.isDirectory)
            let stamp = stamp(of: item.url, fileManager: fileManager)
            let exists = fileManager.fileExists(atPath: target.path)
            if exists, manifest[item.relativePath] == stamp { continue }
            try replace(target, with: item.url, fileManager: fileManager)
            manifest[item.relativePath] = stamp
            changed = true
            if exists { summary.updated += 1 } else { summary.added += 1 }
            count(item, in: &summary)
        }
        return summary
    }

    private static func count(_ item: Item, in summary: inout SyncSummary) {
        let path = item.relativePath
        let name = item.url.lastPathComponent
        let ext = item.url.pathExtension.lowercased()
        if path.hasPrefix(moodTracksFolderName + "/") {
            summary.moodTracks += 1
        } else if path.hasPrefix(AtmosphereTrackFinder.tracksFolderName + "/") {
            summary.atmosphereTracks += 1
        } else if path.hasPrefix(atmosphereFolderName + "/") {
            if AmbienceLibrary.audioExtensions.contains(ext) { summary.atmosphereRecordings += 1 }
        } else if isClassifier(item.url) || isEmbeddingModel(item.url) || isTransformerModel(item.url) {
            summary.models += 1
        } else if MusicLibrary.audioExtensions.contains(ext) {
            summary.music += 1
        } else if name == LibraryManifest.fileName {
            // library.json changing means the tracks' details changed.
            summary.music += 1
        }
    }

    /// Copies `source` over `target` through a temporary file beside it, so a copy that
    /// fails part way leaves the old file in place.
    private static func replace(_ target: URL, with source: URL, fileManager: FileManager) throws {
        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let part = parent.appendingPathComponent("." + target.lastPathComponent + ".part")
        try? fileManager.removeItem(at: part)
        try copy(source, to: part, fileManager: fileManager)
        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: part, to: target)
    }

    static func stamp(of url: URL, fileManager: FileManager) -> Stamp {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return Stamp(size: 0, modified: 0) }
        if isDirectory.boolValue {
            // A compiled Core ML model: its files together.
            var size = 0
            var modified = 0.0
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
                for case let file as URL in enumerator {
                    let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    size += values?.fileSize ?? 0
                    modified = max(modified, values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
                }
            }
            return Stamp(size: size, modified: modified.rounded())
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Stamp(size: values?.fileSize ?? 0, modified: (values?.contentModificationDate?.timeIntervalSince1970 ?? 0).rounded())
    }

    static func loadManifest(in destination: URL, fileManager: FileManager) -> Manifest? {
        guard let data = fileManager.contents(atPath: destination.appendingPathComponent(manifestFileName).path) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func saveManifest(_ manifest: Manifest, in destination: URL, fileManager: FileManager = .default) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: destination.appendingPathComponent(manifestFileName), options: .atomic)
    }

    /// Asks iCloud Drive to download files that are only placeholders on the device.
    static func requestDownloads(_ placeholders: [URL], fileManager: FileManager) {
        #if canImport(Darwin)
        for url in placeholders {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
        #endif
    }
}
