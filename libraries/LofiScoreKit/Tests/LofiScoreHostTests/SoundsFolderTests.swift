import Foundation
import LofiText
import XCTest
@testable import LofiScoreHost

/// Finding a book's text, and importing and syncing the sounds folder.
final class SoundsFolderTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        folder = fileManager.temporaryDirectory.appendingPathComponent("lofi-sounds-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: folder)
    }

    private func touch(_ path: String, contents: Data = Data([0])) throws {
        let url = folder.appendingPathComponent(path)
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

    // MARK: - Remembering which file is a book's

    func testTheMatchMemorySkipsDecodingUntilTheFolderChanges() throws {
        let tracks = folder.appendingPathComponent("Scores", isDirectory: true)
        try touch("Scores/a.json", contents: Data("a".utf8))
        try touch("Scores/b.json", contents: Data("b".utf8))
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
        try touch("Scores/c.json", contents: Data("c".utf8))
        decoded = []
        XCTAssertEqual(lookUp("y", match: "c.json"), "c.json")
        XCTAssertTrue(decoded.contains("c.json"))
        // The remembered file no longer matching (the book was re-synced) is not trusted.
        decoded = []
        XCTAssertNil(lookUp("x", match: nil))
        XCTAssertEqual(decoded.first, "a.json")
        XCTAssertEqual(decoded.count, 3)
        XCTAssertTrue(fileManager.fileExists(atPath: tracks.appendingPathComponent(".matches.json").path), "the memory is a dot file the import never copies")
    }

    // MARK: - Importing sounds

    func testImportsOnlyTheSoundsAndTheScores() throws {
        let source = folder.appendingPathComponent("Picked Sounds", isDirectory: true)
        // The music the shelved player used, still in Mo's folder: left behind.
        try touch("Picked Sounds/Calm/rain 70bpm.mp3")
        try touch("Picked Sounds/Cozy/fire.m4a")
        try touch("Picked Sounds/library.json")
        try touch("Picked Sounds/SOURCES.csv")
        try touch("Picked Sounds/CREDITS.md")
        try touch("Picked Sounds/LofiMood-embed-word-3.json")
        try touch("Picked Sounds/Mood.mlmodelc/model.mil")
        try touch("Picked Sounds/MoodTracks/some-book.json")
        try touch("Picked Sounds/tracks/The Green Lantern.track.json")
        try touch("Picked Sounds/notes.txt")
        try touch("Picked Sounds/.DS_Store")
        // Book scores and atmosphere tracks, wherever they sit.
        try touch("Picked Sounds/tracks/The Green Lantern.score.json")
        try touch("Picked Sounds/MoodTracks/Old Book.score.json")
        try touch("Picked Sounds/tracks/The Green Lantern.atmosphere.json")
        // An unpacked read-aloud book next to its track: its narration is not a sound.
        try touch("Picked Sounds/tracks/books/The Green Lantern/OEBPS/Audio/00001.mp3")
        // The atmosphere's sounds.
        try touch("Picked Sounds/Atmosphere/Rain/rain-1.m4a")
        try touch("Picked Sounds/Atmosphere/Rain/.rain-2.m4a.icloud")
        try touch("Picked Sounds/Atmosphere/Rain/notes.txt")
        try touch("Picked Sounds/Atmosphere/Bagpipes/drone.wav")
        try touch("Picked Sounds/Atmosphere/OldTown.ChurchBells/bells-fs1.m4a")
        try touch("Picked Sounds/Atmosphere/Bagpipes.Drone/drone.wav")
        try touch("Picked Sounds/Atmosphere/variants.json")
        try touch("Picked Sounds/Atmosphere/OneShots/DoorKnock/knock-fs2.m4a")
        try touch("Picked Sounds/Atmosphere/OneShots/Gunshot/bang.wav")
        try touch("Picked Sounds/Atmosphere/OneShots/sounds.json")
        try touch("Picked Sounds/Atmosphere/sounds.json")
        try touch("Picked Sounds/Atmosphere/SOURCES.csv")
        try touch("Picked Sounds/Atmosphere/Credits.md", contents: Data("# Sound credits\n".utf8))

        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("app/Music/Old/old.mp3")

        let summary = try SoundsFolderImport.importFolder(source, into: destination)
        XCTAssertEqual(summary, .init(folderName: "Picked Sounds", recordings: 3, scores: 2, atmosphereTracks: 1, notDownloaded: 1))
        XCTAssertEqual(files(under: destination), [
            ".imported.json",
            "Atmosphere/Credits.md",
            "Atmosphere/OldTown.ChurchBells/bells-fs1.m4a",
            "Atmosphere/OneShots/DoorKnock/knock-fs2.m4a",
            "Atmosphere/OneShots/sounds.json",
            "Atmosphere/Rain/rain-1.m4a",
            "Atmosphere/SOURCES.csv",
            "Atmosphere/sounds.json",
            "Atmosphere/variants.json",
            "AtmosphereTracks/The Green Lantern.atmosphere.json",
            "Scores/Old Book.score.json",
            "Scores/The Green Lantern.score.json",
        ])
        XCTAssertEqual(SoundsFolderImport.creditsFile(in: destination.appendingPathComponent("Atmosphere"))?.lastPathComponent, "Credits.md")
        XCTAssertTrue(SoundsFolderImport.isImported(destination))
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path + ".incoming"))
    }

    func testAFolderWithoutSoundsChangesNothing() throws {
        try touch("Empty/notes.txt")
        try touch("Empty/Calm/music.mp3")
        try touch("app/Music/Atmosphere/Rain/kept.mp3")
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        XCTAssertThrowsError(try SoundsFolderImport.importFolder(folder.appendingPathComponent("Empty"), into: destination)) { error in
            XCTAssertEqual(error as? SoundsFolderImport.ImportError, .noSounds("Empty"))
        }
        XCTAssertEqual(files(under: destination), ["Atmosphere/Rain/kept.mp3"])
    }

    func testSyncCopiesOnlyWhatIsNewAndNeverDeletes() throws {
        let source = folder.appendingPathComponent("Linked", isDirectory: true)
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("Linked/Atmosphere/Rain/rain.m4a")
        try touch("Linked/Atmosphere/Crowd/crowd.m4a")
        try touch("Linked/tracks/Book One.score.json")
        try touch("Linked/Calm/a.mp3")
        try touch("Linked/notes.txt")

        // Nothing imported yet: a plain import, remembered file by file.
        var summary = try SoundsFolderImport.sync(source, into: destination)
        XCTAssertTrue(summary.fresh)
        XCTAssertEqual(summary.added, 3)
        XCTAssertEqual(summary.recordings, 2)
        XCTAssertEqual(summary.scores, 1)
        XCTAssertEqual(summary.description, "Imported 1 book score, 2 sounds")
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Crowd/crowd.m4a", "Atmosphere/Rain/rain.m4a", "Scores/Book One.score.json",
        ])

        // The same folder again: nothing to do.
        summary = try SoundsFolderImport.sync(source, into: destination)
        XCTAssertFalse(summary.changed)
        XCTAssertEqual(summary.description, "Nothing new")

        // A new score and a changed sound: only those are copied, and a sound the phone
        // keeps but the folder no longer has stays.
        try touch("Linked/tracks/Book Two.score.json", contents: Data("two".utf8))
        try touch("Linked/Atmosphere/Rain/rain.m4a", contents: Data("longer".utf8))
        try fileManager.removeItem(at: source.appendingPathComponent("Atmosphere/Crowd/crowd.m4a"))
        summary = try SoundsFolderImport.sync(source, into: destination)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.scores, 1)
        XCTAssertEqual(summary.recordings, 1)
        XCTAssertEqual(summary.description, "New: 1 book score, 1 sound")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Atmosphere/Rain/rain.m4a")), Data("longer".utf8))
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Crowd/crowd.m4a", "Atmosphere/Rain/rain.m4a",
            "Scores/Book One.score.json", "Scores/Book Two.score.json",
        ])
        XCTAssertFalse(files(under: destination).contains { $0.hasSuffix(".part") })

        // A file still in iCloud is counted and asked for, not copied.
        try touch("Linked/Atmosphere/Wind/.storm.wav.icloud")
        summary = try SoundsFolderImport.sync(source, into: destination)
        XCTAssertEqual(summary.notDownloaded, 1)
        XCTAssertEqual(summary.description, "Nothing new yet; 1 file is still downloading from iCloud")
    }

    func testAFirstImportBringsScoresFirstCountsItsFilesAndCarriesOnAfterBeingCutShort() throws {
        let source = folder.appendingPathComponent("Linked", isDirectory: true)
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("app/Music/Atmosphere/Crowd/old-stand-in.wav")
        try touch("Linked/Atmosphere/Rain/rain.m4a")
        try touch("Linked/Atmosphere/Crowd/crowd.m4a")
        try touch("Linked/Atmosphere/sounds.json", contents: Data("{}".utf8))
        try touch("Linked/tracks/Book One.score.json")
        try touch("Linked/tracks/Book One.atmosphere.json")

        // Cut short after the third file: what was copied stays and is remembered.
        struct Stop: Error {}
        var seen: [SoundsFolderImport.Progress] = []
        var order: [[String]] = []
        XCTAssertThrowsError(try SoundsFolderImport.sync(source, into: destination) { progress in
            seen.append(progress)
            order.append(self.files(under: destination))
            if progress.copied == 3 { try? self.fileManager.removeItem(at: source.appendingPathComponent("Atmosphere/Rain/rain.m4a")) }
        })
        XCTAssertEqual(seen.first, .init(copied: 0, total: 5, scoresReady: false))
        XCTAssertEqual(seen.map(\.copied), [0, 1, 2, 3])
        XCTAssertEqual(seen.map(\.scoresReady), [false, false, true, true], "the track and the score go first")
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Crowd/crowd.m4a", "AtmosphereTracks/Book One.atmosphere.json", "Scores/Book One.score.json",
        ], "what sat there before a first import is replaced; the list of sounds is not in yet")

        // The next look copies only the rest, the list of sounds last, and clears nothing.
        try touch("Linked/Atmosphere/Rain/rain.m4a")
        seen = []
        let summary = try SoundsFolderImport.sync(source, into: destination) { seen.append($0) }
        XCTAssertFalse(summary.fresh)
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.recordings, 1)
        XCTAssertEqual(seen.last, .init(copied: 2, total: 2, scoresReady: true))
        XCTAssertEqual(files(under: destination), [
            ".imported.json", "Atmosphere/Crowd/crowd.m4a", "Atmosphere/Rain/rain.m4a", "Atmosphere/sounds.json",
            "AtmosphereTracks/Book One.atmosphere.json", "Scores/Book One.score.json",
        ])
    }

    func testTidiesWhatTheMusicLeftBehind() throws {
        let destination = folder.appendingPathComponent("app/Music", isDirectory: true)
        try touch("app/Music/Calm/a.mp3")
        try touch("app/Music/Tense/b.mp3")
        try touch("app/Music/library.json")
        try touch("app/Music/SOURCES.csv")
        try touch("app/Music/Credits.md")
        try touch("app/Music/LofiMood-embed-word-3.json")
        try touch("app/Music/LofiMood-lm-minilm.mlmodelc/model.mil")
        try touch("app/Music/Old.mlmodel")
        try touch("app/Music/MoodTracks/book.track.json")
        try touch("app/Music/MoodTracks/.matches.json")
        try touch("app/Music/MoodTracks/Book One.score.json", contents: Data("one".utf8))
        try touch("app/Music/Scores/Book Two.score.json")
        try touch("app/Music/Atmosphere/Rain/rain.m4a")
        try touch("app/Music/Atmosphere/CREDITS.md")
        try touch("app/Music/AtmosphereTracks/Book One.atmosphere.json")
        try touch("app/Music/.imported.json")

        XCTAssertEqual(SoundsFolderImport.tidyMusicLeftovers(in: destination), 10)
        XCTAssertEqual(files(under: destination), [
            ".imported.json",
            "Atmosphere/CREDITS.md",
            "Atmosphere/Rain/rain.m4a",
            "AtmosphereTracks/Book One.atmosphere.json",
            "Scores/Book One.score.json",
            "Scores/Book Two.score.json",
        ])
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Scores/Book One.score.json")), Data("one".utf8))
        XCTAssertEqual(SoundsFolderImport.tidyMusicLeftovers(in: destination), 0, "nothing left to do")
        XCTAssertEqual(SoundsFolderImport.tidyMusicLeftovers(in: folder.appendingPathComponent("missing")), 0)
    }
}
