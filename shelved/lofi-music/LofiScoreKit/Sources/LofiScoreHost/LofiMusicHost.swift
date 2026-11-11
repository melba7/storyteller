import Foundation
import LofiAtmosphere
import LofiAudio
import LofiDirector
import LofiMood
import LofiPlaceholders
import LofiScoreCore
import LofiText

/// Everything the app needs for the music, in one object: the music library, the player,
/// the narrator follower, each book's text and mood engine, the atmosphere sounds, and the
/// settings.
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
        /// Makes the atmosphere's audio. Nil leaves the atmosphere out.
        public var makeAmbienceBackend: (() -> AmbienceBackend)?
        public var makeAtmosphereScheduler: () -> LofiScheduler
        public var atmosphereConfig: AtmosphereConfig
        /// Where synthesised stand-in sounds go for the sounds not imported. Nil plays
        /// imported sounds only.
        public var atmospherePlaceholderFolder: URL?
        /// More places to look for atmosphere tracks, besides `AtmosphereTracks/` in the music folder.
        public var atmosphereTrackFolders: [URL]
        /// Which recordings this build may play: `.personal` for Mo's own builds,
        /// `.publish` for an App Store build, which never plays a personal-use recording.
        public var soundEdition: SoundEdition
        /// Pauses the narrator for this many seconds at the end of the sentence playing now,
        /// for a swell or a hush in the atmosphere. Answers false when it cannot (and the
        /// app reports a hold that was dropped with `narrationHold(began: false)`). Nil: no
        /// pauses.
        public var holdNarration: (@Sendable (_ seconds: Double) -> Bool)?
        /// Where the "Wrong mood" button's log goes (``MoodFeedbackLog``). Nil: no log.
        public var feedbackFolder: URL?
        /// How a linked music folder is remembered across launches and found again: a
        /// security-scoped bookmark on Apple platforms, the path elsewhere (tests).
        public var makeBookmark: (URL) throws -> Data = FolderBookmark.make
        public var resolveBookmark: (Data) throws -> URL = FolderBookmark.resolve

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
            makeLiveEngine: @escaping (_ moodModels: [URL]) -> any MoodEngine = { MoodEngineCatalog.fastEngine(modelURLs: $0) },
            makeAmbienceBackend: (() -> AmbienceBackend)? = nil,
            makeAtmosphereScheduler: @escaping () -> LofiScheduler = { DispatchScheduler(label: "LofiScore.atmosphere") },
            atmosphereConfig: AtmosphereConfig = AtmosphereConfig(),
            atmospherePlaceholderFolder: URL? = nil,
            atmosphereTrackFolders: [URL] = [],
            soundEdition: SoundEdition = .personal,
            holdNarration: (@Sendable (_ seconds: Double) -> Bool)? = nil,
            feedbackFolder: URL? = nil
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
            self.makeAmbienceBackend = makeAmbienceBackend
            self.makeAtmosphereScheduler = makeAtmosphereScheduler
            self.atmosphereConfig = atmosphereConfig
            self.atmospherePlaceholderFolder = atmospherePlaceholderFolder
            self.atmosphereTrackFolders = atmosphereTrackFolders
            self.soundEdition = soundEdition
            self.holdNarration = holdNarration
            self.feedbackFolder = feedbackFolder
        }
    }

    /// Why the linked music folder is being looked at.
    public enum SyncReason: String, Sendable {
        case launch, foreground, bookOpened, manual
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
    /// The "Wrong mood" button's log, if the environment gives it a folder.
    public let feedback: MoodFeedbackLog?
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
    /// Whether this book's opening mood went into the wrong-mood counts yet (on `queue`).
    private var openingMoodCounted = false
    // The linked music folder (on `queue`).
    private var syncing = false
    private var lastSyncStarted: Date?
    /// Automatic looks at the linked folder are at least this far apart.
    static let syncInterval: TimeInterval = 60

    // The atmosphere, on `queue` too.
    private let sinks = NarrationFanOut()
    private let musicYield: MusicYield
    private var atmosphere: AmbiencePlayer?
    private var retiringAtmosphere: [AmbiencePlayer] = []
    private var preparingAtmosphere = false
    private var atmosphereGeneration = 0
    private var atmosphereSource = "none"
    private var atmosphereSounds = 0
    private var atmosphereVariants = 0
    private var atmosphereOneShots = 0
    private var atmosphereTrack: (bookID: String, track: AtmosphereTrack?, origin: String?)?

    private enum BookTextState: Equatable {
        case none
        case loading(String)
        case ready(String, engineID: String, moodTrack: Bool)
        case unavailable(String, reason: String)
    }

    public init(environment: Environment) {
        self.environment = environment
        feedback = environment.feedbackFolder.map { MoodFeedbackLog(folder: $0) }
        follower = NarrationFollower(scheduler: environment.followerScheduler)
        musicYield = MusicYield(scheduler: DispatchScheduler(label: "LofiScore.musicYield"), fade: environment.atmosphereConfig.musicYieldFade)
        follower.attach(sinks)
    }

    /// Loads the music and the atmosphere if they are on. Call once, at launch.
    public func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            HostLog.note("started, music \(settings.enabled ? "on" : "off"), atmosphere \(atmosphereOn ? "on" : "off")")
            if settings.enabled { prepareLibrary() }
            if atmosphereOn { prepareAtmosphere() }
            syncMusicFolderIfDue(reason: .launch)
        }
    }

    /// The atmosphere is switched on and this build can play it.
    private var atmosphereOn: Bool {
        settings.atmosphereEnabled && environment.makeAmbienceBackend != nil
    }

    /// The narration needs following: for the music, the atmosphere or both.
    private var followingOn: Bool {
        settings.enabled || atmosphereOn
    }

    // MARK: - Narrator events

    /// The audiobook player loaded a file of a book. Only a new `id` matters.
    public func narratorLoadedBook(id: String, trackFile: URL?) {
        follower.bookOpened(id: id)
        queue.async { [self] in
            guard book?.id != id else { return }
            book = (id, trackFile)
            bookText = .none
            atmosphereTrack = nil
            if followingOn { loadBookText() }
        }
    }

    public func narratorPlayingChanged(_ isPlaying: Bool) {
        follower.playingChanged(isPlaying)
    }

    public func narratorClipStarted(_ clip: NarratorClip, audioTime: Double? = nil) {
        follower.clipStarted(clip, audioTime: audioTime)
    }

    /// The narrator's pause for a swell or hush (asked for through
    /// `Environment.holdNarration`) began, or ended or was dropped.
    public func narrationHold(began: Bool) {
        queue.async { [self] in
            atmosphere?.narrationHold(began: began)
        }
    }

    // MARK: - Reading on screen

    /// The listener turned a page of `bookID` with the narration stopped, and the page now
    /// begins with `clip`'s sentence. The music follows the pages (see
    /// ``NarrationFollower/readerReached(_:)``), if ``MusicSettings/followsReading`` is on.
    public func readerReached(bookID: String, clip: NarratorClip) {
        queue.async { [self] in
            guard settings.followsReading, book?.id == bookID else { return }
            follower.readerReached(clip)
        }
    }

    /// The listener stopped reading on screen (the app went to the background).
    public func readerStopped() {
        follower.readerStopped()
    }

    /// Music while reading on screen, on or off.
    public func setFollowsReading(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.followsReading = enabled
            if !enabled { follower.readerStopped() }
        }
    }

    // MARK: - Wrong mood

    /// The listener says the mood playing is wrong. With `mood`, the music moves there;
    /// without, to the engine's next guess. Logged for the listening test. Nil when no book
    /// is playing or nothing changed.
    public func markWrongMood(_ mood: MoodBucket? = nil) async -> MoodOverride? {
        let (player, bookID, engine) = await onQueue { [self] () -> (LofiScorePlayer?, String?, String?) in
            var engine: String?
            if case let .ready(_, engineID, _) = bookText { engine = engineID }
            // `self.` because Swift 6.2 (Xcode 26) takes a bare `player` here for the
            // variable this statement declares.
            return (self.player, book?.id, engine)
        }
        guard let player, let bookID else { return nil }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<MoodOverride?, Never>) in
            player.overrideMood(to: mood) { continuation.resume(returning: $0) }
        }
        guard let result else { return nil }
        HostLog.note("listener: not \(result.rejected.rawValue), \(result.picked ? "picked" : "guessed") \(result.chosen.rawValue)")
        if let feedback {
            let entry = MoodFeedbackLog.Entry(
                bookID: bookID,
                sentence: result.sentence,
                rejected: result.rejected.rawValue,
                chosen: result.chosen.rawValue,
                how: result.picked ? "picked" : "guess",
                correction: result.correction,
                readingSource: result.readingSource?.rawValue,
                engine: result.readingSource == .live ? engine : nil,
                track: result.trackID
            )
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                work.async {
                    do {
                        try feedback.record(entry)
                    } catch {
                        HostLog.error("wrong-mood log: \(error)")
                    }
                    continuation.resume()
                }
            }
        }
        return result
    }

    /// ``markWrongMood(_:)`` for the app's bridge, with the mood named as the status names
    /// it ("cozy"). An unknown name does nothing.
    public func markWrongMood(named name: String?) async -> MoodOverride? {
        guard let name else { return await markWrongMood(nil) }
        guard let mood = MoodBucket(rawValue: name) else { return nil }
        return await markWrongMood(mood)
    }

    /// The wrong-mood log as text to share, or nil when nothing was marked yet.
    public func moodFeedbackText() async -> String? {
        guard let feedback else { return nil }
        return await withCheckedContinuation { continuation in
            work.async { continuation.resume(returning: feedback.exportText()) }
        }
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
            atmosphere?.setMutedRoutes(settings.mutedRoutes)
        }
    }

    /// Switches the atmosphere sounds on or off.
    public func setAtmosphereEnabled(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.atmosphereEnabled = enabled
            if enabled {
                if let atmosphere {
                    atmosphere.setEnabled(true)
                } else {
                    prepareAtmosphere()
                }
                if book != nil, bookText == .none { loadBookText() }
            } else {
                atmosphere?.setEnabled(false)
            }
        }
    }

    /// Short narration pauses where the atmosphere swells or hushes.
    public func setAtmospherePausesEnabled(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.atmospherePausesEnabled = enabled
            atmosphere?.setPausesEnabled(enabled)
        }
    }

    /// One-off sounds (a knock, a clap of thunder) on the sentences that say they happen.
    public func setAtmosphereOneShotsEnabled(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.atmosphereOneShotsEnabled = enabled
            atmosphere?.setOneShotsEnabled(enabled)
        }
    }

    /// The atmosphere's level under the voice in dB; nil goes back to the default.
    public func setAtmosphereLevel(dB: Double?) async {
        await onQueue { [self] in
            settings.atmosphereLevelDB = dB
            atmosphere?.setLevel(dB: atmosphereLevelDB)
        }
    }

    private var atmosphereLevelDB: Double {
        settings.atmosphereLevelDB ?? environment.atmosphereConfig.bedLevelDB
    }

    /// How much is going on in the atmosphere, 0 to 1; nil goes back to the default.
    public func setAtmosphereIntensity(_ intensity: Double?) async {
        await onQueue { [self] in
            settings.atmosphereIntensity = intensity
            atmosphere?.setIntensity(atmosphereIntensity)
        }
    }

    private var atmosphereIntensity: Double {
        settings.atmosphereIntensity ?? environment.atmosphereConfig.intensity
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
            reloadAtmosphere()
        }
        return summary
    }

    /// Imports the folder like ``importMusic(from:)`` and keeps a link to it, so new scores,
    /// sounds and tracks put into it later are copied without importing again (see
    /// ``syncMusicFolder(reason:)``).
    public func linkMusicFolder(_ folder: URL) async throws -> MusicFolderImport.Summary {
        let summary = try await importMusic(from: folder)
        let bookmark: Data?
        do {
            bookmark = try environment.makeBookmark(folder)
        } catch {
            HostLog.error("could not keep a link to \(folder.lastPathComponent): \(error)")
            bookmark = nil
        }
        await onQueue { [self] in
            settings.linkedFolderBookmark = bookmark
            settings.linkedFolderName = bookmark == nil ? nil : folder.lastPathComponent
            settings.lastSyncDate = Date()
            settings.lastSyncResult = nil
            lastSyncStarted = Date()
        }
        return summary
    }

    /// Forgets the linked folder. The music already imported stays.
    public func unlinkMusicFolder() async {
        await onQueue { [self] in
            settings.linkedFolderBookmark = nil
            settings.linkedFolderName = nil
            settings.lastSyncDate = nil
            settings.lastSyncResult = nil
        }
    }

    /// Copies whatever is new in the linked music folder (``MusicFolderImport/sync(_:into:fileManager:)``)
    /// and reloads what it touched: the music or the mood models, the atmosphere's sounds,
    /// or the open book's text when a score for it may have arrived. Nil when no folder is
    /// linked. Errors (the folder gone, iCloud not reachable) are kept for the settings
    /// screen and thrown.
    @discardableResult
    public func syncMusicFolder(reason: SyncReason) async throws -> MusicFolderImport.SyncSummary? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                startSync(reason: reason) { continuation.resume(with: $0) }
            }
        }
    }

    /// ``syncMusicFolder(reason:)`` in the background, unless one ran a minute ago or is
    /// running. For launch, the app coming to the foreground, and a book opening without
    /// a score.
    public func syncMusicFolderIfDue(reason: SyncReason) {
        queue.async { [self] in
            guard settings.linkedFolderBookmark != nil, !syncing else { return }
            if let last = lastSyncStarted, Date().timeIntervalSince(last) < Self.syncInterval { return }
            startSync(reason: reason) { _ in }
        }
    }

    /// On `queue`.
    private func startSync(reason: SyncReason, completion: @escaping (Result<MusicFolderImport.SyncSummary?, Error>) -> Void) {
        guard let bookmark = settings.linkedFolderBookmark else {
            completion(.success(nil))
            return
        }
        guard !syncing else {
            completion(.failure(SyncError.busy))
            return
        }
        syncing = true
        lastSyncStarted = Date()
        let environment = environment
        let destination = environment.musicFolder
        work.async { [weak self] in
            let result = Result { () -> (MusicFolderImport.SyncSummary, Data?) in
                let folder = try environment.resolveBookmark(bookmark)
                let summary = try MusicFolderImport.sync(folder, into: destination)
                // A bookmark goes stale when the folder moves; a fresh one keeps the link.
                let refreshed = try? environment.makeBookmark(folder)
                return (summary, refreshed)
            }
            guard let host = self else { return }
            host.queue.async {
                host.finishSync(reason: reason, result: result, completion: completion)
            }
        }
    }

    /// On `queue`.
    private func finishSync(
        reason: SyncReason,
        result: Result<(MusicFolderImport.SyncSummary, Data?), Error>,
        completion: (Result<MusicFolderImport.SyncSummary?, Error>) -> Void
    ) {
        syncing = false
        settings.lastSyncDate = Date()
        switch result {
        case let .success((summary, refreshed)):
            if let refreshed, refreshed != settings.linkedFolderBookmark { settings.linkedFolderBookmark = refreshed }
            settings.lastSyncResult = summary.description
            HostLog.note("music folder (\(reason.rawValue)): \(summary.description)")
            if summary.changed || summary.fresh {
                settings.importedFolderName = summary.folderName
                if summary.fresh || summary.music > 0 || summary.models > 0 { reloadLibrary() }
                if summary.fresh || summary.atmosphereRecordings > 0 { reloadAtmosphere() }
                if summary.moodTracks > 0 || summary.atmosphereTracks > 0 { reopenBookIfUnscored() }
            }
            completion(.success(summary))
        case let .failure(error):
            settings.lastSyncResult = "Could not read the folder: \(error.localizedDescription)"
            HostLog.error("music folder (\(reason.rawValue)): \(error)")
            completion(.failure(error))
        }
    }

    /// A score may have arrived for the open book: look at its text again when it has no
    /// mood track or no atmosphere track yet. A book that already has both is left alone.
    private func reopenBookIfUnscored() {
        guard let book, followingOn else { return }
        let hasMoodTrack: Bool
        if case let .ready(id, _, moodTrack) = bookText, id == book.id { hasMoodTrack = moodTrack } else { hasMoodTrack = false }
        let hasAtmosphere = atmosphereTrack?.bookID == book.id && atmosphereTrack?.track != nil
        guard !(hasMoodTrack && (hasAtmosphere || environment.makeAmbienceBackend == nil)) else { return }
        if case .loading = bookText { return }
        HostLog.note("book \(book.id): looking for its score again")
        loadBookText(replacing: true)
    }

    public enum SyncError: Error, CustomStringConvertible {
        case busy
        public var description: String { "the music folder is being read already" }
    }

    /// Keeps a score the app fetched from the server with its book: inside the unzipped
    /// read-aloud EPUB at `BookScore.pathInBook`, where the book's text is read from, so a
    /// re-imported music folder does not lose it and a deleted book takes it along. When
    /// that book is open and missing a track, its text is read again with the score.
    /// Throws when the data is not a score or the book's text is not on the device.
    public func installScore(_ data: Data, forBook id: String) async throws {
        let parts = try BookScore.contents(of: data)
        let (trackFile, environment) = await onQueue { [self] () -> (URL?, Environment) in
            (self.book?.id == id ? self.book?.trackFile : nil, self.environment)
        }
        let file: URL = try await withCheckedThrowingContinuation { continuation in
            work.async {
                guard let folder = BookTextLocator.epubDirectory(bookID: id, booksFolder: environment.booksFolder, trackFile: trackFile) else {
                    continuation.resume(throwing: BookTextError.notFound)
                    return
                }
                let file = folder.appendingPathComponent(BookScore.pathInBook)
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                    continuation.resume(returning: file)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        await onQueue { [self] in
            HostLog.note("book \(id): score saved in the book (mood: \(parts.mood), atmosphere: \(parts.atmosphere)) at \(file.lastPathComponent)")
            guard book?.id == id else { return }
            reopenBookIfUnscored()
        }
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

    /// The imported sounds' credits (`Atmosphere/CREDITS.md`), if the folder had them.
    public func atmosphereCredits() async -> String? {
        let folder = environment.musicFolder.appendingPathComponent(MusicFolderImport.atmosphereFolderName, isDirectory: true)
        return await withCheckedContinuation { continuation in
            work.async {
                let text = MusicFolderImport.creditsFile(in: folder).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                continuation.resume(returning: text)
            }
        }
    }

    /// Deletes the imported music, forgets the linked folder and goes back to the stand-ins.
    public func removeImportedMusic() async {
        await onQueue { [self] in
            try? FileManager.default.removeItem(at: environment.musicFolder)
            settings.importedFolderName = nil
            settings.linkedFolderBookmark = nil
            settings.linkedFolderName = nil
            settings.lastSyncDate = nil
            settings.lastSyncResult = nil
            reloadLibrary()
            reloadAtmosphere()
        }
    }

    // MARK: - Status

    public func status() async -> LofiMusicStatus {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        // Named apart from the properties they copy: Swift 6.2 (Xcode 26) takes a bare
        // `player` in the closure for the variable this statement declares.
        let (status, currentPlayer, currentAtmosphere) = await onQueue {
            [self] () -> (LofiMusicStatus, LofiScorePlayer?, AmbiencePlayer?) in
            (makeStatus(followerStatus), self.player, self.atmosphere)
        }
        var result = status
        if let feedback {
            let bookID = result.book?.id
            let (book, total) = await withCheckedContinuation { continuation in
                work.async { continuation.resume(returning: (bookID.map { feedback.counts(bookID: $0) }, feedback.counts(bookID: nil))) }
            }
            result.feedback = .init(
                bookChanges: book?.changes ?? 0,
                bookWrong: book?.wrong ?? 0,
                totalChanges: total.changes,
                totalWrong: total.wrong
            )
        }
        if let atmosphere = currentAtmosphere {
            let ambience = await withCheckedContinuation { continuation in
                atmosphere.snapshot { continuation.resume(returning: $0) }
            }
            result.atmosphere.place = ambience.scene?.placeName ?? ambience.scene?.placeID
            result.atmosphere.playing = ambience.voices.filter { $0.playing && !$0.fadingOut }.map(\.sound.rawValue)
            result.atmosphere.musicYielding = ambience.musicYielding
            result.atmosphere.chapterDip = ambience.dipped
            result.atmosphere.missingSounds = ambience.missingSounds.map(\.rawValue)
            result.atmosphere.engineRunning = ambience.engineRunning
            result.atmosphere.lastError = ambience.lastError
        }
        guard let player = currentPlayer else { return result }
        let snapshot = await withCheckedContinuation { continuation in
            player.snapshot { continuation.resume(returning: $0) }
        }
        result.playback.musicMood = snapshot.musicMood?.rawValue
        if let id = snapshot.decks.first(where: { $0.deck == snapshot.activeDeck })?.trackID,
           let track = player.library.track(id: id) {
            result.playback.nowPlaying = .init(
                title: track.displayTitle,
                artist: track.displayArtist,
                license: track.licenseName,
                mood: (snapshot.musicMood ?? track.bucket).rawValue
            )
        }
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
            sinks.setMusic(nil)
            musicYield.setPlayer(nil)
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
        musicYield.setPlayer(player)
        // Brings the new player up to date with the book and the narrator, without
        // reopening the book for the atmosphere already playing.
        follower.catchUp(player, reading: true) { [sinks] in sinks.setMusic(player) }
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
        countMoodChange(event)
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

    /// Counts the moods the music chose on its own, for the wrong-mood log: every change,
    /// and the opening mood of a book (which is not a change when it is the director's
    /// starting mood, so only the first track tells).
    private func countMoodChange(_ event: PlayerEvent) {
        guard let feedback else { return }
        queue.async { [self] in
            switch event {
            case .bookOpened, .bookClosed:
                openingMoodCounted = false
                return
            case let .moodChanged(decision):
                let counts = decision.reason != .listener
                openingMoodCounted = true
                guard counts else { return }
            case .trackStarted:
                guard !openingMoodCounted else { return }
                openingMoodCounted = true
            default:
                return
            }
            guard let id = book?.id else { return }
            work.async { feedback.noteChange(bookID: id) }
        }
    }

    // MARK: - Book text

    /// Opens the book's text and looks for its score. With `replacing`, the text already
    /// attached is swapped for the new one (a score arrived) and the book stays open.
    private func loadBookText(replacing: Bool = false) {
        guard let book else { return }
        let id = book.id
        bookText = .loading(id)
        let environment = environment
        let live = liveEngineForBooks()
        work.async { [weak self] in
            let outcome = Self.openText(bookID: id, trackFile: book.trackFile, environment: environment, live: live)
            let found: (track: AtmosphereTrack, origin: String)?
            if case let .success((text, _)) = outcome, environment.makeAmbienceBackend != nil {
                found = Self.findAtmosphere(bookID: id, trackFile: book.trackFile, environment: environment, spoilerGuard: text.spoilerGuard)
            } else {
                found = nil
            }
            guard let host = self else { return }
            host.queue.async {
                let `self` = host
                guard self.book?.id == id else { return }
                switch outcome {
                case let .success((text, hasTrack)):
                    HostLog.note("book \(id): following the text with \(hasTrack ? "a mood track over " : "")\(text.engineID)")
                    if let found {
                        HostLog.note("book \(id): atmosphere track by \(found.track.engineID) from \(found.origin)")
                    }
                    self.bookText = .ready(id, engineID: text.engineID, moodTrack: hasTrack)
                    // The atmosphere's track first, so it is there when the book opens.
                    self.atmosphereTrack = (id, found?.track, found?.origin)
                    self.atmosphere?.setTrack(found?.track, forBook: id)
                    if replacing {
                        self.follower.replaceText(text, toBook: id)
                    } else {
                        self.follower.attachText(text, toBook: id)
                    }
                    // A book without a score: its score may have arrived in the linked folder.
                    if !hasTrack || (found == nil && environment.makeAmbienceBackend != nil) {
                        self.syncMusicFolderIfDue(reason: .bookOpened)
                    }
                case let .failure(error):
                    HostLog.note("book \(id): no music, \(error)")
                    self.bookText = .unavailable(id, reason: "\(error)")
                    self.atmosphereTrack = (id, nil, nil)
                    self.atmosphere?.setTrack(nil, forBook: id)
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

    // MARK: - Atmosphere

    private func prepareAtmosphere() {
        guard !preparingAtmosphere, atmosphere == nil, let makeBackend = environment.makeAmbienceBackend else { return }
        preparingAtmosphere = true
        atmosphereGeneration += 1
        let generation = atmosphereGeneration
        let environment = environment
        work.async { [weak self] in
            let (library, source) = Self.loadAmbience(environment)
            let oneShots = Self.loadOneShots(environment)
            guard let host = self else { return }
            host.queue.async {
                guard generation == host.atmosphereGeneration else { return }
                host.preparingAtmosphere = false
                host.installAtmosphere(library, oneShots: oneShots, source: source, backend: makeBackend())
            }
        }
    }

    private func reloadAtmosphere() {
        preparingAtmosphere = false
        atmosphereGeneration += 1
        if let old = atmosphere {
            atmosphere = nil
            sinks.setAtmosphere(nil)
            old.setEnabled(false)
            old.closeBook()
            retiringAtmosphere.append(old)
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.retiringAtmosphere.removeAll { $0 === old }
            }
        }
        atmosphereSource = "none"
        atmosphereSounds = 0
        atmosphereVariants = 0
        atmosphereOneShots = 0
        if atmosphereOn { prepareAtmosphere() }
    }

    /// The imported sounds (`Atmosphere/` in the music folder) this build may play, with
    /// synthesised stand-ins for the sounds not imported.
    static func loadAmbience(_ environment: Environment) -> (AmbienceLibrary, String) {
        let importedFolder = environment.musicFolder.appendingPathComponent(MusicFolderImport.atmosphereFolderName, isDirectory: true)
        let imported = (try? AmbienceLibrary.load(from: importedFolder, edition: environment.soundEdition)) ?? .empty(at: importedFolder)
        // Stand-ins are rendered only for the sounds that have no recording, so a full
        // import renders none and a first launch renders a few at a time.
        let missing = AmbientSound.allCases.filter { !imported.sounds.contains($0) }
        guard !missing.isEmpty,
              let folder = environment.atmospherePlaceholderFolder,
              let standIns = try? AmbienceSynth.prepare(at: folder, sounds: missing, seconds: 20, sampleRate: 24_000)
        else {
            return (imported, imported.recordings.isEmpty ? "none" : "imported")
        }
        return (imported.filling(from: standIns), imported.recordings.isEmpty ? "standIns" : "mixed")
    }

    /// The imported one-off sounds (`Atmosphere/OneShots/`) this build may play, with
    /// synthesised stand-ins for those that have simple ones.
    static func loadOneShots(_ environment: Environment) -> OneShotLibrary {
        let importedFolder = environment.musicFolder
            .appendingPathComponent(MusicFolderImport.atmosphereFolderName, isDirectory: true)
            .appendingPathComponent(OneShotLibrary.folderName, isDirectory: true)
        let imported = (try? OneShotLibrary.load(from: importedFolder, edition: environment.soundEdition)) ?? .empty(at: importedFolder)
        guard !Set(AmbienceSynth.oneShotStandIns).isSubset(of: imported.sounds),
              let beds = environment.atmospherePlaceholderFolder,
              let standIns = try? AmbienceSynth.prepareOneShots(
                  at: beds.deletingLastPathComponent().appendingPathComponent(beds.lastPathComponent + "OneShots", isDirectory: true),
                  sampleRate: 24_000
              )
        else { return imported }
        return imported.filling(from: standIns)
    }

    private func installAtmosphere(_ library: AmbienceLibrary, oneShots: OneShotLibrary, source: String, backend: AmbienceBackend) {
        var config = environment.atmosphereConfig
        config.bedLevelDB = atmosphereLevelDB
        config.intensity = atmosphereIntensity
        let player = AmbiencePlayer(
            library: library, oneShots: oneShots, backend: backend, scheduler: environment.makeAtmosphereScheduler(), config: config
        )
        player.setMutedRoutes(settings.mutedRoutes)
        player.setEnabled(settings.atmosphereEnabled)
        player.setPausesEnabled(settings.atmospherePausesEnabled)
        player.setOneShotsEnabled(settings.atmosphereOneShotsEnabled)
        if let hold = environment.holdNarration {
            player.requestNarrationHold = { hold($0) }
        }
        player.onMusicYieldChanged = { [weak self] yielding in
            self?.musicYield.setYielding(yielding)
        }
        player.onEvent = { [weak self] event in
            self?.recordAtmosphere(event)
        }
        if let given = atmosphereTrack {
            player.setTrack(given.track, forBook: given.bookID)
        }
        atmosphere = player
        atmosphereSource = source
        atmosphereSounds = library.sounds.count
        atmosphereVariants = library.variants.count
        atmosphereOneShots = oneShots.sounds.count
        HostLog.note(
            "atmosphere: \(library.sounds.count) of \(AmbientSound.allCases.count) sounds (\(source)), "
                + "\(library.variants.count) more specific sounds, "
                + "\(oneShots.sounds.count) of \(OneShotSound.allCases.count) one-off sounds, \(environment.soundEdition.rawValue) edition"
        )
        // Brings the atmosphere up to date without reopening the book for the music.
        follower.catchUp(player, reading: false) { [sinks] in sinks.setAtmosphere(player) }
    }

    private func recordAtmosphere(_ event: AmbienceEvent) {
        let line: String
        switch event {
        case let .sceneChanged(scene):
            line = "atmosphere: \(scene.isSilent ? "quiet" : scene.layers.map(\.key).joined(separator: ", "))"
        case let .musicYield(yielding):
            line = yielding ? "music steps aside for a crowd" : "music back"
        case let .narrationHold(moment):
            line = "atmosphere: \(moment.rawValue), the narrator pauses briefly"
        case let .oneShot(sound):
            line = "atmosphere: one-off \(sound.rawValue)"
        case let .transition(transition):
            line = "atmosphere: \(transition.rawValue)"
        case let .missingSound(sound):
            line = "no \(sound.rawValue) sound"
        case let .error(message):
            line = "atmosphere error: \(message)"
        }
        if case .error = event { HostLog.error(line) } else { HostLog.note(line) }
        queue.async { [self] in
            recentEvents.append(line)
            if recentEvents.count > 20 { recentEvents.removeFirst() }
        }
    }

    static func findAtmosphere(
        bookID: String,
        trackFile: URL?,
        environment: Environment,
        spoilerGuard: SpoilerGuard
    ) -> (track: AtmosphereTrack, origin: String)? {
        let epub = BookTextLocator.epubDirectory(bookID: bookID, booksFolder: environment.booksFolder, trackFile: trackFile)
        let scoreFolders = [environment.musicFolder.appendingPathComponent(MusicFolderImport.moodTracksFolderName, isDirectory: true)]
            + environment.moodTrackFolders
        let trackFolders = [environment.musicFolder.appendingPathComponent(AtmosphereTrackFinder.tracksFolderName, isDirectory: true)]
            + environment.atmosphereTrackFolders
        return AtmosphereTrackFinder.find(
            bookID: bookID, epubDirectory: epub, scoreFolders: scoreFolders, trackFolders: trackFolders, spoilerGuard: spoilerGuard
        )
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
                text = .init(id: book.id, text: followingOn ? "waiting" : "off", detail: nil, engine: nil, moodTrack: false)
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
            followsReading: settings.followsReading,
            musicLevelDB: ducking.bedLevelDB,
            defaultMusicLevelDB: environment.config.ducking.bedLevelDB,
            musicLevelRange: [MusicSettings.musicLevelRange.lowerBound, MusicSettings.musicLevelRange.upperBound],
            library: .init(
                source: source.rawValue,
                preparing: preparingLibrary,
                importedFolderName: settings.importedFolderName,
                tracks: library?.tracks.count ?? 0,
                moods: moods,
                linkedFolder: settings.linkedFolderBookmark == nil ? nil : .init(
                    name: settings.linkedFolderName ?? settings.importedFolderName ?? "music folder",
                    lastSync: settings.lastSyncDate?.timeIntervalSince1970,
                    lastResult: settings.lastSyncResult,
                    syncing: syncing
                )
            ),
            book: text,
            playback: .init(
                narrating: followerStatus.isNarrating,
                reading: followerStatus.isReading,
                sentence: followerStatus.position?.globalIndex,
                estimatedRate: (followerStatus.estimatedRate * 100).rounded() / 100,
                readings: followerStatus.readingsDelivered,
                musicMood: nil,
                engineRunning: false,
                routeMuted: false,
                recentMoods: []
            ),
            atmosphere: .init(
                enabled: settings.atmosphereEnabled,
                available: environment.makeAmbienceBackend != nil,
                levelDB: atmosphereLevelDB,
                defaultLevelDB: environment.atmosphereConfig.bedLevelDB,
                levelRange: [MusicSettings.atmosphereLevelRange.lowerBound, MusicSettings.atmosphereLevelRange.upperBound],
                intensity: atmosphereIntensity,
                defaultIntensity: environment.atmosphereConfig.intensity,
                source: atmosphereSource,
                preparing: preparingAtmosphere,
                sounds: atmosphereSounds,
                totalSounds: AmbientSound.allCases.count,
                variants: atmosphereVariants,
                edition: environment.soundEdition.rawValue,
                pausesEnabled: settings.atmospherePausesEnabled,
                pausesAvailable: environment.holdNarration != nil,
                oneShotsEnabled: settings.atmosphereOneShotsEnabled,
                oneShots: atmosphereOneShots,
                totalOneShots: OneShotSound.allCases.count,
                track: book != nil && atmosphereTrack?.bookID == book?.id && atmosphereTrack?.track != nil,
                trackOrigin: atmosphereTrack?.bookID == book?.id ? atmosphereTrack?.origin : nil,
                place: nil,
                playing: [],
                musicYielding: false,
                chapterDip: false,
                missingSounds: [],
                engineRunning: false,
                lastError: nil
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

    /// The music folder the app keeps up to date with.
    public struct LinkedFolder: Codable, Sendable, Hashable {
        public var name: String
        /// Seconds since 1970, when the folder was last looked at.
        public var lastSync: Double?
        /// What the last look found, or why it failed.
        public var lastResult: String?
        public var syncing: Bool
    }

    public struct Library: Codable, Sendable, Hashable {
        /// "imported", "placeholders" or "none".
        public var source: String
        public var preparing: Bool
        public var importedFolderName: String?
        public var tracks: Int
        public var moods: [MoodCount]
        /// Nil when no folder is linked (older builds, or the link was removed).
        public var linkedFolder: LinkedFolder? = nil
    }

    public struct Book: Codable, Sendable, Hashable {
        public var id: String
        /// "off", "waiting", "loading", "ready" or "unavailable".
        public var text: String
        public var detail: String?
        public var engine: String?
        public var moodTrack: Bool
    }

    /// The track playing, for the music panel.
    public struct NowPlaying: Codable, Sendable, Hashable {
        public var title: String
        public var artist: String?
        /// The license's short name ("CC BY 4.0"), when the music folder's SOURCES.csv has it.
        public var license: String?
        public var mood: String
    }

    /// The "Wrong mood" button's counts: the music's own mood changes, and how many of them
    /// the listener marked wrong, in the open book and in all books.
    public struct Feedback: Codable, Sendable, Hashable {
        public var bookChanges: Int
        public var bookWrong: Int
        public var totalChanges: Int
        public var totalWrong: Int
    }

    public struct Playback: Codable, Sendable, Hashable {
        public var narrating: Bool
        /// Following the pages of a listener reading on screen, the narration stopped.
        public var reading: Bool = false
        public var sentence: Int?
        public var estimatedRate: Double
        public var readings: Int
        /// The mood playing now. Only the present: nothing ahead of the narration.
        public var musicMood: String?
        public var nowPlaying: NowPlaying? = nil
        public var engineRunning: Bool
        public var routeMuted: Bool
        public var recentMoods: [String]
    }

    public var enabled: Bool
    public var mutedInCar: Bool
    /// Music while reading on screen with the narration stopped.
    public var followsReading: Bool = true
    public var musicLevelDB: Double
    public var defaultMusicLevelDB: Double
    public var musicLevelRange: [Double]
    /// The atmosphere sounds.
    public struct Atmosphere: Codable, Sendable, Hashable {
        public var enabled: Bool
        /// False when this build cannot play them.
        public var available: Bool
        public var levelDB: Double
        public var defaultLevelDB: Double
        public var levelRange: [Double]
        /// How much is going on, 0 to 1 (``AtmosphereConfig/intensity``): the dial next to
        /// the volume.
        public var intensity: Double
        public var defaultIntensity: Double
        /// "imported", "standIns" (synthesised), "mixed" or "none".
        public var source: String
        public var preparing: Bool
        /// Sounds with a recording, of `totalSounds`.
        public var sounds: Int
        public var totalSounds: Int
        /// More specific sounds (church bells, a waterfall) with recordings.
        public var variants: Int
        /// "personal" (Mo's builds, personal-use recordings allowed) or "publish".
        public var edition: String
        /// Short narration pauses where the sound swells or hushes: the setting, and
        /// whether this app can pause its narrator.
        public var pausesEnabled: Bool
        public var pausesAvailable: Bool
        /// One-off sounds (a knock, a clap of thunder): the setting, and how many of the
        /// `totalOneShots` have a recording or a stand-in.
        public var oneShotsEnabled: Bool
        public var oneShots: Int
        public var totalOneShots: Int
        /// The open book has an atmosphere track, and where it came from.
        public var track: Bool
        public var trackOrigin: String?
        /// The place playing now and its sounds. Only the present: never anything ahead
        /// of the narration.
        public var place: String?
        public var playing: [String]
        public var musicYielding: Bool
        public var chapterDip: Bool
        public var missingSounds: [String]
        public var engineRunning: Bool
        public var lastError: String?
    }

    public var library: Library
    public var book: Book?
    public var playback: Playback
    public var atmosphere: Atmosphere
    public var feedback: Feedback? = nil
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

extension MoodOverride {
    /// What the "Wrong mood" button did, as a JSON object for the native module.
    public func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "rejected": rejected.rawValue,
            "chosen": chosen.rawValue,
            "picked": picked,
            "correction": correction,
        ]
        if let sentence { object["sentence"] = sentence }
        return object
    }
}
