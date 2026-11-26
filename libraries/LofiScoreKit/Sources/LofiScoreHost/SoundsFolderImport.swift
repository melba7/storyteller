import Foundation
import LofiAtmosphere
import LofiScoreCore

/// Copies a sounds folder the listener picked (in Files or iCloud Drive) into the app's own
/// storage, so playback never depends on a security-scoped bookmark or on iCloud keeping
/// the files downloaded.
///
/// What is copied: the atmosphere's recordings, `Atmosphere/<Sound>/` and
/// `Atmosphere/<Sound>.<Variant>/` audio and the one-off sounds in `Atmosphere/OneShots/<Sound>/`,
/// with `Atmosphere/sounds.json`, `variants.json`, `OneShots/sounds.json`, `SOURCES.csv` and
/// `CREDITS.md`; book scores (`*.score.json` anywhere, gathered into `Scores/`); and plain
/// atmosphere tracks (`*.atmosphere.json` anywhere, gathered into `AtmosphereTracks/`).
/// Nothing else: music, mood models and mood tracks the folder may still hold from the
/// shelved music, and an audiobook unpacked somewhere in the folder, are left behind.
public enum SoundsFolderImport {
    public struct Summary: Sendable, Hashable, Codable {
        public var folderName: String
        /// Recordings copied: the sounds, their more specific variants and the one-off sounds.
        public var recordings: Int
        /// Book scores (`*.score.json`) and plain atmosphere tracks copied.
        public var scores: Int
        public var atmosphereTracks: Int
        /// Files that were still only in iCloud and could not be read.
        public var notDownloaded: Int

        public init(folderName: String, recordings: Int, scores: Int, atmosphereTracks: Int, notDownloaded: Int) {
            self.folderName = folderName
            self.recordings = recordings
            self.scores = scores
            self.atmosphereTracks = atmosphereTracks
            self.notDownloaded = notDownloaded
        }
    }

