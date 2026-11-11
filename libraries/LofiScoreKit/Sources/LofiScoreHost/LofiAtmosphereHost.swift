import Foundation
import LofiAtmosphere
import LofiAudioCore
import LofiScoreCore
import LofiText

/// Everything the app needs for the atmosphere, in one object: the imported sounds, the
/// player, the narrator follower, each book's text and atmosphere track, and the settings.
///
/// The app's native module creates one at launch, forwards the audiobook player's events
/// (``narratorLoadedBook(id:trackFile:)``, ``narratorPlayingChanged(_:)``,
/// ``narratorClipStarted(_:audioTime:)``) and calls the settings methods from the
/// settings screen. Nothing here touches the audio session or Now Playing.
public final class LofiAtmosphereHost: @unchecked Sendable {
    /// Where things live and how to make the audio parts. ``LofiAtmosphereHost/forApp(settings:holdNarration:)``
    /// fills it in for the iPhone app; tests pass a fake backend and temporary folders.
    public struct Environment {
        public var settings: AtmosphereSettings
        /// The imported sounds, scores and tracks (see ``SoundsFolderImport``).
        public var soundsFolder: URL
        /// More places to look for book scores, besides `Scores/` in the sounds folder.
        public var scoreFolders: [URL]
        /// More places to look for atmosphere tracks, besides `AtmosphereTracks/` in the sounds folder.
        public var atmosphereTrackFolders: [URL]
        /// Storyteller's unzipped books, `<Documents>/books/extracted/`.
        public var booksFolder: URL?
        /// Makes the atmosphere's audio. Nil when this build cannot play it.
        public var makeBackend: (() -> AmbienceBackend)?
        public var makeScheduler: () -> LofiScheduler
        public var followerScheduler: LofiScheduler
        public var config: AtmosphereConfig
        /// Where synthesised stand-in sounds go for the sounds not imported. Nil plays
        /// imported sounds only.
        public var placeholderFolder: URL?
        /// Which recordings this build may play: `.personal` for Mo's own builds,
        /// `.publish` for an App Store build, which never plays a personal-use recording.
        public var soundEdition: SoundEdition
        /// Pauses the narrator for this many seconds at the end of the sentence playing now,
        /// for a swell or a hush in the atmosphere. Answers false when it cannot (and the
        /// app reports a hold that was dropped with `narrationHold(began: false)`). Nil: no
        /// pauses.
        public var holdNarration: (@Sendable (_ seconds: Double) -> Bool)?
        /// Folders the shelved music left behind, removed at launch.
        public var staleFolders: [URL]
        /// How a linked sounds folder is remembered across launches and found again: a
        /// security-scoped bookmark on Apple platforms, the path elsewhere (tests).
        public var makeBookmark: (URL) throws -> Data = FolderBookmark.make
        public var resolveBookmark: (Data) throws -> URL = FolderBookmark.resolve

        public init(
            settings: AtmosphereSettings,
            soundsFolder: URL,
            scoreFolders: [URL] = [],
            atmosphereTrackFolders: [URL] = [],
            booksFolder: URL?,
            makeBackend: (() -> AmbienceBackend)?,
            makeScheduler: @escaping () -> LofiScheduler = { DispatchScheduler(label: "LofiScore.atmosphere") },
            followerScheduler: LofiScheduler = DispatchScheduler(label: "LofiScore.follower"),
            config: AtmosphereConfig = AtmosphereConfig(),
            placeholderFolder: URL? = nil,
            soundEdition: SoundEdition = .personal,
            holdNarration: (@Sendable (_ seconds: Double) -> Bool)? = nil,
            staleFolders: [URL] = []
        ) {
            self.settings = settings
            self.soundsFolder = soundsFolder
            self.scoreFolders = scoreFolders
            self.atmosphereTrackFolders = atmosphereTrackFolders
            self.booksFolder = booksFolder
            self.makeBackend = makeBackend
            self.makeScheduler = makeScheduler
            self.followerScheduler = followerScheduler
            self.config = config
            self.placeholderFolder = placeholderFolder
            self.soundEdition = soundEdition
            self.holdNarration = holdNarration
            self.staleFolders = staleFolders
        }
    }

    /// Why the linked sounds folder is being looked at.
    public enum SyncReason: String, Sendable {
        case launch, foreground, bookOpened, manual
    }

