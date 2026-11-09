import Foundation
import LofiAtmosphere
import LofiAudio
import LofiMood
import LofiText
import XCTest
@testable import LofiScoreHost

final class AtmosphereHostTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        folder = fileManager.temporaryDirectory.appendingPathComponent("lofi-atmosphere-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: folder)
    }

    private func write(_ data: Data, to path: String) throws {
        let url = folder.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// An atmosphere track for `guardian`'s first sentences: a hallway full of people.
    private func track(for guardian: SpoilerGuard, bookID: String, tamper: Bool = false) throws -> AtmosphereTrack {
        var track = AtmosphereTrack(engineID: "claude.test/a1", bookID: bookID, wordsBetweenEntries: 50)
        for index in [0, 1, 2] {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
            let sentence = try XCTUnwrap(try guardian.window(at: position).lines.last?.text)
            let scene = StoryScene(placeID: "p1", placeName: "the hallway", setting: .indoors, layers: [SceneLayer(.crowd)], confidence: 0.9)
            track.insert(.init(position: position, sentence: tamper ? sentence + "!" : sentence, scene: scene))
        }
        return track
    }

    private func score(atmosphere: AtmosphereTrack?, format: Int = 1) throws -> Data {
        var object: [String: Any] = ["format": format, "mood": ["format": 1, "entries": []]]
        if let atmosphere {
            object["atmosphere"] = try JSONSerialization.jsonObject(with: atmosphere.encoded())
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Finding a book's atmosphere

    func testFindsTheAtmosphereInTheBookThenTheImportedFiles() throws {
        let guardian = try Books.text().spoilerGuard
        let scores = folder.appendingPathComponent("MoodTracks", isDirectory: true)
        let tracks = folder.appendingPathComponent("AtmosphereTracks", isDirectory: true)
        let book = folder.appendingPathComponent("Book", isDirectory: true)
        func find() -> (track: AtmosphereTrack, origin: String)? {
            AtmosphereTrackFinder.find(bookID: "abc", epubDirectory: book, scoreFolders: [scores], trackFolders: [tracks], spoilerGuard: guardian)
        }
        XCTAssertNil(find())

        try write(track(for: guardian, bookID: "plain").encoded(), to: "AtmosphereTracks/abc.atmosphere.json")
        XCTAssertEqual(find()?.track.bookID, "plain")
        XCTAssertEqual(find()?.origin, "an imported atmosphere track")

        try write(score(atmosphere: track(for: guardian, bookID: "imported score")), to: "MoodTracks/abc.score.json")
        XCTAssertEqual(find()?.track.bookID, "imported score")

        try write(score(atmosphere: track(for: guardian, bookID: "in the book")), to: "Book/" + BookScore.pathInBook)
        XCTAssertEqual(find()?.track.bookID, "in the book")
        XCTAssertEqual(find()?.origin, "the book's score")

        // A score from before the text changed is skipped, and so is a newer format.
        try write(score(atmosphere: track(for: guardian, bookID: "stale", tamper: true)), to: "Book/" + BookScore.pathInBook)
        XCTAssertEqual(find()?.track.bookID, "imported score")
        try write(score(atmosphere: track(for: guardian, bookID: "future"), format: 2), to: "Book/" + BookScore.pathInBook)
        XCTAssertThrowsError(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        XCTAssertEqual(find()?.track.bookID, "imported score")

        // A score without atmosphere, or with the old placeholder shape, has none.
        try write(score(atmosphere: nil), to: "Book/" + BookScore.pathInBook)
        XCTAssertNil(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        try write(Data(#"{"format":1,"atmosphere":{"format":1,"cues":[]}}"#.utf8), to: "Book/" + BookScore.pathInBook)
        XCTAssertNil(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))

        XCTAssertEqual(AtmosphereTrackFinder.bookName(of: tracks.appendingPathComponent("abc.atmosphere.json")), "abc")
        XCTAssertEqual(AtmosphereTrackFinder.bookName(of: tracks.appendingPathComponent("abc.score.json")), "abc")
    }

    func testTheMusicFadesOutAndBackForACrowd() {
        let scheduler = ManualScheduler()
        let yield = MusicYield(scheduler: scheduler, fade: 4)
        XCTAssertEqual(yield.volume, 1)
        yield.setYielding(true)
        scheduler.advance(by: 2)
        XCTAssertGreaterThan(yield.volume, 0)
        XCTAssertLessThan(yield.volume, 1)
        scheduler.advance(by: 2.1)
        XCTAssertEqual(yield.volume, 0, accuracy: 1e-6)
        XCTAssertEqual(scheduler.pendingCount, 0, "the ramp's timer stops when the fade is done")
        yield.setYielding(false)
        scheduler.advance(by: 4.1)
        XCTAssertEqual(yield.volume, 1, accuracy: 1e-6)
    }

    // MARK: - The whole host

    /// The music player's scheduler and its fake backend, to read the backend on its own queue.
    private final class MusicSide: @unchecked Sendable {
        let scheduler = DispatchScheduler(label: "test.player")
        private let lock = NSLock()
        private var made: FakeAudioBackend?

        func make() -> FakeAudioBackend {
            let fake = FakeAudioBackend(clock: scheduler)
            lock.withLock { made = fake }
            return fake
        }

        /// The backend's calls so far, read on the player's queue.
        func calls() async -> [FakeAudioBackend.Call] {
            guard let backend = lock.withLock({ made }) else { return [] }
            return await withCheckedContinuation { continuation in
                scheduler.perform { continuation.resume(returning: backend.calls) }
            }
        }
    }

    private func makeHost(defaults: UserDefaults, music: MusicSide = MusicSide()) -> (LofiMusicHost, () -> FakeAmbienceBackend?) {
        let scheduler = music.scheduler
        let lock = NSLock()
        var ambience: FakeAmbienceBackend?
        let environment = LofiMusicHost.Environment(
            settings: MusicSettings(defaults: defaults),
            musicFolder: folder.appendingPathComponent("app/Music", isDirectory: true),
            placeholderFolder: nil,
            booksFolder: folder.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: { music.make() },
            makePlayerScheduler: { scheduler },
            followerScheduler: DispatchScheduler(label: "test.follower"),
            makeLiveEngine: { _ in LexiconMoodEngine() },
            makeAmbienceBackend: {
                let fake = FakeAmbienceBackend()
                lock.withLock { ambience = fake }
                return fake
            },
            makeAtmosphereScheduler: { DispatchScheduler(label: "test.atmosphere") }
        )
        return (LofiMusicHost(environment: environment), { lock.withLock { ambience } })
    }

    private func waitFor(_ host: LofiMusicHost, timeout: TimeInterval = 10, _ condition: (LofiMusicStatus) -> Bool) async throws -> LofiMusicStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let status = await host.status()
            if condition(status) { return status }
            if Date() > deadline {
                XCTFail("timed out; last status: \(status)")
                return status
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The reader test book with a score holding an atmosphere track, and one imported crowd.
    private func prepareBook() throws {
        let book = folder.appendingPathComponent("books/extracted/book-1/readaloud", isDirectory: true)
        try fileManager.createDirectory(at: book.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: LofiMusicHostTests.readerBook, to: book)
        let guardian = try SpoilerGuard(epubDirectory: book)
        try write(score(atmosphere: track(for: guardian, bookID: "book-1")), to: "books/extracted/book-1/readaloud/" + BookScore.pathInBook)
        try write(Data([0]), to: "app/Music/Atmosphere/Crowd/hallway.wav")
    }

    private func narrate(_ host: LofiMusicHost) {
        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        host.narratorPlayingChanged(true)
        for index in 0..<3 {
            host.narratorClipStarted(NarratorClip(
                textResource: "OEBPS/chapter.xhtml",
                fragmentId: "sentence-\(index)",
                audioResource: "OEBPS/audio.wav",
                start: Double(index) * 3,
                end: Double(index + 1) * 3
            ))
        }
    }

    func testTheAtmosphereFollowsTheBookAndTheMusicStepsAside() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook()
        try write(Data([0]), to: "app/Music/Calm/a.mp3")
        let (host, ambience) = makeHost(defaults: defaults)
        host.start()
        var status = try await waitFor(host) { $0.library.tracks == 1 && $0.atmosphere.sounds == 1 }
        XCTAssertEqual(status.atmosphere.source, "imported")
        XCTAssertTrue(status.atmosphere.enabled)
        XCTAssertTrue(status.atmosphere.available)

        narrate(host)
        status = try await waitFor(host) { $0.atmosphere.playing == ["crowd"] && $0.atmosphere.musicYielding }
        XCTAssertTrue(status.atmosphere.track)
        XCTAssertEqual(status.atmosphere.trackOrigin, "the book's score")
        XCTAssertEqual(status.atmosphere.place, "the hallway")
        XCTAssertEqual(ambience()?.slots.first { $0.playing }?.filter, .speechSafe)
        XCTAssertNotNil(status.playback.sentence, "the music is following the same narration")

        let json = status.jsonObject()
        XCTAssertEqual((json["atmosphere"] as? [String: Any])?["playing"] as? [String], ["crowd"])

        await host.setAtmosphereLevel(dB: -30)
        status = await host.status()
        XCTAssertEqual(status.atmosphere.levelDB, -30)
        XCTAssertEqual(MusicSettings(defaults: defaults).atmosphereLevelDB, -30, "settings persist")

        await host.setAtmosphereEnabled(false)
        status = try await waitFor(host) { !$0.atmosphere.musicYielding && $0.atmosphere.playing.isEmpty }
        XCTAssertFalse(status.atmosphere.enabled)
        XCTAssertFalse(MusicSettings(defaults: defaults).atmosphereEnabled)
    }

    func testTheAtmosphereWorksWithTheMusicOff() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        MusicSettings(defaults: defaults).enabled = false
        try prepareBook()
        let (host, _) = makeHost(defaults: defaults)
        host.start()
        _ = try await waitFor(host) { $0.atmosphere.sounds == 1 }
        narrate(host)
        let status = try await waitFor(host) { $0.atmosphere.playing == ["crowd"] }
        XCTAssertEqual(status.book?.text, "ready")
        XCTAssertEqual(status.library.tracks, 0, "the music stays off")
    }

    func testTurningTheAtmosphereOnMidBookLeavesTheMusicAlone() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        MusicSettings(defaults: defaults).atmosphereEnabled = false
        try prepareBook()
        try write(Data([0]), to: "app/Music/Calm/a.mp3")
        let music = MusicSide()
        let (host, _) = makeHost(defaults: defaults, music: music)
        host.start()
        _ = try await waitFor(host) { $0.library.tracks == 1 }
        narrate(host)
        _ = try await waitFor(host) { $0.playback.musicMood != nil && $0.playback.engineRunning }
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = await music.calls()
        XCTAssertTrue(before.contains { if case .load = $0 { return true } else { return false } }, "the music is playing")

        await host.setAtmosphereEnabled(true)
        _ = try await waitFor(host) { $0.atmosphere.playing == ["crowd"] }
        // Long enough for a reopened book's fade-out (1 s) and its stopped decks.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let after = await music.calls()
        XCTAssertEqual(Array(after.dropFirst(before.count)), [], "the music was not reopened, faded out or restarted")
    }

    func testTheBuildSaysWhichSoundsItMayPlay() {
        XCTAssertEqual(LofiMusicHost.soundEdition("publish"), .publish)
        XCTAssertEqual(LofiMusicHost.soundEdition(" PUBLISH "), .publish)
        XCTAssertEqual(LofiMusicHost.soundEdition("personal"), .personal)
        XCTAssertEqual(LofiMusicHost.soundEdition(nil), .personal, "Mo's builds, which have no key, are personal")
        XCTAssertEqual(LofiMusicHost.soundEdition(1), .personal)
    }
}
