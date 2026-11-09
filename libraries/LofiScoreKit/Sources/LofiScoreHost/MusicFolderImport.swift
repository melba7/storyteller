import Foundation
import LofiAtmosphere
import LofiAudio
import LofiScoreCore

/// Copies a music folder the listener picked (in Files or iCloud Drive) into the app's own
/// storage, so playback never depends on a security-scoped bookmark or on iCloud keeping
/// the files downloaded.
///
/// What is copied: the audio `MusicLibrary` plays (files directly inside a mood folder, such
/// as `Calm/`, and files `library.json` lists), `library.json`, `SOURCES.csv` and `CREDITS.md`
/// at the top,
/// mood tracks and book scores (`*.json` in `MoodTracks/`, and `*.track.json` or
/// `*.score.json` anywhere, gathered into `MoodTracks/`), and the Fast mood models at the top (embedding models named
/// `LofiMood-embed-*.json`, Core ML classifiers `.mlmodel` or `.mlmodelc`). For the
/// atmosphere: `Atmosphere/<Sound>/` and `Atmosphere/<Sound>.<Variant>/` audio with
/// `Atmosphere/sounds.json`, `variants.json`, `SOURCES.csv` and `CREDITS.md`, and atmosphere tracks (`*.atmosphere.json` anywhere, gathered into
/// `AtmosphereTracks/`). Nothing else: an audiobook unpacked somewhere in the folder is left behind.
public enum MusicFolderImport {
    public struct Summary: Sendable, Hashable, Codable {
        public var folderName: String
        public var tracks: Int
        public var moodTracks: Int
        public var hasClassifier: Bool
        /// Files that were still only in iCloud and could not be read.
        public var notDownloaded: Int
        /// Atmosphere recordings and atmosphere tracks copied.
        public var atmosphereRecordings: Int = 0
        public var atmosphereTracks: Int = 0
    }

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case noMusic(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case let .noMusic(name):
                return "\(name) has no music: it needs one folder per mood (Calm, Cozy, …) with audio files in them"
            case let .unreadable(reason):
                return "The folder could not be read: \(reason)"
            }
        }
    }

    public static let moodTracksFolderName = "MoodTracks"
    /// The atmosphere's sounds, one folder per sound (see `AmbienceLibrary`).
    public static let atmosphereFolderName = "Atmosphere"
    /// The attribution the music's licences ask for (CC BY and BY-SA tracks), shown in Settings.
    public static let creditsFileName = "CREDITS.md"

    /// The credits file in a music folder, if it has one (any capitalisation).
    public static func creditsFile(in folder: URL, fileManager: FileManager = .default) -> URL? {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.lastPathComponent.lowercased() == creditsFileName.lowercased() }
    }

    /// Copies `source` into `destination`, replacing what was there only once the copy has
    /// worked and holds at least one track.
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
        for item in plan.items {
            let target = staging.appendingPathComponent(item.relativePath, isDirectory: item.isDirectory)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copy(item.url, to: target, fileManager: fileManager)
        }

        let library: MusicLibrary
        do {
            library = try MusicLibrary.load(from: staging, fileManager: fileManager)
        } catch {
            throw ImportError.noMusic(source.lastPathComponent)
        }
        guard !library.tracks.isEmpty else { throw ImportError.noMusic(source.lastPathComponent) }

        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)
        keepStaging = true
        excludeFromBackup(destination)

        return Summary(
            folderName: source.lastPathComponent,
            tracks: library.tracks.count,
            moodTracks: plan.items.filter { $0.relativePath.hasPrefix(moodTracksFolderName + "/") }.count,
            hasClassifier: plan.items.contains { isClassifier($0.url) || isEmbeddingModel($0.url) },
            notDownloaded: plan.notDownloaded,
            atmosphereRecordings: plan.items.filter {
                $0.relativePath.hasPrefix(atmosphereFolderName + "/")
                    && AmbienceLibrary.audioExtensions.contains($0.url.pathExtension.lowercased())
            }.count,
            atmosphereTracks: plan.items.filter { $0.relativePath.hasPrefix(AtmosphereTrackFinder.tracksFolderName + "/") }.count
        )
    }

    /// The Fast mood models in a music folder, best first, for
    /// `MoodEngineCatalog.fastEngine(modelURLs:)`, which uses the first one that loads.
    /// Embedding models come first (they scored better on held-out books), the contextual
    /// ones ahead of the word one: they need Apple's downloadable assets and fall through to
    /// the next model until those are on the phone. Then the Core ML classifiers, compiled first.
    public static func moodModels(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { isEmbeddingModel($0) || isClassifier($0) }.sorted { lhs, rhs in
            (modelRank(lhs), lhs.lastPathComponent) < (modelRank(rhs), rhs.lastPathComponent)
        }
    }

    /// True when one of these models needs Apple's contextual embedding assets.
    public static func needsContextualAssets(_ models: [URL]) -> Bool {
        models.contains { isEmbeddingModel($0) && $0.lastPathComponent.lowercased().contains("contextual") }
    }

    static func modelRank(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        if isEmbeddingModel(url) {
            if name.contains("word+contextual") { return 0 }
            if name.contains("contextual") { return 1 }
            if name.contains("word") { return 2 }
            return 3
        }
        return url.pathExtension.lowercased() == "mlmodelc" ? 4 : 5
    }

    static func isEmbeddingModel(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix("lofimood-embed-") && url.pathExtension.lowercased() == "json"
    }

    // MARK: - Internals

    struct Item: Equatable {
        var url: URL
        var relativePath: String
        var isDirectory: Bool
    }

    struct Plan {
        var items: [Item] = []
        var notDownloaded = 0
    }

    static func plan(for source: URL, fileManager: FileManager) throws -> Plan {
        var plan = Plan()
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let listed = listedFiles(in: root)
        // Audio the library will play: directly inside a mood folder, or listed in library.json.
        func isMusic(_ components: [String]) -> Bool {
            guard let name = components.last,
                  MusicLibrary.audioExtensions.contains((name as NSString).pathExtension.lowercased())
            else { return false }
            return components.count == 2 && MoodBucket(lenient: components[0]) != nil
                || listed.contains(components.joined(separator: "/"))
        }
        // An atmosphere recording: `Atmosphere/<Sound>/<file>`, a variant's,
        // `Atmosphere/<Sound>.<Variant>/<file>`, or a one-off sound's,
        // `Atmosphere/OneShots/<Sound>/<file>`.
        func isAtmosphere(_ components: [String]) -> Bool {
            guard components.count == 3 || components.count == 4,
                  components[0].lowercased() == atmosphereFolderName.lowercased(),
                  let name = components.last,
                  AmbienceLibrary.audioExtensions.contains((name as NSString).pathExtension.lowercased())
            else { return false }
            if components.count == 4 {
                return components[1].lowercased() == OneShotLibrary.folderName.lowercased() && OneShotSound(lenient: components[2]) != nil
            }
            return AmbientSound(lenient: components[1]) != nil || SoundVariant.parseFolder(components[1]) != nil
        }
        // The one-off sounds' `Atmosphere/OneShots/sounds.json`.
        func isOneShotManifest(_ components: [String]) -> Bool {
            components.count == 3 && components[0].lowercased() == atmosphereFolderName.lowercased()
                && components[1].lowercased() == OneShotLibrary.folderName.lowercased()
                && components[2].lowercased() == AmbienceLibrary.manifestName
        }
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
                // An iCloud placeholder (".Song.mp3.icloud") means the file is not on the device.
                if name.hasSuffix(".icloud") {
                    let original = String(name.dropFirst().dropLast(".icloud".count))
                    let parts = Array(components.dropLast()) + [original]
                    if isMusic(parts) || isAtmosphere(parts) {
                        plan.notDownloaded += 1
                    }
                }
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            if isDirectory {
                if isClassifier(resolved) {
                    if components.count == 1 {
                        plan.items.append(Item(url: resolved, relativePath: relative, isDirectory: true))
                    }
                    enumerator.skipDescendants()
                }
                continue
            }
            if name.lowercased().hasSuffix(".track.json") || name.lowercased().hasSuffix(".score.json") {
                // Claude mood tracks and book scores from the Mac (`make-tracks.sh`), wherever they sit:
                // they all go to MoodTracks/, where the app looks for them.
                plan.items.append(Item(url: resolved, relativePath: moodTracksFolderName + "/" + name, isDirectory: false))
                continue
            }
            if name.lowercased().hasSuffix(".atmosphere.json") {
                plan.items.append(Item(url: resolved, relativePath: AtmosphereTrackFinder.tracksFolderName + "/" + name, isDirectory: false))
                continue
            }
            if isAtmosphere(components) || isOneShotManifest(components)
                || components.count == 2 && components[0].lowercased() == atmosphereFolderName.lowercased()
                && [AmbienceLibrary.manifestName, SoundVariantCatalog.fileName, "sources.csv", creditsFileName.lowercased()].contains(name.lowercased())
            {
                // Under one spelling of the folder, where the host looks.
                let rest = components.dropFirst().joined(separator: "/")
                plan.items.append(Item(url: resolved, relativePath: atmosphereFolderName + "/" + rest, isDirectory: false))
                continue
            }
            let ext = resolved.pathExtension.lowercased()
            let topLevel = components.count == 1
            if isMusic(components)
                || topLevel && (name == LibraryManifest.fileName || name.lowercased() == "sources.csv" || name.lowercased() == creditsFileName.lowercased() || ext == "mlmodel" || isEmbeddingModel(resolved))
                || components.count == 2 && components[0] == moodTracksFolderName && ext == "json"
            {
                plan.items.append(Item(url: resolved, relativePath: relative, isDirectory: false))
            }
        }
        plan.items.sort { $0.relativePath < $1.relativePath }
        return plan
    }

    /// The track files `library.json` names, if the folder has one that reads.
    static func listedFiles(in root: URL) -> Set<String> {
        let manifestURL = root.appendingPathComponent(LibraryManifest.fileName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data)
        else { return [] }
        return Set(manifest.tracks.map(\.file).filter { !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") })
    }

    static func isClassifier(_ url: URL) -> Bool {
        ["mlmodel", "mlmodelc"].contains(url.pathExtension.lowercased())
    }

    private static func copy(_ source: URL, to target: URL, fileManager: FileManager) throws {
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
