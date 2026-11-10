import XCTest
import LofiDirector
import LofiScoreCore
@testable import LofiAudio

/// Book themes, the "Wrong mood" button and the track names for "now playing".
final class ThemeAndOverrideTests: XCTestCase {
    private func themed() -> PlayerHarness {
        var config = ScoreConfig.mechanics
        config.bookThemes = true
        return PlayerHarness(config: config)
    }

    private func overrideMood(_ h: PlayerHarness, to mood: MoodBucket? = nil) -> MoodOverride? {
        var result: MoodOverride?
        h.player.overrideMood(to: mood) { result = $0 }
        return result
    }

    // MARK: - Book themes

    func testThemeIsStableForABookAndDiffersBetweenBooks() {
        let tracks = (1...6).map { LibraryTrack(id: "calm-\($0)", file: "calm/calm-\($0).wav", bucket: .calm) }
        let first = BookThemes.theme(bookID: "book-a", bucket: .calm, candidates: tracks)
        XCTAssertEqual(first, BookThemes.theme(bookID: "book-a", bucket: .calm, candidates: tracks.reversed()))
        let themes = Set((0..<20).compactMap { BookThemes.theme(bookID: "book-\($0)", bucket: .calm, candidates: tracks)?.id })
        XCTAssertGreaterThan(themes.count, 2, "different books get different themes")
        // Removing a track that is not the theme leaves the theme alone.
        let others = tracks.filter { $0.id != first?.id }
        XCTAssertEqual(BookThemes.theme(bookID: "book-a", bucket: .calm, candidates: others.dropLast() + [first!])?.id, first?.id)
    }

    func testReturningToAMoodStartsItsThemeAgain() {
        let h = themed()
        h.startPlaying(in: .calm)
        let theme = h.startedFiles.first
        XCTAssertEqual(theme, BookThemes.theme(bookID: "book", bucket: .calm, candidates: h.library.tracks(in: .calm))?.id)

        h.seek(to: 100, finding: .tense)
        h.advance(10)
        let tenseTheme = h.startedFiles.last
        h.seek(to: 200, finding: .calm)
        h.advance(10)
        XCTAssertEqual(h.startedFiles.last, theme, "calm again: the same track as before")
        h.seek(to: 300, finding: .tense)
        h.advance(10)
        XCTAssertEqual(h.startedFiles.last, tenseTheme)
    }

    func testTracksAfterTheThemeStillRotate() {
        let h = themed()
        h.startPlaying(in: .calm)
        let theme = h.startedFiles.first
        h.advance(130)
        XCTAssertEqual(h.startedFiles.count, 2)
        XCTAssertNotEqual(h.startedFiles.last, theme, "the next calm track is another one")
    }

    func testThemesOffPicksByRotationOnly() {
        var config = ScoreConfig.mechanics
        config.bookThemes = false
        let off = PlayerHarness(config: config)
        off.startPlaying(in: .calm)
        let on = themed()
        on.startPlaying(in: .calm)
        let theme = BookThemes.theme(bookID: "book", bucket: .calm, candidates: on.library.tracks(in: .calm))?.id
        XCTAssertEqual(on.startedFiles.first, theme)
        XCTAssertEqual(off.startedFiles.count, 1)
    }

    // MARK: - Wrong mood

    func testWrongMoodMovesToTheNextGuessAndHoldsIt() {
        let h = PlayerHarness()
        h.startPlaying(in: .tense)
        h.advance(30)
        let result = overrideMood(h)
        XCTAssertEqual(result?.rejected, .tense)
        XCTAssertNotNil(result?.chosen)
        XCTAssertNotEqual(result?.chosen, .tense)
        XCTAssertEqual(result?.picked, false)
        XCTAssertEqual(result?.sentence, 0)
        XCTAssertEqual(result?.trackID?.hasPrefix("tense"), true)
        XCTAssertEqual(h.crossfades.last?.transition, .quick)
        XCTAssertEqual(h.decisions.last?.reason, .listener)

        // The engine keeps saying tense: the music stays where the listener put it.
        for _ in 0..<40 {
            h.advance(5)
            h.send(.tense)
        }
        XCTAssertEqual(h.snapshot().musicMood, result?.chosen)
    }