    public let follower: NarrationFollower
    private let environment: Environment
    private var settings: AtmosphereSettings { environment.settings }
    private let queue = DispatchQueue(label: "LofiScore.host")
    private let work = DispatchQueue(label: "LofiScore.host.work", qos: .userInitiated)

    // State on `queue`.
    private var started = false
    private var book: (id: String, trackFile: URL?)?
    private var bookText: BookTextState = .none
    private var lastError: String?
    private var recentEvents: [String] = []
    // The linked sounds folder (on `queue`).
    private var syncing = false
    private var syncProgress: SoundsFolderImport.Progress?
    private var lastSyncStarted: Date?
    /// Automatic looks at the linked folder are at least this far apart.
    static let syncInterval: TimeInterval = 60

    // The atmosphere, on `queue` too.
    private var atmosphere: AmbiencePlayer?
    private var retiring: [AmbiencePlayer] = []
    private var preparing = false
    private var generation = 0
    private var source = "none"
    private var soundCount = 0
    private var variantCount = 0
    private var oneShotCount = 0
    private var track: (bookID: String, track: AtmosphereTrack?, origin: String?)?

    private enum BookTextState {
        case none
        case loading(String)
        case ready(String, SpoilerGuard)
        case unavailable(String, reason: String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    public init(environment: Environment) {
        self.environment = environment
        follower = NarrationFollower(scheduler: environment.followerScheduler)
    }

    /// Loads the sounds if the atmosphere is on, and tidies what the shelved music left
    /// behind. Call once, at launch.
    public func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            HostLog.note("started, atmosphere \(atmosphereOn ? "on" : "off"), \(environment.soundEdition.rawValue) edition")
            tidyMusicLeftovers()
            if atmosphereOn { prepareAtmosphere() }
            syncSoundsFolderIfDue(reason: .launch)
        }
    }

    /// The atmosphere is switched on and this build can play it.
    private var atmosphereOn: Bool {
        settings.atmosphereEnabled && environment.makeBackend != nil
    }

    /// What the music left in the app's folders is removed once, in the background.
    private func tidyMusicLeftovers() {
        let environment = environment
        work.async {
            var removed = SoundsFolderImport.tidyMusicLeftovers(in: environment.soundsFolder)
            for folder in environment.staleFolders where FileManager.default.fileExists(atPath: folder.path) {
                if (try? FileManager.default.removeItem(at: folder)) != nil { removed += 1 }
            }
            if removed > 0 { HostLog.note("removed \(removed) things the shelved music left behind") }
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
            track = nil
            if atmosphereOn { loadBookText() }
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
    /// begins with `clip`'s sentence. The sounds follow the pages (see
    /// ``NarrationFollower/readerReached(_:)``), if ``AtmosphereSettings/followsReading`` is on.
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

    /// Sounds while reading on screen, on or off.
    public func setFollowsReading(_ enabled: Bool) async {
        await onQueue { [self] in
            settings.followsReading = enabled
            if !enabled { follower.readerStopped() }
        }
    }

    // MARK: - Settings

    public func setMutedInCar(_ muted: Bool) async {
        await onQueue { [self] in
            settings.mutedInCar = muted
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
                if book != nil, case .none = bookText { loadBookText() }
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
            atmosphere?.setLevel(dB: levelDB)
        }
    }

    private var levelDB: Double {
        settings.atmosphereLevelDB ?? environment.config.bedLevelDB
    }

    /// How much is going on in the atmosphere, 0 to 1; nil goes back to the default.
    public func setAtmosphereIntensity(_ intensity: Double?) async {
        await onQueue { [self] in
            settings.atmosphereIntensity = intensity
            atmosphere?.setIntensity(self.intensity)
        }
    }

    private var intensity: Double {
        settings.atmosphereIntensity ?? environment.config.intensity
    }

    // MARK: - The sounds folder

    /// Copies a picked folder of sounds into the app and switches to it.
    public func importSounds(from folder: URL) async throws -> SoundsFolderImport.Summary {
        let destination = environment.soundsFolder
        let summary = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SoundsFolderImport.Summary, Error>) in
            work.async {
                let result = Result { try SoundsFolderImport.importFolder(folder, into: destination) }
                switch result {
                case let .success(summary):
                    HostLog.note(
                        "imported \(summary.folderName): \(summary.recordings) recordings, \(summary.scores) scores, "
                            + "\(summary.atmosphereTracks) atmosphere tracks, \(summary.notDownloaded) not downloaded"
                    )
                case let .failure(error):
                    HostLog.error("import failed: \(error)")
                }
                continuation.resume(with: result)
            }
        }
        await onQueue { [self] in
            settings.importedFolderName = summary.folderName
            reloadAtmosphere()
            reopenBookIfUnscored()
        }
        return summary
    }

