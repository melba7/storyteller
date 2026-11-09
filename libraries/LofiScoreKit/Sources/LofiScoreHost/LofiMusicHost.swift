import Foundation
import LofiAudio
import LofiDirector
import LofiMood
import LofiPlaceholders
import LofiScoreCore
import LofiText

/// Everything the app needs for the music, in one object: the music library, the player,
/// the narrator follower, each book's text and mood engine, and the settings.
///
/// The app's native module creates one at launch, forwards the audiobook player's events
/// (``narratorLoadedBook(id:trackFile:)``, ``narratorPlayingChanged(_:)``,
/// ``narratorClipStarted(_:audioTime:)``) and calls the settings methods from the
/// settings screen. Nothing here touches the audio session or Now Playing.
public final class LofiMusicHost: @unchecked Sendable {
    /// Where things live and how to make the audio parts. ``LofiMusicHost/forApp()`` fills
    /// it in for the iPhone app; tests pass a fake backend and temporary folders.
    public struct Environment {
        public var settings: MusicSettings
        /// The imported music (see ``MusicFolderImport``).
        public var musicFolder: URL
        /// Where synthesised stand-in tracks go while no music has been imported. Nil
        /// leaves the music off until some is imported.
        public var placeholderFolder: URL?
        /// More places to look for mood tracks, besides `MoodTracks/` in the music folder.
        public var moodTrackFolders: [URL]
        /// Storyteller's unzipped books, `<Documents>/books/extracted/`.
        public var booksFolder: URL?
        public var config: ScoreConfig
        public var makeBackend: () -> LofiAudioBackend
        public var makePlayerScheduler: () -> LofiScheduler
        public var followerScheduler: LofiScheduler
        /// The live mood engine for places no mood track covers.
        /// The live mood engine, from the Fast models in the music folder (best first).
        public var makeLiveEngine: (_ moodModels: [URL]) -> any MoodEngine

        public init(
            settings: MusicSettings,
            musicFolder: URL,
            placeholderFolder: URL?,
            moodTrackFolders: [URL] = [],
            booksFolder: URL?,
            config: ScoreConfig = ScoreConfig(),
            makeBackend: @escaping () -> LofiAudioBackend,
            makePlayerScheduler: @escaping () -> LofiScheduler = { DispatchScheduler(label: "LofiScore.player") },
            followerScheduler: LofiScheduler = DispatchScheduler(label: "LofiScore.follower"),
            makeLiveEngine: @escaping (_ moodModels: [URL]) -> any MoodEngine = { MoodEngineCatalog.fastEngine(modelURLs: $0) }
        ) {
            self.settings = settings
            self.musicFolder = musicFolder
            self.placeholderFolder = placeholderFolder
            self.moodTrackFolders = moodTrackFolders
            self.booksFolder = booksFolder
            self.config = config
            self.makeBackend = makeBackend
            self.makePlayerScheduler = makePlayerScheduler
            self.followerScheduler = followerScheduler
            self.makeLiveEngine = makeLiveEngine
        }
    }

    public enum MusicSource: String, Codable, Sendable {
        /// Music imported from a folder.
        case imported
        /// Synthesised stand-ins, until music is imported.
        case placeholders
        /// No music yet.
        case none
    }

    public let follower: NarrationFollower
    private let environment: Environment
    private var settings: MusicSettings { environment.settings }
    private let queue = DispatchQueue(label: "LofiScore.host")
    private let work = DispatchQueue(label: "LofiScore.host.work", qos: .userInitiated)

    // State on `queue`.
    private var started = false
    private var player: LofiScorePlayer?
    private var library: MusicLibrary?
    private var source: MusicSource = .none
    private var libraryGeneration = 0
    private var preparingLibrary = false
    private var retiring: [LofiScorePlayer] = []
    private var liveEngine: (any MoodEngine)?
    private var preparingContextualAssets = false
    private var book: (id: String, trackFile: URL?)?
    private var bookText: BookTextState = .none
    private var lastError: String?
    private var recentEvents: [String] = []

    private enum BookTextState: Equatable {
        case none
        case loading(String)
        case ready(String, engineID: String, moodTrack: Bool)
        case unavailable(String, reason: String)
    }

    public init(environment: Environment) {
        self.environment = environment
        follower = NarrationFollower(scheduler: environment.followerScheduler)
    }