    func testPickingAMoodGoesStraightThere() {
        let h = PlayerHarness()
        h.startPlaying(in: .tense)
        h.advance(30)
        let result = overrideMood(h, to: .cozy)
        XCTAssertEqual(result?.chosen, .cozy)
        XCTAssertEqual(result?.picked, true)
        XCTAssertEqual(result?.correction, false)
        h.advance(10)
        XCTAssertEqual(h.snapshot().musicMood, .cozy)
        XCTAssertNil(overrideMood(h, to: .cozy), "nothing to change")
    }

    func testAPickRightAfterAGuessIsACorrection() {
        let h = PlayerHarness()
        h.startPlaying(in: .tense)
        h.advance(30)
        let guess = overrideMood(h)
        h.advance(10)
        let pick = overrideMood(h, to: guess?.chosen == .cozy ? .playful : .cozy)
        XCTAssertEqual(pick?.correction, true)
        XCTAssertEqual(pick?.rejected, guess?.chosen)
    }

    func testWrongMoodWithNoBookDoesNothing() {
        let h = PlayerHarness()
        XCTAssertNil(overrideMood(h))
    }

    // MARK: - Track names

    func testNamesComeFromSourcesThenTheFileName() {
        let csv = #"""
        id,mood,file,title,artist,license_name,attribution
        c1,Calm,"Calm/Sky Lake - Purrple Cat.mp3",Sky Lake,Purrple Cat,CC BY-SA 3.0,"""Sky Lake"" by Purrple Cat, licensed"
        """#
        let sources = TrackSources.parse(csv)
        XCTAssertEqual(sources?.entries["Calm/Sky Lake - Purrple Cat.mp3"]?.artist, "Purrple Cat")
        XCTAssertEqual(sources?.entries["Calm/Sky Lake - Purrple Cat.mp3"]?.licenseName, "CC BY-SA 3.0")

        let listed = LibraryTrack(id: "calm/sky", file: "Calm/Sky Lake - Purrple Cat.mp3", bucket: .calm)
        let filled = sources!.filling([listed])[0]
        XCTAssertEqual(filled.displayTitle, "Sky Lake")
        XCTAssertEqual(filled.displayArtist, "Purrple Cat")

        let bare = LibraryTrack(id: "dreamy/x", file: "Dreamy/Night Drive - Mr. Smith - Remix.m4a", bucket: .dreamy)
        XCTAssertEqual(bare.displayTitle, "Night Drive - Mr. Smith")
        XCTAssertEqual(bare.displayArtist, "Remix")
        let plain = LibraryTrack(id: "calm/1", file: "calm/calm-1.wav", bucket: .calm)
        XCTAssertEqual(plain.displayTitle, "calm-1")
        XCTAssertNil(plain.displayArtist)
    }

    func testLibraryLoadFillsNamesFromSourcesCSV() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Calm"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("Calm/a.mp3"))
        try "file,title,artist,license_name\nCalm/a.mp3,Quiet Night,Tokyo Music Walker,CC BY 3.0\n"
            .write(to: folder.appendingPathComponent("SOURCES.csv"), atomically: true, encoding: .utf8)
        let scanned = try MusicLibrary.load(from: folder)
        XCTAssertEqual(scanned.tracks.first?.title, "Quiet Night")

        let manifest = LibraryManifest(tracks: [LibraryTrack(id: "calm/a", file: "Calm/a.mp3", bucket: .calm)])
        try manifest.jsonData().write(to: folder.appendingPathComponent("library.json"))
        let listed = try MusicLibrary.load(from: folder)
        XCTAssertEqual(listed.track(id: "calm/a")?.artist, "Tokyo Music Walker")
        XCTAssertEqual(listed.track(id: "calm/a")?.licenseName, "CC BY 3.0")
    }
}