    /// Imports the folder like ``importSounds(from:)`` and keeps a link to it, so new scores,
    /// sounds and tracks put into it later are copied without importing again (see
    /// ``syncSoundsFolder(reason:)``).
    ///
    /// The link is kept before anything is copied, and the copy goes file by file (book
    /// scores first), so an import cut short (the app closed, the phone locked for long)
    /// carries on from where it stopped at the next look at the folder instead of starting
    /// again. ``status()`` reports how far it has got.
    public func linkSoundsFolder(_ folder: URL) async throws -> SoundsFolderImport.Summary {
        let bookmark: Data
        do {
            bookmark = try environment.makeBookmark(folder)
        } catch {
            // No link can be kept: copy the folder in one go, as before.
            HostLog.error("could not keep a link to \(folder.lastPathComponent): \(error)")
            let summary = try await importSounds(from: folder)
            await onQueue { [self] in
                settings.linkedFolderBookmark = nil
                settings.linkedFolderName = nil
            }
            return summary
        }
        let destination = environment.soundsFolder
        await onQueue { [self] in
            // Another folder than last time replaces the sounds; the same folder picked
            // again carries on with (or adds to) what is there.
            let before = settings.linkedFolderName ?? settings.importedFolderName
            if let before, before != folder.lastPathComponent {
                try? FileManager.default.removeItem(at: destination.appendingPathComponent(SoundsFolderImport.manifestFileName))
            }
            settings.linkedFolderBookmark = bookmark
            settings.linkedFolderName = folder.lastPathComponent
            settings.lastSyncResult = nil
        }
        guard let synced = try await syncSoundsFolder(reason: .manual) else {
            return .init(folderName: folder.lastPathComponent, recordings: 0, scores: 0, atmosphereTracks: 0, notDownloaded: 0)
        }
        return .init(
            folderName: synced.folderName,
            recordings: synced.recordings,
            scores: synced.scores,
            atmosphereTracks: synced.atmosphereTracks,
            notDownloaded: synced.notDownloaded
        )
    }

    /// Forgets the linked folder. The sounds already imported stay.
    public func unlinkSoundsFolder() async {
        await onQueue { [self] in
            settings.linkedFolderBookmark = nil
            settings.linkedFolderName = nil
            settings.lastSyncDate = nil
            settings.lastSyncResult = nil
        }
    }