    /// `LocalizedError`, so the sentence reaches the phone's screen: the app shows an error's
    /// `localizedDescription`.
    public enum ImportError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case noSounds(String)
        /// The picked folder is the Atmosphere folder itself (its sound folders are at its
        /// top), not the folder that holds it and the book scores.
        case atmosphereFolderPicked(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case let .noSounds(name):
                return "“\(name)” has no Atmosphere folder in it. Pick the folder the Mac copies the sounds into (LofiMusic in iCloud Drive), which holds the Atmosphere folder and the book scores."
            case let .atmosphereFolderPicked(name):
                return "“\(name)” holds the sounds themselves. Pick the folder one level up (LofiMusic in iCloud Drive), so the book scores come with the sounds."
            case let .unreadable(reason):
                return "The folder could not be read: \(reason)"
            }
        }

        public var errorDescription: String? { description }
    }

    /// The atmosphere's sounds, one folder per sound (see `AmbienceLibrary`).
    public static let atmosphereFolderName = "Atmosphere"
    /// Where book scores go (`<book>.score.json`, from the Mac's scoring).
    public static let scoresFolderName = "Scores"
    /// The attribution the recordings' licences ask for, shown in Settings.
    public static let creditsFileName = "CREDITS.md"

    /// The credits file in a folder, if it has one (any capitalisation).
    public static func creditsFile(in folder: URL, fileManager: FileManager = .default) -> URL? {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.lastPathComponent.lowercased() == creditsFileName.lowercased() }
    }

    /// Sounds have been imported into `destination` (or synced into it).
    public static func isImported(_ destination: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: destination.appendingPathComponent(manifestFileName).path)
    }

    /// Copies `source` into `destination`, replacing what was there only once the copy has
    /// worked and holds something for the atmosphere.
    @discardableResult
    public static func importFolder(_ source: URL, into destination: URL, fileManager: FileManager = .default) throws -> Summary {
        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(destination.lastPathComponent + ".incoming", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var keepStaging = false
        defer { if !keepStaging { try? fileManager.removeItem(at: staging) } }

        let plan = try plan(for: source, fileManager: fileManager)
        guard !plan.items.isEmpty else { throw nothingToImport(in: source, fileManager: fileManager) }
        for item in plan.items {
            let target = staging.appendingPathComponent(item.relativePath)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copy(item.url, to: target, fileManager: fileManager)
        }

        // What was copied, so a later sync of the same folder copies only what is new.
        var manifest = Manifest()
        for item in plan.items {
            manifest[item.relativePath] = stamp(of: item.url, fileManager: fileManager)
        }
        try saveManifest(manifest, in: staging)

        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)
        keepStaging = true
        excludeFromBackup(destination)

        return Summary(
            folderName: source.lastPathComponent,
            recordings: plan.items.filter(\.isRecording).count,
            scores: plan.items.filter(\.isScore).count,
            atmosphereTracks: plan.items.filter(\.isAtmosphereTrack).count,
            notDownloaded: plan.notDownloaded
        )
    }

    // MARK: - Leftovers of the music

    /// Removes what the shelved music left in an imported folder: the mood folders of
    /// music, `library.json` and the music's credits, the mood models and mood tracks. Book
    /// scores that sat in `MoodTracks/` move to `Scores/`, where the atmosphere looks for
    /// them. Returns how many things were removed or moved; nothing when the folder is
    /// already clean, so this is cheap to call at every launch.
    @discardableResult
    public static func tidyMusicLeftovers(in destination: URL, fileManager: FileManager = .default) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return 0
        }
        var touched = 0
        for entry in entries {
            let name = entry.lastPathComponent
            let lower = name.lowercased()
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory, lower == "moodtracks" {
                touched += moveScores(from: entry, into: destination.appendingPathComponent(scoresFolderName, isDirectory: true), fileManager: fileManager)
                if (try? fileManager.removeItem(at: entry)) != nil { touched += 1 }
                continue
            }
            let isMusic = isDirectory
                ? MoodBucket(lenient: name) != nil || lower.hasSuffix(".mlmodelc")
                : lower == "library.json" || lower == "sources.csv" || lower == creditsFileName.lowercased()
                    || lower.hasPrefix("lofimood-") && lower.hasSuffix(".json") || lower.hasSuffix(".mlmodel") || lower == ".matches.json"
            guard isMusic, (try? fileManager.removeItem(at: entry)) != nil else { continue }
            touched += 1
        }
        return touched
    }

    private static func moveScores(from moodTracks: URL, into scores: URL, fileManager: FileManager) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: moodTracks, includingPropertiesForKeys: nil) else { return 0 }
        var moved = 0
        for file in files where file.lastPathComponent.lowercased().hasSuffix(".score.json") {
            let target = scores.appendingPathComponent(file.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try? fileManager.createDirectory(at: scores, withIntermediateDirectories: true)
            if (try? fileManager.moveItem(at: file, to: target)) != nil { moved += 1 }
        }
        return moved
    }

    // MARK: - Internals

    struct Item: Equatable {
        var url: URL
        var relativePath: String

        var isRecording: Bool {
            relativePath.hasPrefix(atmosphereFolderName + "/")
                && AmbienceLibrary.audioExtensions.contains(url.pathExtension.lowercased())
        }

        var isScore: Bool { relativePath.hasPrefix(scoresFolderName + "/") }
        var isAtmosphereTrack: Bool { relativePath.hasPrefix(AtmosphereTrackFinder.tracksFolderName + "/") }
    }

    struct Plan {
        var items: [Item] = []
        var notDownloaded = 0
        /// The files still only in iCloud, by the names they will have once downloaded.
        var placeholders: [URL] = []
    }

    /// Where a file of the picked folder goes in the app's copy, or nil for a file that
    /// is not copied. `components` is its path in the picked folder, split.
    static func destinationPath(for components: [String]) -> String? {
        guard let name = components.last else { return nil }
        let lower = name.lowercased()
        if lower.hasSuffix(".score.json") {
            // Book scores from the Mac (`lofi-sync.sh`), wherever they sit: they all go to
            // Scores/, where the atmosphere looks for them.
            return scoresFolderName + "/" + name
        }
        if lower.hasSuffix(".atmosphere.json") {
            return AtmosphereTrackFinder.tracksFolderName + "/" + name
        }
        guard components.count >= 2, components[0].lowercased() == atmosphereFolderName.lowercased() else { return nil }
        let isAudio = AmbienceLibrary.audioExtensions.contains((name as NSString).pathExtension.lowercased())
        let keep: Bool
        switch components.count {
        case 2:
            keep = [AmbienceLibrary.manifestName, SoundVariantCatalog.fileName, "sources.csv", creditsFileName.lowercased()].contains(lower)
        case 3:
            // A sound's recording, a variant's, or the one-off sounds' manifest.
            let folder = components[1]
            if folder.lowercased() == OneShotLibrary.folderName.lowercased() {
                keep = lower == AmbienceLibrary.manifestName
            } else {
                keep = isAudio && (AmbientSound(lenient: folder) != nil || SoundVariant.parseFolder(folder) != nil)
            }
        case 4:
            keep = isAudio && components[1].lowercased() == OneShotLibrary.folderName.lowercased() && OneShotSound(lenient: components[2]) != nil
        default:
            keep = false
        }
        guard keep else { return nil }
        // Under one spelling of the folder, where the host looks.
        return atmosphereFolderName + "/" + components.dropFirst().joined(separator: "/")
    }

    /// Why a picked folder gave nothing to copy: it is the Atmosphere folder itself (named so,
    /// or with a sound's folder such as Rain at its top), or it simply has no sounds.
    static func nothingToImport(in source: URL, fileManager: FileManager) -> ImportError {
        let name = source.lastPathComponent
        let top = (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
        let looksLikeAtmosphere = name.lowercased() == atmosphereFolderName.lowercased()
            || top.contains { AmbientSound(lenient: $0) != nil || SoundVariant.parseFolder($0) != nil }
        return looksLikeAtmosphere ? .atmosphereFolderPicked(name) : .noSounds(name)
    }

    static func plan(for source: URL, fileManager: FileManager) throws -> Plan {
        var plan = Plan()
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw ImportError.unreadable(source.lastPathComponent)
        }
        for case let url as URL in enumerator {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(rootPath) else { continue }
            let relative = String(resolved.path.dropFirst(rootPath.count))
            let components = relative.split(separator: "/").map(String.init)
            guard let name = components.last else { continue }
            let isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if name.hasPrefix(".") {
                // An iCloud placeholder (".rain.m4a.icloud") means the file is not on the device.
                if !isDirectory, name.hasSuffix(".icloud") {
                    let original = String(name.dropFirst().dropLast(".icloud".count))
                    if destinationPath(for: Array(components.dropLast()) + [original]) != nil {
                        plan.notDownloaded += 1
                        plan.placeholders.append(resolved.deletingLastPathComponent().appendingPathComponent(original))
                    }
                }
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            guard !isDirectory, let target = destinationPath(for: components) else { continue }
            plan.items.append(Item(url: resolved, relativePath: target))
        }
        plan.items.sort { $0.relativePath < $1.relativePath }
        return plan
    }

    static func copy(_ source: URL, to target: URL, fileManager: FileManager) throws {
        #if canImport(Darwin)
        // Coordinated reading makes iCloud Drive download a file that is not on the device yet.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { url in
            do { try fileManager.copyItem(at: url, to: target) } catch { copyError = error }
        }
        let failure: Error? = coordinationError ?? copyError
        if let error = failure {
            throw ImportError.unreadable("\(source.lastPathComponent): \(error.localizedDescription)")
        }
        #else
        do {
            try fileManager.copyItem(at: source, to: target)
        } catch {
            throw ImportError.unreadable("\(source.lastPathComponent): \(error)")
        }
        #endif
    }

    private static func excludeFromBackup(_ url: URL) {
        #if canImport(Darwin)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
        #endif
    }
}