    /// Loads the music if it is on. Call once, at launch.
    public func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            HostLog.note("started, music \(settings.enabled ? "on" : "off")")
            if settings.enabled { prepareLibrary() }
        }
    }

    // MARK: - Narrator events

    /// The audiobook player loaded a file of a book. Only a new `id` matters.
    public func narratorLoadedBook(id: String, trackFile: URL?) {
        follower.bookOpened(id: id)
        queue.async { [self] in
            guard book?.id != id else { return }
            book = (id, trackFile)
            bookText = .none
            if settings.enabled { loadBookText() }
        }
    }

    public func narratorPlayingChanged(_ isPlaying: Bool) {
        follower.playingChanged(isPlaying)
    }

    public func narratorClipStarted(_ clip: NarratorClip, audioTime: Double? = nil) {
        follower.clipStarted(clip, audioTime: audioTime)
    }

    // MARK: - Settings

    public func setEnabled(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.enabled = enabled
            if enabled {
                if let player {
                    player.setEnabled(true)
                } else {
                    prepareLibrary()
                }
                if book != nil, bookText == .none { loadBookText() }
            } else {
                player?.setEnabled(false)
            }
        }
    }

    public func setMutedInCar(_ muted: Bool) async {
        await onQueue { [self] in
            settings.mutedInCar = muted
            player?.setMutedRoutes(settings.mutedRoutes)
        }
    }

    /// The music's level under the voice in dB; nil goes back to the default.
    public func setMusicLevel(dB: Double?) async {
        await onQueue { [self] in
            settings.musicLevelDB = dB
            player?.setDucking(settings.ducking(base: environment.config.ducking))
        }
    }

    /// Copies a picked folder of music into the app and switches to it.
    public func importMusic(from folder: URL) async throws -> MusicFolderImport.Summary {
        let destination = environment.musicFolder
        let summary = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MusicFolderImport.Summary, Error>) in
            work.async {
                let result = Result { try MusicFolderImport.importFolder(folder, into: destination) }
                switch result {
                case let .success(summary):
                    HostLog.note("imported \(summary.folderName): \(summary.tracks) tracks, \(summary.moodTracks) mood tracks, \(summary.notDownloaded) not downloaded")
                case let .failure(error):
                    HostLog.error("import failed: \(error)")
                }
                continuation.resume(with: result)
            }
        }
        await onQueue { [self] in
            settings.importedFolderName = summary.folderName
            reloadLibrary()
        }
        return summary
    }

    /// The imported music's credits (`CREDITS.md`), if the folder had them.
    public func musicCredits() async -> String? {
        let folder = environment.musicFolder
        return await withCheckedContinuation { continuation in
            work.async {
                let text = MusicFolderImport.creditsFile(in: folder).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                continuation.resume(returning: text)
            }
        }
    }

    /// Deletes the imported music and goes back to the stand-ins.
    public func removeImportedMusic() async {
        await onQueue { [self] in
            try? FileManager.default.removeItem(at: environment.musicFolder)
            settings.importedFolderName = nil
            reloadLibrary()
        }
    }

    // MARK: - Status

    public func status() async -> LofiMusicStatus {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        let (status, player) = await onQueue { [self] in (makeStatus(followerStatus), player) }
        guard let player else { return status }
        let snapshot = await withCheckedContinuation { continuation in
            player.snapshot { continuation.resume(returning: $0) }
        }
        var result = status
        result.playback.musicMood = snapshot.musicMood?.rawValue
        result.playback.engineRunning = snapshot.engineRunning
        result.playback.routeMuted = snapshot.routeMuted
        result.playback.recentMoods = snapshot.recentDecisions.suffix(5).map(\.bucket.rawValue)
        if result.lastError == nil { result.lastError = snapshot.lastError }
        return result
    }

    // MARK: - Library

    private func prepareLibrary() {
        guard !preparingLibrary, player == nil else { return }
        preparingLibrary = true
        libraryGeneration += 1
        let generation = libraryGeneration
        let environment = environment
        work.async { [weak self] in
            let loaded = Self.loadLibrary(environment)
            guard let host = self else { return }
            host.queue.async {
                let `self` = host
                guard generation == self.libraryGeneration else { return }
                self.preparingLibrary = false
                switch loaded {
                case let .success((library, source)):
                    self.install(library, source: source)
                case let .failure(error):
                    self.lastError = "\(error)"
                    HostLog.error("no music library: \(error)")
                }
            }
        }
    }

    private func reloadLibrary() {
        preparingLibrary = false
        if let player {
            retire(player)
            self.player = nil
        }
        library = nil
        source = .none
        liveEngine = nil
        if settings.enabled {
            prepareLibrary()
        } else {
            libraryGeneration += 1
        }
    }

    static func loadLibrary(_ environment: Environment) -> Result<(MusicLibrary, MusicSource), Error> {
        if let imported = try? MusicLibrary.load(from: environment.musicFolder), !imported.tracks.isEmpty {
            return .success((imported, .imported))
        }
        guard let folder = environment.placeholderFolder else {
            return .failure(LofiAudioError.emptyLibrary)
        }
        do {
            return .success((try PlaceholderLibrary.prepare(at: folder), .placeholders))
        } catch {
            return .failure(error)
        }
    }

    private func install(_ library: MusicLibrary, source: MusicSource) {
        let player = LofiScorePlayer(
            library: library,
            backend: environment.makeBackend(),
            scheduler: environment.makePlayerScheduler(),
            config: environment.config
        )
        player.setDucking(settings.ducking(base: environment.config.ducking))
        player.setMutedRoutes(settings.mutedRoutes)
        player.setEnabled(settings.enabled)
        player.onEvent = { [weak self] event in
            self?.record(event)
        }
        self.player = player
        self.library = library
        self.source = source
        lastError = nil
        HostLog.note("\(source) music: \(library.tracks.count) tracks")
        follower.attach(player)
        prepareContextualAssetsIfNeeded()
    }

    /// Keeps a replaced player alive while it fades out.
    private func retire(_ old: LofiScorePlayer) {
        retiring.append(old)
        old.setEnabled(false)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.retiring.removeAll { $0 === old }
        }
    }

    private func record(_ event: PlayerEvent) {
        let line: String
        switch event {
        case let .error(message):
            line = "error: \(message)"
        case let .moodChanged(decision):
            line = "mood: \(decision.bucket.rawValue)"
        case let .fallback(requested, used):
            line = "no \(requested.rawValue) tracks, played \(used.rawValue)"
        default:
            return
        }
        if case .error = event { HostLog.error(line) } else { HostLog.note(line) }
        queue.async { [self] in
            if case let .error(message) = event { lastError = message }
            recentEvents.append(line)
            if recentEvents.count > 20 { recentEvents.removeFirst() }
        }
    }

    // MARK: - Book text

    private func loadBookText() {
        guard let book else { return }
        let id = book.id
        bookText = .loading(id)
        let environment = environment
        let live = liveEngineForBooks()
        work.async { [weak self] in
            let outcome = Self.openText(bookID: id, trackFile: book.trackFile, environment: environment, live: live)
            guard let host = self else { return }
            host.queue.async {
                let `self` = host
                guard self.book?.id == id else { return }
                switch outcome {
                case let .success((text, hasTrack)):
                    HostLog.note("book \(id): following the text with \(hasTrack ? "a mood track over " : "")\(text.engineID)")
                    self.bookText = .ready(id, engineID: text.engineID, moodTrack: hasTrack)
                    self.follower.attachText(text, toBook: id)
                case let .failure(error):
                    HostLog.note("book \(id): no music, \(error)")
                    self.bookText = .unavailable(id, reason: "\(error)")
                }
            }
        }
    }

    /// A contextual embedding model needs Apple's English embedding assets, which iOS
    /// downloads on request. Until they are on the phone the next model in the list plays;
    /// once they arrive, the next book opened gets the contextual model.
    private func prepareContextualAssetsIfNeeded() {
        guard !preparingContextualAssets,
              MusicFolderImport.needsContextualAssets(MusicFolderImport.moodModels(in: environment.musicFolder))
        else { return }
        #if canImport(NaturalLanguage) && canImport(CoreML)
        guard #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) else { return }
        preparingContextualAssets = true
        Task.detached(priority: .background) { [weak self] in
            let ready = await ClassifierMoodEngine.prepareAssets()
            guard let host = self else { return }
            host.queue.async {
                host.preparingContextualAssets = false
                HostLog.note(ready ? "contextual embedding assets on the device" : "contextual embedding assets not available")
                if ready { host.liveEngine = nil }
            }
        }
        #endif
    }

    private func liveEngineForBooks() -> any MoodEngine {
        if let liveEngine { return liveEngine }
        let models = MusicFolderImport.moodModels(in: environment.musicFolder)
        let engine = environment.makeLiveEngine(models)
        HostLog.note("mood models: \(models.isEmpty ? "none" : models.map(\.lastPathComponent).joined(separator: ", ")); live engine \(engine.id)")
        liveEngine = engine
        return engine
    }

    public enum BookTextError: Error, CustomStringConvertible {
        case notFound

        public var description: String {
            "this book's text was not found on the device (an audiobook without its ebook has nothing to follow)"
        }
    }

    static func openText(
        bookID: String,
        trackFile: URL?,
        environment: Environment,
        live: any MoodEngine
    ) -> Result<(BookText, Bool), Error> {
        guard let folder = BookTextLocator.epubDirectory(bookID: bookID, booksFolder: environment.booksFolder, trackFile: trackFile) else {
            return .failure(BookTextError.notFound)
        }
        do {
            let spoilerGuard = try SpoilerGuard(epubDirectory: folder)
            let trackFolders = [environment.musicFolder.appendingPathComponent(MusicFolderImport.moodTracksFolderName, isDirectory: true)]
                + environment.moodTrackFolders
            // The score inside the book first, then the imported tracks and scores.
            let inBook = MoodTrackFinder.inBook(epubDirectory: folder, spoilerGuard: spoilerGuard)
            let track = inBook ?? MoodTrackFinder.find(bookID: bookID, in: trackFolders, spoilerGuard: spoilerGuard)
            if let track {
                HostLog.note("book \(bookID): mood track by \(track.engineID) from \(inBook != nil ? "the book's score" : "the imported tracks")")
            }
            let engine: any MoodEngine = track.map { TrackedMoodEngine(store: MoodTrackStore($0), fallback: live) } ?? live
            return .success((BookText(spoilerGuard: spoilerGuard, engine: engine), track != nil))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Helpers

    private func makeStatus(_ followerStatus: NarrationFollower.Status) -> LofiMusicStatus {
        // Every mood, with no tracks before the library loads, so the app can name the folders.
        let moods = MoodBucket.allCases.map {
            LofiMusicStatus.MoodCount(mood: $0.rawValue, tracks: library?.tracks(in: $0).count ?? 0)
        }
        let text: LofiMusicStatus.Book?
        if let book {
            switch bookText {
            case .none:
                text = .init(id: book.id, text: settings.enabled ? "waiting" : "off", detail: nil, engine: nil, moodTrack: false)
            case .loading:
                text = .init(id: book.id, text: "loading", detail: nil, engine: nil, moodTrack: false)
            case let .ready(_, engineID, moodTrack):
                text = .init(id: book.id, text: "ready", detail: nil, engine: engineID, moodTrack: moodTrack)
            case let .unavailable(_, reason):
                text = .init(id: book.id, text: "unavailable", detail: reason, engine: nil, moodTrack: false)
            }
        } else {
            text = nil
        }
        let ducking = settings.ducking(base: environment.config.ducking)
        return LofiMusicStatus(
            enabled: settings.enabled,
            mutedInCar: settings.mutedInCar,
            musicLevelDB: ducking.bedLevelDB,
            defaultMusicLevelDB: environment.config.ducking.bedLevelDB,
            musicLevelRange: [MusicSettings.musicLevelRange.lowerBound, MusicSettings.musicLevelRange.upperBound],
            library: .init(
                source: source.rawValue,
                preparing: preparingLibrary,
                importedFolderName: settings.importedFolderName,
                tracks: library?.tracks.count ?? 0,
                moods: moods
            ),
            book: text,
            playback: .init(
                narrating: followerStatus.isNarrating,
                sentence: followerStatus.position?.globalIndex,
                estimatedRate: (followerStatus.estimatedRate * 100).rounded() / 100,
                readings: followerStatus.readingsDelivered,
                musicMood: nil,
                engineRunning: false,
                routeMuted: false,
                recentMoods: []
            ),
            recentEvents: recentEvents,
            lastError: lastError
        )
    }

    private func onQueue<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}

/// The music's state for the settings screen. Encodes to the JSON the JavaScript side reads.
public struct LofiMusicStatus: Codable, Sendable, Hashable {
    public struct MoodCount: Codable, Sendable, Hashable {
        public var mood: String
        public var tracks: Int
    }

    public struct Library: Codable, Sendable, Hashable {
        /// "imported", "placeholders" or "none".
        public var source: String
        public var preparing: Bool
        public var importedFolderName: String?
        public var tracks: Int
        public var moods: [MoodCount]
    }

    public struct Book: Codable, Sendable, Hashable {
        public var id: String
        /// "off", "waiting", "loading", "ready" or "unavailable".
        public var text: String
        public var detail: String?
        public var engine: String?
        public var moodTrack: Bool
    }

    public struct Playback: Codable, Sendable, Hashable {
        public var narrating: Bool
        public var sentence: Int?
        public var estimatedRate: Double
        public var readings: Int
        /// The mood playing now. Only the present: nothing ahead of the narration.
        public var musicMood: String?
        public var engineRunning: Bool
        public var routeMuted: Bool
        public var recentMoods: [String]
    }

    public var enabled: Bool
    public var mutedInCar: Bool
    public var musicLevelDB: Double
    public var defaultMusicLevelDB: Double
    public var musicLevelRange: [Double]
    public var library: Library
    public var book: Book?
    public var playback: Playback
    public var recentEvents: [String]
    public var lastError: String?

    /// The status as a JSON object, for the native module to hand to JavaScript.
    public func jsonObject() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
