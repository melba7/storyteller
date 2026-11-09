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
            return (player, book?.id, engine)
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

    /// Deletes the imported music and goes back to the stand-ins.
    public func removeImportedMusic() async {
        await onQueue { [self] in
            try? FileManager.default.removeItem(at: environment.musicFolder)
            settings.importedFolderName = nil
            reloadLibrary()
            reloadAtmosphere()
        }
    }

    // MARK: - Status

    public func status() async -> LofiMusicStatus {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        let (status, player, atmosphere) = await onQueue { [self] in (makeStatus(followerStatus), player, atmosphere) }
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
        if let atmosphere {
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
        guard let player else { return result }
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

    private func loadBookText() {
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
                    self.follower.attachText(text, toBook: id)
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
            guard let host = self else { return }
            host.queue.async {
                guard generation == host.atmosphereGeneration else { return }
                host.preparingAtmosphere = false
                host.installAtmosphere(library, source: source, backend: makeBackend())
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
        if atmosphereOn { prepareAtmosphere() }
    }

    /// The imported sounds (`Atmosphere/` in the music folder) this build may play, with
    /// synthesised stand-ins for the sounds not imported.
    static func loadAmbience(_ environment: Environment) -> (AmbienceLibrary, String) {
        let importedFolder = environment.musicFolder.appendingPathComponent(MusicFolderImport.atmosphereFolderName, isDirectory: true)
        let imported = (try? AmbienceLibrary.load(from: importedFolder, edition: environment.soundEdition)) ?? .empty(at: importedFolder)
        guard imported.sounds.count < AmbientSound.allCases.count,
              let folder = environment.atmospherePlaceholderFolder,
              let standIns = try? AmbienceSynth.prepare(at: folder, seconds: 20, sampleRate: 24_000)
        else {
            return (imported, imported.recordings.isEmpty ? "none" : "imported")
        }
        return (imported.filling(from: standIns), imported.recordings.isEmpty ? "standIns" : "mixed")
    }

    private func installAtmosphere(_ library: AmbienceLibrary, source: String, backend: AmbienceBackend) {
        var config = environment.atmosphereConfig
        config.bedLevelDB = atmosphereLevelDB
        let player = AmbiencePlayer(library: library, backend: backend, scheduler: environment.makeAtmosphereScheduler(), config: config)
        player.setMutedRoutes(settings.mutedRoutes)
        player.setEnabled(settings.atmosphereEnabled)
        player.setPausesEnabled(settings.atmospherePausesEnabled)
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
        HostLog.note(
            "atmosphere: \(library.sounds.count) of \(AmbientSound.allCases.count) sounds (\(source)), "
                + "\(library.variants.count) more specific sounds, \(environment.soundEdition.rawValue) edition"
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
                moods: moods
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
                source: atmosphereSource,
                preparing: preparingAtmosphere,
                sounds: atmosphereSounds,
                totalSounds: AmbientSound.allCases.count,
                variants: atmosphereVariants,
                edition: environment.soundEdition.rawValue,
                pausesEnabled: settings.atmospherePausesEnabled,
                pausesAvailable: environment.holdNarration != nil,
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