/// Keeping the imported sounds up to date with the folder they came from, without the
/// listener importing it again: new scores, tracks and sounds put into the folder (by the
/// Mac's scoring, or by hand) are copied the next time the app looks.
extension SoundsFolderImport {
    /// What a sync copied, by kind, so the host knows what to reload.
    public struct SyncSummary: Sendable, Hashable, Codable {
        public var folderName: String
        /// Files copied for the first time, and files copied again because they changed.
        public var added = 0
        public var updated = 0
        /// Files still only in iCloud; their download was asked for, for next time.
        public var notDownloaded = 0
        /// Of the files copied: book scores, plain atmosphere tracks, recordings.
        public var scores = 0
        public var atmosphereTracks = 0
        public var recordings = 0
        /// The whole folder was imported afresh (nothing was imported before).
        public var fresh = false
        /// Asked to stop part way (iOS ending the app's background time); the rest is
        /// copied the next time.
        public var stopped = false

        public var changed: Bool { added + updated > 0 }

        public init(folderName: String) {
            self.folderName = folderName
        }

        /// One line for the settings screen: "New: 3 book scores, 2 sounds".
        public var description: String {
            var parts: [String] = []
            func add(_ count: Int, _ singular: String, _ plural: String) {
                guard count > 0 else { return }
                parts.append("\(count) \(count == 1 ? singular : plural)")
            }
            add(scores, "book score", "book scores")
            add(atmosphereTracks, "atmosphere track", "atmosphere tracks")
            add(recordings, "sound", "sounds")
            let other = added + updated - scores - atmosphereTracks - recordings
            add(other, "other file", "other files")
            let downloading = notDownloaded == 1 ? "1 file is still downloading from iCloud" : "\(notDownloaded) files are still downloading from iCloud"
            if parts.isEmpty, !stopped { return notDownloaded > 0 ? "Nothing new yet; \(downloading)" : "Nothing new" }
            var line = parts.isEmpty ? "Nothing copied yet" : (fresh ? "Imported " : "New: ") + parts.joined(separator: ", ")
            if stopped {
                line += "; stopped part way, the rest comes next time"
            } else if notDownloaded > 0 {
                line += "; \(notDownloaded) more still downloading from iCloud"
            }
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

    /// How far a sync has got, for a count on the settings screen.
    public struct Progress: Sendable, Hashable {
        /// Files copied so far, of the files this sync has to copy.
        public var copied: Int
        public var total: Int
        /// The book scores and atmosphere tracks are all in: a book can start playing
        /// while the recordings are still being copied.
        public var scoresReady: Bool
        /// Of the files still to copy, how many iCloud is still downloading.
        public var downloading = 0
    }

    /// Whether a file is on the device, and asking iCloud Drive for one that is not.
    /// Injected so tests can play iCloud.
    public struct CloudDownloads: Sendable {
        public var isLocal: @Sendable (URL) -> Bool
        public var request: @Sendable (URL) -> Void

        public init(isLocal: @escaping @Sendable (URL) -> Bool, request: @escaping @Sendable (URL) -> Void) {
            self.isLocal = isLocal
            self.request = request
        }

        /// iCloud Drive's own state. Outside Apple's platforms every file is local.
        public static let system = CloudDownloads(
            isLocal: { url in
                #if canImport(Darwin)
                let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                guard values?.isUbiquitousItem == true else { return true }
                return values?.ubiquitousItemDownloadingStatus == .current
                #else
                return true
                #endif
            },
            request: { url in
                #if canImport(Darwin)
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                #endif
            }
        )
    }

    /// The manifest is saved every this many files, so a copy cut short (the app closed,
    /// iCloud unreachable) carries on from there the next time.
    static let manifestSaveInterval = 25

    /// Copies into `destination` whatever in `source` is new or changed since the last
    /// import or sync, by the same rules as ``importFolder(_:into:fileManager:)``, and never
    /// deletes anything (but a first import, with nothing imported before, replaces what
    /// sat in `destination`). This is also the first import of a linked folder: the files go in
    /// one at a time, book scores and tracks first (so the open book can start), then the
    /// recordings, then the lists that describe them, and a copy cut short carries on from
    /// where it stopped the next time.
    ///
    /// Every file not on the device yet is asked for from iCloud before the first copy, so
    /// iCloud downloads them together (and carries on with the app closed), and the files
    /// already here are copied first. `shouldStop` is asked before each file: a sync told to
    /// stop saves its place and returns, marked `stopped`.
    /// `progress` is called before the first copy and after every file, on the caller's thread.
    public static func sync(
        _ source: URL,
        into destination: URL,
        fileManager: FileManager = .default,
        downloads: CloudDownloads = .system,
        shouldStop: () -> Bool = { false },
        progress: ((Progress) -> Void)? = nil
    ) throws -> SyncSummary {
        var summary = SyncSummary(folderName: source.lastPathComponent)
        summary.fresh = !isImported(destination, fileManager: fileManager)

        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif

        let plan = try plan(for: source, fileManager: fileManager)
        if summary.fresh, plan.items.isEmpty, plan.notDownloaded == 0 {
            throw nothingToImport(in: source, fileManager: fileManager)
        }
        summary.notDownloaded = plan.notDownloaded
        plan.placeholders.forEach(downloads.request)
        if summary.fresh {
            // A first import replaces whatever sat there (stand-ins, an older import that
            // kept no list). The empty list written at once marks the import as begun, so
            // a copy cut short carries on next time instead of clearing the folder again.
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try saveManifest([:], in: destination, fileManager: fileManager)
        }
        var manifest = loadManifest(in: destination, fileManager: fileManager) ?? [:]
        var unsaved = 0
        defer {
            if unsaved > 0 { try? saveManifest(manifest, in: destination, fileManager: fileManager) }
            if summary.fresh { excludeFromBackup(destination) }
        }

        // What has to be copied, in the order it is most useful to have it.
        struct Pending {
            var item: Item
            var stamp: Stamp
            var exists: Bool
        }
        var pending: [Pending] = []
        for item in plan.items {
            let target = destination.appendingPathComponent(item.relativePath)
            let stamp = stamp(of: item.url, fileManager: fileManager)
            let exists = fileManager.fileExists(atPath: target.path)
            if exists, manifest[item.relativePath] == stamp { continue }
            pending.append(Pending(item: item, stamp: stamp, exists: exists))
        }
        func rank(_ item: Item) -> Int {
            if item.isScore || item.isAtmosphereTrack { return 0 }
            return item.isRecording ? 1 : 2
        }
        let total = pending.count
        let scoreCount = pending.filter { rank($0.item) == 0 }.count
        var local = Set(pending.filter { downloads.isLocal($0.item.url) }.map(\.item.relativePath))
        for next in pending where !local.contains(next.item.relativePath) { downloads.request(next.item.url) }
        var waiting = pending.count - local.count
        progress?(Progress(copied: 0, total: total, scoresReady: scoreCount == 0, downloading: waiting))

        // Scores and tracks first, then the files already on the device, then the rest, a
        // coordinated read of each waiting for iCloud. Every so often the files iCloud has
        // finished are looked at again, so they go before ones it is still fetching.
        func order(_ item: Item) -> (Int, Int, String) {
            (rank(item), local.contains(item.relativePath) ? 0 : 1, item.relativePath)
        }
        var index = 0
        while !pending.isEmpty {
            if shouldStop() {
                summary.stopped = true
                break
            }
            if index > 0, index % manifestSaveInterval == 0 {
                for next in pending where !local.contains(next.item.relativePath) && downloads.isLocal(next.item.url) {
                    local.insert(next.item.relativePath)
                }
                waiting = pending.filter { !local.contains($0.item.relativePath) }.count
            }
            let at = pending.indices.min { order(pending[$0].item) < order(pending[$1].item) }!
            let next = pending.remove(at: at)
            let item = next.item
            if !local.contains(item.relativePath) { waiting -= 1 }
            let target = destination.appendingPathComponent(item.relativePath)
            try replace(target, with: item.url, fileManager: fileManager)
            manifest[item.relativePath] = next.stamp
            unsaved += 1
            if unsaved >= manifestSaveInterval {
                try? saveManifest(manifest, in: destination, fileManager: fileManager)
                unsaved = 0
            }
            if next.exists { summary.updated += 1 } else { summary.added += 1 }
            if item.isScore {
                summary.scores += 1
            } else if item.isAtmosphereTrack {
                summary.atmosphereTracks += 1
            } else if item.isRecording {
                summary.recordings += 1
            }
            index += 1
            progress?(Progress(copied: index, total: total, scoresReady: index >= scoreCount, downloading: waiting))
        }
        return summary
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
}
