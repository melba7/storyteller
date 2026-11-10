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

    func testLooksThroughAnyNumberOfTracksAndRemembersTheMatch() throws {
        let guardian = try Books.text().spoilerGuard
        let tracks = folder.appendingPathComponent("MoodTracks", isDirectory: true)
        // The match is the oldest file, behind hundreds of other books' tracks.
        try track(for: guardian, bookID: "The Match").save(to: tracks.appendingPathComponent("aaa-match.json"))
        for index in 0..<240 {
            try track(for: guardian, bookID: "other \(index)", tamper: true).save(to: tracks.appendingPathComponent("other-\(index).score.json"))
        }
        let old = Date().addingTimeInterval(-3600)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: tracks.appendingPathComponent("aaa-match.json").path)

        XCTAssertEqual(MoodTrackFinder.find(bookID: "abc", in: [tracks], spoilerGuard: guardian)?.bookID, "The Match")
        let memory = try XCTUnwrap(TrackMatchMemory.load(from: tracks))
        XCTAssertEqual(memory["mood:abc"]?.file, "0/aaa-match.json")

        // A book with no track: remembered too, until the folder changes.
        let otherBook = try SpoilerGuard(chapters: [["Nothing here matches.", "Nor this."]])
        XCTAssertNil(MoodTrackFinder.find(bookID: "xyz", in: [tracks], spoilerGuard: otherBook))
        let none = try XCTUnwrap(TrackMatchMemory.load(from: tracks)?["xyz"] ?? TrackMatchMemory.load(from: tracks)?["mood:xyz"])
        XCTAssertNil(none.file)
        XCTAssertEqual(none.signature, memory["mood:abc"]?.signature)
        XCTAssertFalse(files(under: tracks).contains("MoodTracks/.matches.json"), "the memory is a dot file the import never copies")
    }

    func testTheMatchMemorySkipsDecodingUntilTheFolderChanges() throws {
        let tracks = folder.appendingPathComponent("MoodTracks", isDirectory: true)
        try touch("MoodTracks/a.json", contents: Data("a".utf8))
        try touch("MoodTracks/b.json", contents: Data("b".utf8))
        // b is newer, so it is looked at first.
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: tracks.appendingPathComponent("a.json").path)
        var decoded: [String] = []
        func lookUp(_ book: String, match: String?) -> String? {
            TrackMatchMemory.lookUp(
                key: "t:" + book, bookID: book, folders: [tracks],
                isCandidate: { $0.pathExtension == "json" },
                bookName: { $0.deletingPathExtension().lastPathComponent },
                decode: { url -> String? in
                    decoded.append(url.lastPathComponent)
                    return url.lastPathComponent
                },
                matches: { $0 == match }
            )?.track
        }
        XCTAssertEqual(lookUp("x", match: "a.json"), "a.json")
        XCTAssertEqual(decoded, ["b.json", "a.json"], "newest first")
        decoded = []
        XCTAssertEqual(lookUp("x", match: "a.json"), "a.json")
        XCTAssertEqual(decoded, ["a.json"], "the remembered file is checked, nothing else")

        decoded = []
        XCTAssertNil(lookUp("y", match: nil))
        XCTAssertEqual(decoded.count, 2)
        decoded = []
        XCTAssertNil(lookUp("y", match: nil))
        XCTAssertEqual(decoded, [], "nothing matched last time and the folder is the same")

        // A new file: the book is looked for again, and only the new file is new.
        try touch("MoodTracks/c.json", contents: Data("c".utf8))
        decoded = []
        XCTAssertEqual(lookUp("y", match: "c.json"), "c.json")
        XCTAssertTrue(decoded.contains("c.json"))
        // The remembered file no longer matching (the book was re-synced) is not trusted.
        decoded = []
        XCTAssertNil(lookUp("x", match: nil))
        XCTAssertEqual(decoded.first, "a.json")
        XCTAssertEqual(decoded.count, 3)
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
        // A fine-tuned transformer: its settings and its compiled model.
        try touch("Picked Music/LofiMood-lm-minilm-soft.json")
        try touch("Picked Music/LofiMood-lm-minilm-soft.mlmodelc/model.mil")
        // The atmosphere's sounds and tracks.
        try touch("Picked Music/Atmosphere/Rain/rain-1.m4a")
        try touch("Picked Music/Atmosphere/Rain/.rain-2.m4a.icloud")
        try touch("Picked Music/Atmosphere/Rain/notes.txt")
        try touch("Picked Music/Atmosphere/Bagpipes/drone.wav")
        try touch("Picked Music/Atmosphere/OldTown.ChurchBells/bells-fs1.m4a")
        try touch("Picked Music/Atmosphere/Bagpipes.Drone/drone.wav")
        try touch("Picked Music/Atmosphere/variants.json")
        try touch("Picked Music/Atmosphere/OneShots/DoorKnock/knock-fs2.m4a")
        try touch("Picked Music/Atmosphere/OneShots/Gunshot/bang.wav")
        try touch("Picked Music/Atmosphere/OneShots/sounds.json")
        try touch("Picked Music/Atmosphere/sounds.json")
        try touch("Picked Music/Atmosphere/SOURCES.csv")
        try touch("Picked Music/tracks/The Green Lantern.atmosphere.json")

        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("app/Music/Old/old.mp3")

        let summary = try MusicFolderImport.importFolder(source, into: destination)
        XCTAssertEqual(summary, .init(
            folderName: "Picked Music", tracks: 3, moodTracks: 3, hasClassifier: true, notDownloaded: 2,
            atmosphereRecordings: 3, atmosphereTracks: 1
        ))
        XCTAssertEqual(files(under: destination), [
            ".imported.json",
            "Atmosphere/OldTown.ChurchBells/bells-fs1.m4a",
            "Atmosphere/OneShots/DoorKnock/knock-fs2.m4a",
            "Atmosphere/OneShots/sounds.json",
            "Atmosphere/Rain/rain-1.m4a",
            "Atmosphere/SOURCES.csv",
            "Atmosphere/sounds.json",
            "Atmosphere/variants.json",
            "AtmosphereTracks/The Green Lantern.atmosphere.json",
            "Calm/rain 70bpm.mp3",
            "Cozy/fire.m4a",
            "Credits.md",
            "LofiMood-embed-word+contextual-3.json",
            "LofiMood-embed-word-3.json",
            "LofiMood-lm-minilm-soft.json",
            "LofiMood-lm-minilm-soft.mlmodelc/model.mil",
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
            "LofiMood-lm-minilm-soft.json",
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
        XCTAssertEqual(files(under: destination), [".imported.json", "Mastered/Calm/a.m4a", "library.json"])
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

    func testSyncCopiesOnlyWhatIsNewAndNeverDeletes() throws {
        let source = folder.appendingPathComponent("Linked", isDirectory: true)
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("Linked/Calm/a.mp3")
        try touch("Linked/Cozy/b.mp3")
        try touch("Linked/tracks/Book One.score.json")
        try touch("Linked/Atmosphere/Rain/rain.m4a")
        try touch("Linked/notes.txt")

        // Nothing imported yet: a plain import, remembered file by file.
        var summary = try MusicFolderImport.sync(source, into: destination)
        XCTAssertTrue(summary.fresh)
        XCTAssertEqual(summary.added, 4)
        XCTAssertEqual(summary.music, 2)
        XCTAssertEqual(summary.moodTracks, 1)
        XCTAssertEqual(summary.atmosphereRecordings, 1)
        XCTAssertEqual(summary.description, "Imported 1 book score, 2 tracks, 1 sound")
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Rain/rain.m4a", "Calm/a.mp3", "Cozy/b.mp3", "MoodTracks/Book One.score.json",
        ])

        // The same folder again: nothing to do.
        summary = try MusicFolderImport.sync(source, into: destination)
        XCTAssertFalse(summary.changed)
        XCTAssertEqual(summary.description, "Nothing new")

        // A new score and a changed track: only those are copied, and a track the phone
        // keeps but the folder no longer has stays.
        try touch("Linked/tracks/Book Two.score.json", contents: Data("two".utf8))
        try touch("Linked/Calm/a.mp3", contents: Data("longer".utf8))
        try fileManager.removeItem(at: source.appendingPathComponent("Cozy/b.mp3"))
        summary = try MusicFolderImport.sync(source, into: destination)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.moodTracks, 1)
        XCTAssertEqual(summary.music, 1)
        XCTAssertEqual(summary.description, "New: 1 book score, 1 track")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Calm/a.mp3")), Data("longer".utf8))
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Rain/rain.m4a", "Calm/a.mp3", "Cozy/b.mp3",
            "MoodTracks/Book One.score.json", "MoodTracks/Book Two.score.json",
        ])
        XCTAssertFalse(files(under: destination).contains { $0.hasSuffix(".part") })

        // A file still in iCloud is counted and asked for, not copied.
        try touch("Linked/Tense/.storm.wav.icloud")
        summary = try MusicFolderImport.sync(source, into: destination)
        XCTAssertEqual(summary.notDownloaded, 1)
        XCTAssertEqual(summary.description, "Nothing new yet; 1 files are still downloading from iCloud")
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

    func testALinkedFolderBringsAScoreToTheOpenBook() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-host-\(UUID().uuidString)"))
        try touch("Linked/Calm/a.mp3")
        try touch("Linked/Tense/b.mp3")
        try fileManager.createDirectory(at: folder.appendingPathComponent("books/extracted/book-1"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: Self.readerBook, to: folder.appendingPathComponent("books/extracted/book-1/readaloud"))

        let (host, _) = makeHost(defaults: defaults)
        host.start()
        let summary = try await host.linkMusicFolder(folder.appendingPathComponent("Linked"))
        XCTAssertEqual(summary.tracks, 2)
        var status = try await waitFor(host) { $0.library.tracks == 2 }
        XCTAssertEqual(status.library.linkedFolder?.name, "Linked")
        XCTAssertNotNil(status.library.linkedFolder?.lastSync)

        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        host.narratorPlayingChanged(true)
        status = try await waitFor(host) { $0.book?.text == "ready" }
        XCTAssertEqual(status.book?.moodTrack, false)

        // The Mac scores the book into the linked folder; the next look picks it up and the
        // open book gets its score without closing.
        let guardian = try SpoilerGuard(epubDirectory: folder.appendingPathComponent("books/extracted/book-1/readaloud"))
        try touch("Linked/tracks/Reader.score.json", contents: score(track(for: guardian, bookID: "Reader")))
        let synced = try await host.syncMusicFolder(reason: .manual)
        XCTAssertEqual(synced?.moodTracks, 1)
        status = try await waitFor(host) { $0.book?.moodTrack == true }
        XCTAssertEqual(status.book?.text, "ready")
        XCTAssertEqual(status.library.linkedFolder?.lastResult, "New: 1 book score")
        XCTAssertEqual(status.library.tracks, 2, "the music was not reloaded for a score")

        // Unlinking keeps the music.
        await host.unlinkMusicFolder()
        status = await host.status()
        XCTAssertNil(status.library.linkedFolder)
        XCTAssertEqual(status.library.tracks, 2)
        let unlinked = try await host.syncMusicFolder(reason: .manual)
        XCTAssertNil(unlinked)

        // A linked folder that went away is reported, not fatal.
        _ = try await host.linkMusicFolder(folder.appendingPathComponent("Linked"))
        try fileManager.removeItem(at: folder.appendingPathComponent("Linked"))
        do {
            _ = try await host.syncMusicFolder(reason: .manual)
            XCTFail("a missing folder should throw")
        } catch {}
        status = await host.status()
        XCTAssertTrue(status.library.linkedFolder?.lastResult?.hasPrefix("Could not read the folder") == true)
    }

    func testAScoreFromTheServerIsKeptInTheBook() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-host-\(UUID().uuidString)"))
        try touch("Picked/Calm/a.mp3")
        let bookFolder = folder.appendingPathComponent("books/extracted/book-1/readaloud")
        try fileManager.createDirectory(at: folder.appendingPathComponent("books/extracted/book-1"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: Self.readerBook, to: bookFolder)

        let (host, _) = makeHost(defaults: defaults)
        host.start()
        _ = try await host.importMusic(from: folder.appendingPathComponent("Picked"))
        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        host.narratorPlayingChanged(true)
        var status = try await waitFor(host) { $0.book?.text == "ready" }
        XCTAssertEqual(status.book?.moodTrack, false)

        // Not a score: refused, nothing written.
        do {
            try await host.installScore(Data("{\"format\":1}".utf8), forBook: "book-1")
            XCTFail("an empty score should be refused")
        } catch {}
        XCTAssertFalse(fileManager.fileExists(atPath: bookFolder.appendingPathComponent(BookScore.pathInBook).path))

        // A book that is not on the device.
        let guardian = try SpoilerGuard(epubDirectory: bookFolder)
        let data = try score(track(for: guardian, bookID: "book-1"))
        do {
            try await host.installScore(data, forBook: "book-9")
            XCTFail("a book without text should be refused")
        } catch {}

        // The open book: the score lands inside it and the book follows it without closing.
        try await host.installScore(data, forBook: "book-1")
        XCTAssertTrue(fileManager.fileExists(atPath: bookFolder.appendingPathComponent(BookScore.pathInBook).path))
        status = try await waitFor(host) { $0.book?.moodTrack == true }
        XCTAssertEqual(status.book?.text, "ready")

        // Opened again later, the book brings its own score.
        host.narratorLoadedBook(id: "book-2", trackFile: nil)
        status = try await waitFor(host) { $0.book?.id == "book-2" && $0.book?.text != "loading" }
        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        status = try await waitFor(host) { $0.book?.text == "ready" && $0.book?.moodTrack == true }
        XCTAssertEqual(status.book?.moodTrack, true)
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
