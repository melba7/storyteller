import Foundation
import LofiAtmosphere
import LofiAudioCore
import LofiText
import XCTest
@testable import LofiScoreHost

/// The whole host: the sounds, the follower, each book's text and its atmosphere track.
final class AtmosphereHostTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    /// Upstream's `reader.epub` test book, unzipped (see LofiTextTests/Fixtures/README.md):
    /// one chapter of "sentence-<n>" clips, three seconds each, in OEBPS/audio.wav.
    static let readerBook = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("LofiTextTests/Fixtures/storyteller-reader", isDirectory: true)

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
    static func track(for guardian: SpoilerGuard, bookID: String, tamper: Bool = false) throws -> AtmosphereTrack {
        var track = AtmosphereTrack(engineID: "claude.test/a1", bookID: bookID, wordsBetweenEntries: 50)
        for index in [0, 1, 2] {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
            let sentence = try XCTUnwrap(try guardian.window(at: position).lines.last?.text)
            let scene = StoryScene(placeID: "p1", placeName: "the hallway", setting: .indoors, layers: [SceneLayer(.crowd)], confidence: 0.9)
            track.insert(.init(position: position, sentence: tamper ? sentence + "!" : sentence, scene: scene))
        }
        return track
    }

    /// A book score with the atmosphere part, and the mood part the shelved music left.
    static func score(atmosphere: AtmosphereTrack?, format: Int = 1, mood: Bool = true) throws -> Data {
        var object: [String: Any] = ["format": format]
        if mood { object["mood"] = ["format": 1, "entries": []] }
        if let atmosphere {
            object["atmosphere"] = try JSONSerialization.jsonObject(with: atmosphere.encoded())
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Finding a book's atmosphere

    func testFindsTheAtmosphereInTheBookThenTheImportedFiles() throws {
        let guardian = try Books.text().spoilerGuard
        let scores = folder.appendingPathComponent("Scores", isDirectory: true)
        let tracks = folder.appendingPathComponent("AtmosphereTracks", isDirectory: true)
        let book = folder.appendingPathComponent("Book", isDirectory: true)
        func find() -> (track: AtmosphereTrack, origin: String)? {
            AtmosphereTrackFinder.find(bookID: "abc", epubDirectory: book, scoreFolders: [scores], trackFolders: [tracks], spoilerGuard: guardian)
        }
        XCTAssertNil(find())

        try write(Self.track(for: guardian, bookID: "plain").encoded(), to: "AtmosphereTracks/abc.atmosphere.json")
        XCTAssertEqual(find()?.track.bookID, "plain")
        XCTAssertEqual(find()?.origin, "an imported atmosphere track")

        try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "imported score")), to: "Scores/abc.score.json")
        XCTAssertEqual(find()?.track.bookID, "imported score")
        XCTAssertEqual(find()?.origin, "an imported score")

        try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "in the book")), to: "Book/" + BookScore.pathInBook)
        XCTAssertEqual(find()?.track.bookID, "in the book")
        XCTAssertEqual(find()?.origin, "the book's score")

        // A score from before the text changed is skipped, and so is a newer format.
        try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "stale", tamper: true)), to: "Book/" + BookScore.pathInBook)
        XCTAssertEqual(find()?.track.bookID, "imported score")
        try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "future"), format: 2), to: "Book/" + BookScore.pathInBook)
        XCTAssertThrowsError(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        XCTAssertEqual(find()?.track.bookID, "imported score")

        // A score without atmosphere, or with the old placeholder shape, has none.
        try write(Self.score(atmosphere: nil), to: "Book/" + BookScore.pathInBook)
        XCTAssertNil(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        try write(Data(#"{"format":1,"atmosphere":{"format":1,"cues":[]}}"#.utf8), to: "Book/" + BookScore.pathInBook)
        XCTAssertNil(try BookScore.atmosphereTrack(at: book.appendingPathComponent(BookScore.pathInBook)))

        XCTAssertEqual(AtmosphereTrackFinder.bookName(of: tracks.appendingPathComponent("abc.atmosphere.json")), "abc")
        XCTAssertEqual(AtmosphereTrackFinder.bookName(of: tracks.appendingPathComponent("abc.score.json")), "abc")
    }

    func testReadsWhatAScoreHolds() throws {
        let guardian = try Books.text().spoilerGuard
        let both = try BookScore.contents(of: Self.score(atmosphere: Self.track(for: guardian, bookID: "b")))
        XCTAssertTrue(both.mood)
        XCTAssertTrue(both.atmosphere)
        let only = try BookScore.contents(of: Self.score(atmosphere: Self.track(for: guardian, bookID: "b"), mood: false))
        XCTAssertFalse(only.mood)
        XCTAssertTrue(only.atmosphere)
        XCTAssertThrowsError(try BookScore.contents(of: Data("{\"format\":1}".utf8))) { error in
            XCTAssertEqual(error as? BookScore.ScoreError, .empty)
        }
        XCTAssertThrowsError(try BookScore.contents(of: Self.score(atmosphere: nil, format: 2))) { error in
            XCTAssertEqual(error as? BookScore.ScoreError, .unsupportedFormat(2))
        }
        XCTAssertThrowsError(try BookScore.contents(of: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? BookScore.ScoreError, .notAScore)
        }
    }

    // MARK: - The whole host

    private func makeHost(defaults: UserDefaults, canPlay: Bool = true, hold: (@Sendable (Double) -> Bool)? = nil) -> (LofiAtmosphereHost, () -> FakeAmbienceBackend?) {
        let lock = NSLock()
        var ambience: FakeAmbienceBackend?
        let environment = LofiAtmosphereHost.Environment(
            settings: AtmosphereSettings(defaults: defaults),
            soundsFolder: folder.appendingPathComponent("app/Music", isDirectory: true),
            booksFolder: folder.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: canPlay ? {
                let fake = FakeAmbienceBackend()
                lock.withLock { ambience = fake }
                return fake
            } : nil,
            makeScheduler: { DispatchScheduler(label: "test.atmosphere") },
            followerScheduler: DispatchScheduler(label: "test.follower"),
            holdNarration: hold,
            staleFolders: [folder.appendingPathComponent("app/Placeholders", isDirectory: true)]
        )
        return (LofiAtmosphereHost(environment: environment), { lock.withLock { ambience } })
    }

    private func waitFor(_ host: LofiAtmosphereHost, timeout: TimeInterval = 10, _ condition: (LofiHostStatus) -> Bool) async throws -> LofiHostStatus {
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

    /// The reader test book, with a score holding an atmosphere track unless `scored` is
    /// false, and one imported crowd.
    private func prepareBook(scored: Bool = true) throws {
        let book = folder.appendingPathComponent("books/extracted/book-1/readaloud", isDirectory: true)
        try fileManager.createDirectory(at: book.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: Self.readerBook, to: book)
        if scored {
            let guardian = try SpoilerGuard(epubDirectory: book)
            try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "book-1")), to: "books/extracted/book-1/readaloud/" + BookScore.pathInBook)
        }
        try write(Data([0]), to: "app/Music/Atmosphere/Crowd/hallway.wav")
    }

    private func narrate(_ host: LofiAtmosphereHost) {
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

    func testTheAtmosphereFollowsTheBook() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook()
        try write(Data([0]), to: "app/Placeholders/calm-1.wav")
        let (host, ambience) = makeHost(defaults: defaults)
        host.start()
        var status = try await waitFor(host) { $0.atmosphere.sounds == 1 }
        XCTAssertEqual(status.atmosphere.source, "imported")
        XCTAssertTrue(status.atmosphere.enabled)
        XCTAssertTrue(status.atmosphere.available)
        XCTAssertEqual(status.atmosphere.edition, "personal")
        XCTAssertFalse(status.atmosphere.pausesAvailable, "no narrator hold in this test")
        XCTAssertFalse(status.folder.imported, "sounds in the folder, but nothing imported through the app")
        XCTAssertNil(status.book)

        narrate(host)
        status = try await waitFor(host) { $0.atmosphere.playing == ["crowd"] }
        XCTAssertEqual(status.book?.text, "ready")
        XCTAssertTrue(status.atmosphere.track)
        XCTAssertEqual(status.atmosphere.trackOrigin, "the book's score")
        XCTAssertEqual(status.atmosphere.place, "the hallway")
        XCTAssertEqual(status.playback.sentence, 2)
        XCTAssertTrue(status.playback.narrating)
        XCTAssertEqual(ambience()?.slots.first { $0.playing }?.filter, .speechSafe)

        // The status crosses to JavaScript as plain JSON.
        let json = status.jsonObject()
        XCTAssertEqual((json["atmosphere"] as? [String: Any])?["playing"] as? [String], ["crowd"])
        XCTAssertEqual((json["book"] as? [String: Any])?["text"] as? String, "ready")
        XCTAssertEqual(json["followsReading"] as? Bool, true)

        await host.setAtmosphereLevel(dB: -30)
        status = await host.status()
        XCTAssertEqual(status.atmosphere.levelDB, -30)
        XCTAssertEqual(AtmosphereSettings(defaults: defaults).atmosphereLevelDB, -30, "settings persist")
        XCTAssertEqual(status.atmosphere.levelRange, [-40, 0])
        XCTAssertEqual(status.atmosphere.intensity, 0.75, "the default")
        XCTAssertEqual(status.atmosphere.defaultIntensity, 0.75)

        await host.setAtmosphereIntensity(0.4)
        status = await host.status()
        XCTAssertEqual(status.atmosphere.intensity, 0.4)
        XCTAssertEqual(AtmosphereSettings(defaults: defaults).atmosphereIntensity, 0.4, "settings persist")
        await host.setAtmosphereIntensity(nil)
        status = await host.status()
        XCTAssertEqual(status.atmosphere.intensity, 0.75)
        XCTAssertNil(AtmosphereSettings(defaults: defaults).atmosphereIntensity)

        await host.setMutedInCar(true)
        await host.setFollowsReading(false)
        status = await host.status()
        XCTAssertTrue(status.mutedInCar)
        XCTAssertFalse(status.followsReading)
        XCTAssertTrue(AtmosphereSettings(defaults: defaults).mutedInCar)

        await host.setAtmosphereEnabled(false)
        status = try await waitFor(host) { $0.atmosphere.playing.isEmpty }
        XCTAssertFalse(status.atmosphere.enabled)
        XCTAssertFalse(AtmosphereSettings(defaults: defaults).atmosphereEnabled)

        // The shelved music's stand-ins were removed at launch.
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("app/Placeholders").path))
    }

    func testOneOffSoundsAndPausesAreSettings() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook()
        try write(Data([0]), to: "app/Music/Atmosphere/OneShots/DoorKnock/knock.wav")
        let (host, _) = makeHost(defaults: defaults, hold: { _ in true })
        host.start()
        var status = try await waitFor(host) { $0.atmosphere.sounds == 1 }
        XCTAssertEqual(status.atmosphere.oneShots, 1, "the imported knock; this build has no stand-ins")
        XCTAssertEqual(status.atmosphere.totalOneShots, OneShotSound.allCases.count)
        XCTAssertTrue(status.atmosphere.oneShotsEnabled, "on by default")
        XCTAssertTrue(status.atmosphere.pausesAvailable)
        XCTAssertTrue(status.atmosphere.pausesEnabled, "on by default")

        await host.setAtmosphereOneShotsEnabled(false)
        await host.setAtmospherePausesEnabled(false)
        status = await host.status()
        XCTAssertFalse(status.atmosphere.oneShotsEnabled)
        XCTAssertFalse(status.atmosphere.pausesEnabled)
        XCTAssertFalse(AtmosphereSettings(defaults: defaults).atmosphereOneShotsEnabled, "the setting persists")
        XCTAssertFalse(AtmosphereSettings(defaults: defaults).atmospherePausesEnabled)
        XCTAssertEqual((status.jsonObject()["atmosphere"] as? [String: Any])?["oneShotsEnabled"] as? Bool, false)
    }

    func testABuildThatCannotPlayLeavesTheBookAlone() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook()
        let (host, _) = makeHost(defaults: defaults, canPlay: false)
        host.start()
        narrate(host)
        let status = try await waitFor(host) { $0.book != nil }
        XCTAssertFalse(status.atmosphere.available)
        XCTAssertEqual(status.book?.text, "off")
        XCTAssertEqual(status.atmosphere.source, "none")
    }

    func testAnAudiobookWithoutTextHasNoAtmosphere() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try write(Data([0]), to: "app/Music/Atmosphere/Rain/rain.wav")
        let (host, _) = makeHost(defaults: defaults)
        host.start()
        _ = try await waitFor(host) { $0.atmosphere.sounds == 1 }
        host.narratorLoadedBook(id: "audio-only", trackFile: folder.appendingPathComponent("books/audio-only/part1.m4b"))
        host.narratorPlayingChanged(true)
        let status = try await waitFor(host) { $0.book?.text == "unavailable" }
        XCTAssertNotNil(status.book?.detail)
        XCTAssertFalse(status.atmosphere.track)
    }

    func testALinkedFolderBringsAScoreToTheOpenBook() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook(scored: false)
        try write(Data([0]), to: "Linked/Atmosphere/Rain/rain.m4a")
        try write(Data([0]), to: "Linked/Atmosphere/Crowd/crowd.m4a")

        let (host, _) = makeHost(defaults: defaults)
        host.start()
        _ = try await waitFor(host) { $0.atmosphere.sounds == 1 }
        let summary = try await host.linkSoundsFolder(folder.appendingPathComponent("Linked"))
        XCTAssertEqual(summary.recordings, 2)
        var status = try await waitFor(host) { $0.atmosphere.sounds == 2 }
        XCTAssertEqual(status.folder.linkedFolder?.name, "Linked")
        XCTAssertEqual(status.folder.importedFolderName, "Linked")
        XCTAssertTrue(status.folder.imported)
        XCTAssertNotNil(status.folder.linkedFolder?.lastSync)
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("app/Music/Atmosphere/Crowd/hallway.wav").path), "an import replaces the folder")

        narrate(host)
        status = try await waitFor(host) { $0.book?.text == "ready" }
        XCTAssertFalse(status.atmosphere.track)

        // The Mac scores the book into the linked folder; the next look picks it up and the
        // open book gets its score without closing.
        let guardian = try SpoilerGuard(epubDirectory: folder.appendingPathComponent("books/extracted/book-1/readaloud"))
        try write(Self.score(atmosphere: Self.track(for: guardian, bookID: "Reader")), to: "Linked/tracks/Reader.score.json")
        let synced = try await host.syncSoundsFolder(reason: .manual)
        XCTAssertEqual(synced?.scores, 1)
        status = try await waitFor(host) { $0.atmosphere.track }
        XCTAssertEqual(status.book?.text, "ready")
        XCTAssertEqual(status.atmosphere.trackOrigin, "an imported score")
        XCTAssertEqual(status.folder.linkedFolder?.lastResult, "New: 1 book score")
        status = try await waitFor(host) { $0.atmosphere.playing == ["crowd"] }
        XCTAssertEqual(status.atmosphere.sounds, 2, "the sounds were not reloaded for a score")

        // Unlinking keeps the sounds.
        await host.unlinkSoundsFolder()
        status = await host.status()
        XCTAssertNil(status.folder.linkedFolder)
        XCTAssertEqual(status.atmosphere.sounds, 2)
        let unlinked = try await host.syncSoundsFolder(reason: .manual)
        XCTAssertNil(unlinked)

        // A linked folder that went away is reported, not fatal.
        _ = try await host.linkSoundsFolder(folder.appendingPathComponent("Linked"))
        try fileManager.removeItem(at: folder.appendingPathComponent("Linked"))
        do {
            _ = try await host.syncSoundsFolder(reason: .manual)
            XCTFail("a missing folder should throw")
        } catch {}
        status = await host.status()
        XCTAssertTrue(status.folder.linkedFolder?.lastResult?.hasPrefix("Could not read the folder") == true)

        // Removing the sounds forgets the link too.
        await host.removeImportedSounds()
        status = try await waitFor(host) { $0.atmosphere.sounds == 0 }
        XCTAssertNil(status.folder.importedFolderName)
        XCTAssertNil(status.folder.linkedFolder)
        XCTAssertFalse(status.folder.imported)
    }

    func testAScoreFromTheServerIsKeptInTheBook() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-atmosphere-\(UUID().uuidString)"))
        try prepareBook(scored: false)
        let bookFolder = folder.appendingPathComponent("books/extracted/book-1/readaloud")

        let (host, _) = makeHost(defaults: defaults)
        host.start()
        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        host.narratorPlayingChanged(true)
        var status = try await waitFor(host) { $0.book?.text == "ready" }
        XCTAssertFalse(status.atmosphere.track)

        // Not a score: refused, nothing written.
        do {
            try await host.installScore(Data("{\"format\":1}".utf8), forBook: "book-1")
            XCTFail("an empty score should be refused")
        } catch {}
        XCTAssertFalse(fileManager.fileExists(atPath: bookFolder.appendingPathComponent(BookScore.pathInBook).path))

        // A book that is not on the device.
        let guardian = try SpoilerGuard(epubDirectory: bookFolder)
        let data = try Self.score(atmosphere: Self.track(for: guardian, bookID: "book-1"))
        do {
            try await host.installScore(data, forBook: "book-9")
            XCTFail("a book without text should be refused")
        } catch {}

        // The open book: the score lands inside it and the book follows it without closing.
        try await host.installScore(data, forBook: "book-1")
        XCTAssertTrue(fileManager.fileExists(atPath: bookFolder.appendingPathComponent(BookScore.pathInBook).path))
        status = try await waitFor(host) { $0.atmosphere.track }
        XCTAssertEqual(status.book?.text, "ready")
        XCTAssertEqual(status.atmosphere.trackOrigin, "the book's score")

        // Opened again later, the book brings its own score.
        host.narratorLoadedBook(id: "book-2", trackFile: nil)
        status = try await waitFor(host) { $0.book?.id == "book-2" && $0.book?.text != "loading" }
        XCTAssertFalse(status.atmosphere.track)
        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        status = try await waitFor(host) { $0.book?.id == "book-1" && $0.book?.text == "ready" && $0.atmosphere.track }
        XCTAssertTrue(status.atmosphere.track)
    }

    func testTheBuildSaysWhichSoundsItMayPlay() {
        XCTAssertEqual(LofiAtmosphereHost.soundEdition("publish"), .publish)
        XCTAssertEqual(LofiAtmosphereHost.soundEdition(" PUBLISH "), .publish)
        XCTAssertEqual(LofiAtmosphereHost.soundEdition("personal"), .personal)
        XCTAssertEqual(LofiAtmosphereHost.soundEdition(nil), .personal, "Mo's builds, which have no key, are personal")
        XCTAssertEqual(LofiAtmosphereHost.soundEdition(1), .personal)
    }
}