    /// Copies whatever is new in the linked sounds folder (``SoundsFolderImport/sync(_:into:fileManager:)``)
    /// and reloads what it touched: the sounds, or the open book's text when a score for it
    /// may have arrived. Nil when no folder is linked. Errors (the folder gone, iCloud not
    /// reachable) are kept for the settings screen and thrown.
    @discardableResult
    public func syncSoundsFolder(reason: SyncReason) async throws -> SoundsFolderImport.SyncSummary? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                startSync(reason: reason) { continuation.resume(with: $0) }
            }
        }
    }

    /// ``syncSoundsFolder(reason:)`` in the background, unless one ran a minute ago or is
    /// running. For launch, the app coming to the foreground, and a book opening without
    /// a score.
    public func syncSoundsFolderIfDue(reason: SyncReason) {
        queue.async { [self] in
            guard settings.linkedFolderBookmark != nil, !syncing else { return }
            if let last = lastSyncStarted, Date().timeIntervalSince(last) < Self.syncInterval { return }
            startSync(reason: reason) { _ in }
        }
    }

    /// On `queue`.
    private func startSync(reason: SyncReason, completion: @escaping (Result<SoundsFolderImport.SyncSummary?, Error>) -> Void) {
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
        let destination = environment.soundsFolder
        work.async { [weak self] in
            let result = Result { () -> (SoundsFolderImport.SyncSummary, Data?) in
                let folder = try environment.resolveBookmark(bookmark)
                let summary = try SoundsFolderImport.sync(folder, into: destination) { progress in
                    self?.queue.async { self?.noteSyncProgress(progress) }
                }
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

    /// On `queue`. Keeps the count for the settings screen, and lets the open book find
    /// its score as soon as the scores are in, while the recordings are still being copied.
    private func noteSyncProgress(_ progress: SoundsFolderImport.Progress) {
        guard syncing else { return }
        let scoresJustArrived = progress.scoresReady && syncProgress?.scoresReady != true && progress.copied > 0
        syncProgress = progress
        if scoresJustArrived { reopenBookIfUnscored() }
    }

    /// On `queue`.
    private func finishSync(
        reason: SyncReason,
        result: Result<(SoundsFolderImport.SyncSummary, Data?), Error>,
        completion: (Result<SoundsFolderImport.SyncSummary?, Error>) -> Void
    ) {
        syncing = false
        syncProgress = nil
        settings.lastSyncDate = Date()
        switch result {
        case let .success((summary, refreshed)):
            if let refreshed, refreshed != settings.linkedFolderBookmark { settings.linkedFolderBookmark = refreshed }
            settings.lastSyncResult = summary.description
            HostLog.note("sounds folder (\(reason.rawValue)): \(summary.description)")
            if summary.changed || summary.fresh {
                settings.importedFolderName = summary.folderName
                if summary.fresh || summary.recordings > 0 { reloadAtmosphere() }
                if summary.fresh || summary.scores > 0 || summary.atmosphereTracks > 0 { reopenBookIfUnscored() }
            }
            completion(.success(summary))
        case let .failure(error):
            settings.lastSyncResult = "Could not read the folder: \(error.localizedDescription)"
            HostLog.error("sounds folder (\(reason.rawValue)): \(error)")
            completion(.failure(error))
        }
    }

    /// A score may have arrived for the open book: look at its text again when it has no
    /// atmosphere track yet. A book that already has one is left alone.
    private func reopenBookIfUnscored() {
        guard let book, atmosphereOn else { return }
        let hasTrack = track?.bookID == book.id && track?.track != nil
        guard !hasTrack, !bookText.isLoading else { return }
        HostLog.note("book \(book.id): looking for its score again")
        loadBookText(replacing: true)
    }

    public enum SyncError: Error, CustomStringConvertible {
        case busy
        public var description: String { "the sounds folder is being read already" }
    }

    /// Keeps a score the app fetched from the server with its book: inside the unzipped
    /// read-aloud EPUB at `BookScore.pathInBook`, where the book's text is read from, so a
    /// re-imported sounds folder does not lose it and a deleted book takes it along. When
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

    /// The imported sounds' credits (`Atmosphere/CREDITS.md`), if the folder had them.
    public func atmosphereCredits() async -> String? {
        let folder = environment.soundsFolder.appendingPathComponent(SoundsFolderImport.atmosphereFolderName, isDirectory: true)
        return await withCheckedContinuation { continuation in
            work.async {
                let text = SoundsFolderImport.creditsFile(in: folder).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                continuation.resume(returning: text)
            }
        }
    }

    /// Deletes the imported sounds, forgets the linked folder and goes back to the stand-ins.
    public func removeImportedSounds() async {
        await onQueue { [self] in
            try? FileManager.default.removeItem(at: environment.soundsFolder)
            settings.importedFolderName = nil
            settings.linkedFolderBookmark = nil
            settings.linkedFolderName = nil
            settings.lastSyncDate = nil
            settings.lastSyncResult = nil
            reloadAtmosphere()
        }
    }

    // MARK: - Status

    public func status() async -> LofiHostStatus {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        // Named apart from the property it copies: Swift 6.2 (Xcode 26) takes a bare
        // `atmosphere` in the closure for the variable this statement declares.
        let (status, currentPlayer) = await onQueue { [self] () -> (LofiHostStatus, AmbiencePlayer?) in
            (makeStatus(followerStatus), self.atmosphere)
        }
        var result = status
        guard let player = currentPlayer else { return result }
        let ambience = await withCheckedContinuation { continuation in
            player.snapshot { continuation.resume(returning: $0) }
        }
        result.atmosphere.place = ambience.scene?.placeName ?? ambience.scene?.placeID
        result.atmosphere.playing = ambience.voices.filter { $0.playing && !$0.fadingOut }.map { $0.variant ?? $0.sound.rawValue }
        result.atmosphere.chapterDip = ambience.dipped
        result.atmosphere.routeMuted = ambience.routeMuted
        result.atmosphere.missingSounds = ambience.missingSounds.map(\.rawValue)
        result.atmosphere.engineRunning = ambience.engineRunning
        result.atmosphere.lastError = ambience.lastError
        if result.lastError == nil { result.lastError = ambience.lastError }
        return result
    }

    // MARK: - Book text

    /// Opens the book's text and looks for its atmosphere track. With `replacing`, the text
    /// already attached is swapped for the new one (a score arrived) and the book stays open.
    private func loadBookText(replacing: Bool = false) {
        guard let book else { return }
        let id = book.id
        bookText = .loading(id)
        let environment = environment
        work.async { [weak self] in
            let outcome = Self.openText(bookID: id, trackFile: book.trackFile, environment: environment)
            guard let host = self else { return }
            host.queue.async {
                let `self` = host
                guard self.book?.id == id else { return }
                switch outcome {
                case let .success((text, found)):
                    HostLog.note("book \(id): following the text; " + (found.map { "atmosphere track by \($0.track.engineID) from \($0.origin)" } ?? "no atmosphere track yet"))
                    self.bookText = .ready(id, text.spoilerGuard)
                    // The track first, so it is there when the book opens.
                    self.track = (id, found?.track, found?.origin)
                    self.atmosphere?.setTrack(found?.track, forBook: id)
                    if replacing {
                        self.follower.replaceText(text, toBook: id)
                    } else {
                        self.follower.attachText(text, toBook: id)
                    }
                    // A book without a score: its score may have arrived in the linked folder.
                    if found == nil { self.syncSoundsFolderIfDue(reason: .bookOpened) }
                case let .failure(error):
                    HostLog.note("book \(id): no atmosphere, \(error)")
                    self.bookText = .unavailable(id, reason: "\(error)")
                    self.track = (id, nil, nil)
                    self.atmosphere?.setTrack(nil, forBook: id)
                }
            }
        }
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
        environment: Environment
    ) -> Result<(BookText, (track: AtmosphereTrack, origin: String)?), Error> {
        guard let folder = BookTextLocator.epubDirectory(bookID: bookID, booksFolder: environment.booksFolder, trackFile: trackFile) else {
            return .failure(BookTextError.notFound)
        }
        do {
            let spoilerGuard = try SpoilerGuard(epubDirectory: folder)
            let found = findAtmosphere(bookID: bookID, epubDirectory: folder, environment: environment, spoilerGuard: spoilerGuard)
            return .success((BookText(spoilerGuard: spoilerGuard), found))
        } catch {
            return .failure(error)
        }
    }

    static func findAtmosphere(
        bookID: String,
        epubDirectory: URL?,
        environment: Environment,
        spoilerGuard: SpoilerGuard
    ) -> (track: AtmosphereTrack, origin: String)? {
        let scoreFolders = [environment.soundsFolder.appendingPathComponent(SoundsFolderImport.scoresFolderName, isDirectory: true)]
            + environment.scoreFolders
        let trackFolders = [environment.soundsFolder.appendingPathComponent(AtmosphereTrackFinder.tracksFolderName, isDirectory: true)]
            + environment.atmosphereTrackFolders
        return AtmosphereTrackFinder.find(
            bookID: bookID, epubDirectory: epubDirectory, scoreFolders: scoreFolders, trackFolders: trackFolders, spoilerGuard: spoilerGuard
        )
    }

    // MARK: - The player

    private func prepareAtmosphere() {
        guard !preparing, atmosphere == nil, let makeBackend = environment.makeBackend else { return }
        preparing = true
        generation += 1
        let generation = generation
        let environment = environment
        work.async { [weak self] in
            let (library, source) = Self.loadAmbience(environment)
            let oneShots = Self.loadOneShots(environment)
            guard let host = self else { return }
            host.queue.async {
                guard generation == host.generation else { return }
                host.preparing = false
                host.install(library, oneShots: oneShots, source: source, backend: makeBackend())
            }
        }
    }

    private func reloadAtmosphere() {
        preparing = false
        generation += 1
        if let old = atmosphere {
            atmosphere = nil
            // The follower pauses and closes the old player; it fades out while it waits here.
            follower.attach(nil)
            old.setEnabled(false)
            retiring.append(old)
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.retiring.removeAll { $0 === old }
            }
        }
        source = "none"
        soundCount = 0
        variantCount = 0
        oneShotCount = 0
        if atmosphereOn { prepareAtmosphere() }
    }

    /// The imported sounds (`Atmosphere/` in the sounds folder) this build may play, with
    /// synthesised stand-ins for the sounds not imported.
    static func loadAmbience(_ environment: Environment) -> (AmbienceLibrary, String) {
        let importedFolder = environment.soundsFolder.appendingPathComponent(SoundsFolderImport.atmosphereFolderName, isDirectory: true)
        let imported = (try? AmbienceLibrary.load(from: importedFolder, edition: environment.soundEdition)) ?? .empty(at: importedFolder)
        // Stand-ins are rendered only for the sounds that have no recording, so a full
        // import renders none and a first launch renders a few at a time.
        let missing = AmbientSound.allCases.filter { !imported.sounds.contains($0) }
        guard !missing.isEmpty,
              let folder = environment.placeholderFolder,
              let standIns = try? AmbienceSynth.prepare(at: folder, sounds: missing, seconds: 20, sampleRate: 24_000)
        else {
            return (imported, imported.recordings.isEmpty ? "none" : "imported")
        }
        return (imported.filling(from: standIns), imported.recordings.isEmpty ? "standIns" : "mixed")
    }

    /// The imported one-off sounds (`Atmosphere/OneShots/`) this build may play, with
    /// synthesised stand-ins for those that have simple ones.
    static func loadOneShots(_ environment: Environment) -> OneShotLibrary {
        let importedFolder = environment.soundsFolder
            .appendingPathComponent(SoundsFolderImport.atmosphereFolderName, isDirectory: true)
            .appendingPathComponent(OneShotLibrary.folderName, isDirectory: true)
        let imported = (try? OneShotLibrary.load(from: importedFolder, edition: environment.soundEdition)) ?? .empty(at: importedFolder)
        guard !Set(AmbienceSynth.oneShotStandIns).isSubset(of: imported.sounds),
              let beds = environment.placeholderFolder,
              let standIns = try? AmbienceSynth.prepareOneShots(
                  at: beds.deletingLastPathComponent().appendingPathComponent(beds.lastPathComponent + "OneShots", isDirectory: true),
                  sampleRate: 24_000
              )
        else { return imported }
        return imported.filling(from: standIns)
    }

    private func install(_ library: AmbienceLibrary, oneShots: OneShotLibrary, source: String, backend: AmbienceBackend) {
        var config = environment.config
        config.bedLevelDB = levelDB
        config.intensity = intensity
        let player = AmbiencePlayer(
            library: library, oneShots: oneShots, backend: backend, scheduler: environment.makeScheduler(), config: config
        )
        player.setMutedRoutes(settings.mutedRoutes)
        player.setEnabled(settings.atmosphereEnabled)
        player.setPausesEnabled(settings.atmospherePausesEnabled)
        player.setOneShotsEnabled(settings.atmosphereOneShotsEnabled)
        if let hold = environment.holdNarration {
            player.requestNarrationHold = { hold($0) }
        }
        player.onEvent = { [weak self] event in
            self?.record(event)
        }
        if let given = track {
            player.setTrack(given.track, forBook: given.bookID)
        }
        atmosphere = player
        self.source = source
        soundCount = library.sounds.count
        variantCount = library.variants.count
        oneShotCount = oneShots.sounds.count
        lastError = nil
        HostLog.note(
            "atmosphere: \(library.sounds.count) of \(AmbientSound.allCases.count) sounds (\(source)), "
                + "\(library.variants.count) more specific sounds, "
                + "\(oneShots.sounds.count) of \(OneShotSound.allCases.count) one-off sounds, \(environment.soundEdition.rawValue) edition"
        )
        // Brings the new player up to date with the book and the narrator.
        follower.attach(player)
    }

    private func record(_ event: AmbienceEvent) {
        let line: String
        switch event {
        case let .sceneChanged(scene):
            line = "atmosphere: \(scene.isSilent ? "quiet" : scene.layers.map(\.key).joined(separator: ", "))"
        case .musicYield:
            // A crowd scene's cue for the shelved music: nothing to do without it.
            return
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
            if case let .error(message) = event { lastError = message }
            recentEvents.append(line)
            if recentEvents.count > 20 { recentEvents.removeFirst() }
        }
    }

    // MARK: - Helpers

    private func makeStatus(_ followerStatus: NarrationFollower.Status) -> LofiHostStatus {
        let text: LofiHostStatus.Book?
        if let book {
            switch bookText {
            case .none:
                text = .init(id: book.id, text: atmosphereOn ? "waiting" : "off", detail: nil)
            case .loading:
                text = .init(id: book.id, text: "loading", detail: nil)
            case .ready:
                text = .init(id: book.id, text: "ready", detail: nil)
            case let .unavailable(_, reason):
                text = .init(id: book.id, text: "unavailable", detail: reason)
            }
        } else {
            text = nil
        }
        return LofiHostStatus(
            mutedInCar: settings.mutedInCar,
            followsReading: settings.followsReading,
            folder: .init(
                imported: SoundsFolderImport.isImported(environment.soundsFolder),
                importedFolderName: settings.importedFolderName,
                linkedFolder: settings.linkedFolderBookmark == nil ? nil : .init(
                    name: settings.linkedFolderName ?? settings.importedFolderName ?? "sounds folder",
                    lastSync: settings.lastSyncDate?.timeIntervalSince1970,
                    lastResult: settings.lastSyncResult,
                    syncing: syncing,
                    copied: syncing ? syncProgress?.copied : nil,
                    toCopy: syncing ? syncProgress?.total : nil
                )
            ),
            book: text,
            playback: .init(
                narrating: followerStatus.isNarrating,
                reading: followerStatus.isReading,
                sentence: followerStatus.position?.globalIndex,
                estimatedRate: (followerStatus.estimatedRate * 100).rounded() / 100
            ),
            atmosphere: .init(
                enabled: settings.atmosphereEnabled,
                available: environment.makeBackend != nil,
                levelDB: levelDB,
                defaultLevelDB: environment.config.bedLevelDB,
                levelRange: [AtmosphereSettings.atmosphereLevelRange.lowerBound, AtmosphereSettings.atmosphereLevelRange.upperBound],
                intensity: intensity,
                defaultIntensity: environment.config.intensity,
                source: source,
                preparing: preparing,
                sounds: soundCount,
                totalSounds: AmbientSound.allCases.count,
                variants: variantCount,
                edition: environment.soundEdition.rawValue,
                pausesEnabled: settings.atmospherePausesEnabled,
                pausesAvailable: environment.holdNarration != nil,
                oneShotsEnabled: settings.atmosphereOneShotsEnabled,
                oneShots: oneShotCount,
                totalOneShots: OneShotSound.allCases.count,
                track: book != nil && track?.bookID == book?.id && track?.track != nil,
                trackOrigin: track?.bookID == book?.id ? track?.origin : nil,
                place: nil,
                playing: [],
                chapterDip: false,
                routeMuted: false,
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

/// The atmosphere's state for the settings screen and the player's panel. Encodes to the
/// JSON the JavaScript side reads.
public struct LofiHostStatus: Codable, Sendable, Hashable {
    /// The sounds folder the app keeps up to date with.
    public struct LinkedFolder: Codable, Sendable, Hashable {
        public var name: String
        /// Seconds since 1970, when the folder was last looked at.
        public var lastSync: Double?
        /// What the last look found, or why it failed.
        public var lastResult: String?
        public var syncing: Bool
        /// While a look at the folder is copying files: how many are done, of how many.
        public var copied: Int?
        public var toCopy: Int?
    }

    /// The imported sounds folder.
    public struct Folder: Codable, Sendable, Hashable {
        /// A folder has been imported (or synced in).
        public var imported: Bool
        public var importedFolderName: String?
        /// Nil when no folder is linked.
        public var linkedFolder: LinkedFolder?
    }

    public struct Book: Codable, Sendable, Hashable {
        public var id: String
        /// "off", "waiting", "loading", "ready" or "unavailable".
        public var text: String
        public var detail: String?
    }

    public struct Playback: Codable, Sendable, Hashable {
        public var narrating: Bool
        /// Following the pages of a listener reading on screen, the narration stopped.
        public var reading: Bool
        public var sentence: Int?
        public var estimatedRate: Double
    }

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
        public var chapterDip: Bool
        /// The sounds are off because the narration plays through a muted route (the car).
        public var routeMuted: Bool
        public var missingSounds: [String]
        public var engineRunning: Bool
        public var lastError: String?
    }

    public var mutedInCar: Bool
    /// Sounds while reading on screen with the narration stopped.
    public var followsReading: Bool
    public var folder: Folder
    public var book: Book?
    public var playback: Playback
    public var atmosphere: Atmosphere
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
