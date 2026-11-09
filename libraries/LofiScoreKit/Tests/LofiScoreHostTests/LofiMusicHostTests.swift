import Foundation
import LofiAudio
import LofiDirector
import LofiMood
import LofiScoreCore
import LofiText
import XCTest
@testable import LofiScoreHost

final class LofiMusicHostTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    /// Upstream's `reader.epub` test book, unzipped (see LofiTextTests/Fixtures/README.md):
    /// one chapter of "sentence-<n>" clips, three seconds each, in OEBPS/audio.wav.
    static let readerBook = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("LofiTextTests/Fixtures/storyteller-reader", isDirectory: true)

    override func setUpWithError() throws {
        folder = fileManager.temporaryDirectory.appendingPathComponent("lofi-host-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: folder)
    }

    private func touch(_ path: String, in root: URL? = nil, contents: Data = Data([0])) throws {
        let url = (root ?? folder).appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    private func files(under root: URL) -> [String] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        var result: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if !isDirectory.boolValue {
                result.append(String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count)))
            }
        }
        return result.sorted()
    }

    // MARK: - Finding a book's text

    func testFindsStorytellersUnzippedBook() throws {
        let books = folder.appendingPathComponent("books/extracted", isDirectory: true)
        try touch("books/extracted/abc/readaloud/META-INF/container.xml")
        let found = BookTextLocator.epubDirectory(bookID: "abc", booksFolder: books, trackFile: nil)
        XCTAssertEqual(found?.standardizedFileURL, books.appendingPathComponent("abc/readaloud").standardizedFileURL)
        XCTAssertNil(BookTextLocator.epubDirectory(bookID: "other", booksFolder: books, trackFile: nil))
    }

    func testFallsBackToTheFoldersAboveTheAudio() throws {
        try touch("elsewhere/book/META-INF/container.xml")
        try touch("elsewhere/book/OEBPS/Audio/00001.mp4")
        let audio = folder.appendingPathComponent("elsewhere/book/OEBPS/Audio/00001.mp4")
        let found = BookTextLocator.epubDirectory(bookID: "abc", booksFolder: folder, trackFile: audio)
        XCTAssertEqual(found?.standardizedFileURL, folder.appendingPathComponent("elsewhere/book").standardizedFileURL)
    }

    // MARK: - Mood tracks

    private func track(for guardian: SpoilerGuard, bookID: String, tamper: Bool = false) throws -> MoodTrack {
        var track = MoodTrack(engineID: "claude/test", bookID: bookID, wordsBetweenEntries: 50)
        for index in [0, 4, 8] {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
            let sentence = try XCTUnwrap(try guardian.window(at: position).lines.last?.text)
            let reading = MoodReading(bucket: .tense, valence: -0.4, arousal: 0.8, confidence: 0.9, engineID: "claude/test")
            track.insert(MoodTrack.Entry(position: position, sentence: tamper ? sentence + "!" : sentence, reading: reading))
        }
        return track
    }

    func testFindsAMoodTrackByItsText() throws {
        let guardian = try Books.text().spoilerGuard
        let tracks = folder.appendingPathComponent("MoodTracks", isDirectory: true)
        try track(for: guardian, bookID: "another book", tamper: true).save(to: tracks.appendingPathComponent("abc.json"))
        try track(for: guardian, bookID: "Some Book.epub").save(to: tracks.appendingPathComponent("some-book.json"))

        let found = MoodTrackFinder.find(bookID: "abc", in: [tracks], spoilerGuard: guardian)
        XCTAssertEqual(found?.bookID, "Some Book.epub", "a track named for the book but made from other text is skipped")
        XCTAssertNil(MoodTrackFinder.find(bookID: "abc", in: [folder.appendingPathComponent("missing")], spoilerGuard: guardian))
    }

    private func score(_ mood: MoodTrack?, format: Int = 1) throws -> Data {
        var object: [String: Any] = ["format": format, "atmosphere": ["format": 1, "cues": []]]
        if let mood {
            object["mood"] = try JSONSerialization.jsonObject(with: mood.encoded())
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testReadsTheMoodPartOfABookScore() throws {
        let guardian = try Books.text().spoilerGuard
        let tracks = folder.appendingPathComponent("MoodTracks", isDirectory: true)
        try touch("MoodTracks/abc.score.json", contents: score(track(for: guardian, bookID: "From the Mac")))
        XCTAssertEqual(MoodTrackFinder.find(bookID: "abc", in: [tracks], spoilerGuard: guardian)?.bookID, "From the Mac")
        XCTAssertEqual(MoodTrackFinder.bookName(of: tracks.appendingPathComponent("abc.score.json")), "abc")

        // Inside the book: used when it matches the text, and only then.
        let book = folder.appendingPathComponent("Book", isDirectory: true)
        try touch("Book/" + BookScore.pathInBook, contents: score(track(for: guardian, bookID: "In the book")))
        XCTAssertEqual(MoodTrackFinder.inBook(epubDirectory: book, spoilerGuard: guardian)?.bookID, "In the book")
        try touch("Book/" + BookScore.pathInBook, contents: score(track(for: guardian, bookID: "Stale", tamper: true)))
        XCTAssertNil(MoodTrackFinder.inBook(epubDirectory: book, spoilerGuard: guardian))

        // A score with only atmosphere cues has no mood track; a newer format is not guessed at.
        try touch("Book/" + BookScore.pathInBook, contents: score(nil))
        XCTAssertNil(try BookScore.moodTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        try touch("Book/" + BookScore.pathInBook, contents: score(track(for: guardian, bookID: "Future"), format: 2))
        XCTAssertThrowsError(try BookScore.moodTrack(at: book.appendingPathComponent(BookScore.pathInBook)))
        XCTAssertNil(MoodTrackFinder.inBook(epubDirectory: book, spoilerGuard: guardian))
    }

    // MARK: - Importing music

    func testImportsOnlyTheMusicAndItsCompanions() throws {
        let source = folder.appendingPathComponent("Picked Music", isDirectory: true)
        try touch("Picked Music/Calm/rain 70bpm.mp3")
        try touch("Picked Music/Calm/.hidden.mp3")
        try touch("Picked Music/Calm/.Waves.m4a.icloud")
        try touch("Picked Music/Cozy/fire.m4a")
        try touch("Picked Music/Tense/storm.wav")
        try touch("Picked Music/stray.mp3")
        try touch("Picked Music/notes.txt")
        try touch("Picked Music/.DS_Store")
        try touch("Picked Music/SOURCES.csv", contents: Data("file,license\nfire.m4a,CC0\n".utf8))
        try touch("Picked Music/Credits.md", contents: Data("# Music credits\n".utf8))
        try touch("Picked Music/MoodTracks/some-book.json")
        try touch("Picked Music/MoodTracks/readme.txt")
        try touch("Picked Music/tracks/The Green Lantern.track.json")
        try touch("Picked Music/tracks/The Green Lantern.score.json")
        // An unpacked read-aloud book next to its track: its narration is not music.
        try touch("Picked Music/tracks/books/The Green Lantern/OEBPS/Audio/00001.mp3")
        try touch("Picked Music/tracks/books/The Green Lantern/OEBPS/Audio/.00002.mp3.icloud")
        try touch("Picked Music/Unsorted/loose.mp3")
        try touch("Picked Music/Mood.mlmodelc/model.mil")
        try touch("Picked Music/Mood.mlmodelc/weights/weight.bin")
        try touch("Picked Music/LofiMood-embed-word-3.json")
        try touch("Picked Music/LofiMood-embed-word+contextual-3.json")
        try touch("Picked Music/Old.mlmodel")
        try touch("Picked Music/tracks/LofiMood-embed-stray.json")
        // The atmosphere's sounds and tracks.
        try touch("Picked Music/Atmosphere/Rain/rain-1.m4a")
        try touch("Picked Music/Atmosphere/Rain/.rain-2.m4a.icloud")
        try touch("Picked Music/Atmosphere/Rain/notes.txt")
        try touch("Picked Music/Atmosphere/Bagpipes/drone.wav")
        try touch("Picked Music/Atmosphere/sounds.json")
        try touch("Picked Music/Atmosphere/SOURCES.csv")
        try touch("Picked Music/tracks/The Green Lantern.atmosphere.json")

        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("app/Music/Old/old.mp3")

        let summary = try MusicFolderImport.importFolder(source, into: destination)
        XCTAssertEqual(summary, .init(
            folderName: "Picked Music", tracks: 3, moodTracks: 3, hasClassifier: true, notDownloaded: 2,
            atmosphereRecordings: 1, atmosphereTracks: 1
        ))
        XCTAssertEqual(files(under: destination), [
            "Atmosphere/Rain/rain-1.m4a",
            "Atmosphere/SOURCES.csv",
            "Atmosphere/sounds.json",
            "AtmosphereTracks/The Green Lantern.atmosphere.json",
            "Calm/rain 70bpm.mp3",
            "Cozy/fire.m4a",
            "Credits.md",
            "LofiMood-embed-word+contextual-3.json",
            "LofiMood-embed-word-3.json",
            "Mood.mlmodelc/model.mil",
            "Mood.mlmodelc/weights/weight.bin",
            "MoodTracks/The Green Lantern.score.json",
            "MoodTracks/The Green Lantern.track.json",
            "MoodTracks/some-book.json",
            "Old.mlmodel",
            "SOURCES.csv",
            "Tense/storm.wav",
        ])
        XCTAssertEqual(MusicFolderImport.moodModels(in: destination).map(\.lastPathComponent), [
            "LofiMood-embed-word+contextual-3.json",
            "LofiMood-embed-word-3.json",
            "Mood.mlmodelc",
            "Old.mlmodel",
        ])
        XCTAssertTrue(MusicFolderImport.needsContextualAssets(MusicFolderImport.moodModels(in: destination)))
        XCTAssertEqual(MusicFolderImport.creditsFile(in: destination)?.lastPathComponent, "Credits.md")
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path + ".incoming"))
    }

    func testImportsWhatLibraryJSONLists() throws {
        let manifest = #"{"version":1,"tracks":[{"id":"calm/a","file":"Mastered/Calm/a.m4a","bucket":"calm"}]}"#
        try touch("Listed/library.json", contents: Data(manifest.utf8))
        try touch("Listed/Mastered/Calm/a.m4a")
        try touch("Listed/Mastered/Calm/b.m4a")
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)

        let summary = try MusicFolderImport.importFolder(folder.appendingPathComponent("Listed"), into: destination)
        XCTAssertEqual(summary.tracks, 1)
        XCTAssertEqual(files(under: destination), ["Mastered/Calm/a.m4a", "library.json"])
    }

    func testAFolderWithoutMusicChangesNothing() throws {
        try touch("Empty/notes.txt")
        try touch("app/Music/Calm/kept.mp3")
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        XCTAssertThrowsError(try MusicFolderImport.importFolder(folder.appendingPathComponent("Empty"), into: destination)) { error in
            XCTAssertEqual(error as? MusicFolderImport.ImportError, .noMusic("Empty"))
        }
        XCTAssertEqual(files(under: destination), ["Calm/kept.mp3"])
    }

    // MARK: - The whole host

    private func makeHost(defaults: UserDefaults) -> (LofiMusicHost, () -> FakeAudioBackend?) {
        let scheduler = DispatchScheduler(label: "test.player")
        let lock = NSLock()
        var backend: FakeAudioBackend?
        let environment = LofiMusicHost.Environment(
            settings: MusicSettings(defaults: defaults),
            musicFolder: folder.appendingPathComponent("app/Music", isDirectory: true),
            placeholderFolder: nil,
            booksFolder: folder.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: {
                let fake = FakeAudioBackend(clock: scheduler)
                lock.withLock { backend = fake }
                return fake
            },
            makePlayerScheduler: { scheduler },
            followerScheduler: DispatchScheduler(label: "test.follower"),
            makeLiveEngine: { _ in LexiconMoodEngine() }
        )
        return (LofiMusicHost(environment: environment), { lock.withLock { backend } })
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

    func testFollowsABookFromItsUnzippedEPUB() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-host-\(UUID().uuidString)"))
        try touch("Picked/Calm/a.mp3")
        try touch("Picked/Calm/b.mp3")
        try touch("Picked/Mysterious/c.mp3")
        try fileManager.createDirectory(at: folder.appendingPathComponent("books/extracted/book-1"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: Self.readerBook, to: folder.appendingPathComponent("books/extracted/book-1/readaloud"))

        let (host, backend) = makeHost(defaults: defaults)
        host.start()
        var status = try await waitFor(host) { !$0.library.preparing && $0.lastError != nil || $0.library.tracks > 0 }
        XCTAssertEqual(status.library.source, "none", "nothing imported and no stand-ins: no music yet")

        let summary = try await host.importMusic(from: folder.appendingPathComponent("Picked"))
        XCTAssertEqual(summary.tracks, 3)
        status = try await waitFor(host) { $0.library.tracks == 3 }
        XCTAssertEqual(status.library.source, "imported")
        XCTAssertEqual(status.library.importedFolderName, "Picked")
        XCTAssertEqual(status.library.moods.first { $0.mood == "calm" }?.tracks, 2)

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
        status = try await waitFor(host) { $0.book?.text == "ready" && $0.playback.readings > 0 && $0.playback.musicMood != nil }
        XCTAssertEqual(status.book?.engine, "lexicon/1")
        XCTAssertEqual(status.playback.sentence, 2)
        XCTAssertTrue(status.playback.narrating)
        XCTAssertNotNil(backend(), "the player was made once there was music")

        // The status crosses to JavaScript as plain JSON.
        let json = status.jsonObject()
        XCTAssertEqual(json["enabled"] as? Bool, true)
        XCTAssertEqual((json["library"] as? [String: Any])?["source"] as? String, "imported")

        await host.setEnabled(false)
        await host.setMusicLevel(dB: -20)
        status = await host.status()
        XCTAssertFalse(status.enabled)
        XCTAssertEqual(status.musicLevelDB, -20)
        XCTAssertEqual(MusicSettings(defaults: defaults).musicLevelDB, -20, "settings persist")

        await host.removeImportedMusic()
        status = try await waitFor(host) { $0.library.tracks == 0 }
        XCTAssertNil(status.library.importedFolderName)
    }

    func testAnAudiobookWithoutTextKeepsTheMusicOff() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-host-\(UUID().uuidString)"))
        try touch("app/Music/Calm/a.mp3")
        let (host, _) = makeHost(defaults: defaults)
        host.start()
        _ = try await waitFor(host) { $0.library.tracks == 1 }
        host.narratorLoadedBook(id: "audio-only", trackFile: folder.appendingPathComponent("books/audio-only/part1.m4b"))
        host.narratorPlayingChanged(true)
        let status = try await waitFor(host) { $0.book?.text == "unavailable" }
        XCTAssertNil(status.playback.musicMood)
        XCTAssertNotNil(status.book?.detail)
    }
}
