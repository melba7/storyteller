import XCTest
import LofiScoreCore
@testable import LofiAudio

final class CrossfaderTests: XCTestCase {
    func testCrossfaderReversesAtTheSameSpeed() {
        var fader = Crossfader()
        XCTAssertEqual(fader.targetDeck, .a)
        fader.move(toward: .b, fullDuration: 4, at: 0)
        XCTAssertEqual(fader.targetDeck, .b)
        XCTAssertEqual(fader.position(at: 2), 0.5, accuracy: 1e-12)
        fader.move(toward: .a, fullDuration: 4, at: 2)
        XCTAssertEqual(fader.targetDeck, .a)
        XCTAssertEqual(fader.endTime, 4, accuracy: 1e-12)
        XCTAssertEqual(fader.gain(of: .a, at: 2), sqrt(0.5), accuracy: 1e-12)
        XCTAssertEqual(fader.gain(of: .a, at: 4), 1, accuracy: 1e-12)
        fader.snap(to: .b, at: 5)
        XCTAssertEqual(fader.gain(of: .b, at: 5), 1)
        XCTAssertFalse(fader.isMoving(at: 5))
    }
}

final class BarGridTests: XCTestCase {
    func testDelayToNextBar() throws {
        let grid = try XCTUnwrap(BarGrid(bpm: 120))
        XCTAssertEqual(grid.barLength, 2)
        XCTAssertEqual(grid.delayToNextBar(from: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(grid.delayToNextBar(from: 4), 0, accuracy: 1e-9)
        XCTAssertEqual(grid.delayToNextBar(from: 4.000_000_1), 0, accuracy: 1e-6)
        XCTAssertEqual(grid.delayToNextBar(from: 4.1), 1.9, accuracy: 1e-9)
    }

    func testDownbeatOffset() throws {
        let grid = try XCTUnwrap(BarGrid(bpm: 120, beatsPerBar: 4, downbeat: 0.5))
        XCTAssertEqual(grid.delayToNextBar(from: 0.2), 0.3, accuracy: 1e-9)
        XCTAssertEqual(grid.barLine(atOrBefore: 5.9), 4.5, accuracy: 1e-9)
        XCTAssertEqual(grid.barLine(atOrBefore: 0.1), 0.5)
    }

    func testImplausibleTemposHaveNoGrid() {
        XCTAssertNil(BarGrid(bpm: nil))
        XCTAssertNil(BarGrid(bpm: 10))
        XCTAssertNil(BarGrid(bpm: 400))
        XCTAssertNil(BarGrid(bpm: .nan))
        XCTAssertNotNil(BarGrid(bpm: 72, beatsPerBar: 3))
    }
}

final class DuckerTests: XCTestCase {
    func testBedGainPutsTracksAtTheBedLevel() {
        let settings = DuckingSettings()
        // Voice −18 LUFS, bed 16 dB under it: a −16 LUFS track needs −18 dB.
        XCTAssertEqual(settings.bedGain(forTrackLoudness: -16), Gain.linear(fromDB: -18), accuracy: 1e-12)
        XCTAssertEqual(settings.bedGain(forTrackLoudness: -40), 1, "never boosts above unity")
    }

    func testLiftOnlyAfterTheSilenceIsLongEnough() {
        // Defaults: 2 s of silence, then a gentle 2 dB rise over 2.5 s.
        let settings = DuckingSettings()
        var ducker = Ducker()
        ducker.sentenceStarted(at: 0, duration: 2, settings: settings)
        XCTAssertEqual(ducker.gapCheckTime(settings: settings), 4)
        ducker.checkGap(at: 3.5, settings: settings)
        XCTAssertEqual(ducker.offsetDB(at: 3.5), 0)
        ducker.checkGap(at: 4, settings: settings)
        XCTAssertTrue(ducker.isLifted)
        XCTAssertEqual(ducker.offsetDB(at: 5.25), 1, accuracy: 1e-9)
        XCTAssertEqual(ducker.offsetDB(at: 6.5), 2, accuracy: 1e-9)
        XCTAssertNil(ducker.gapCheckTime(settings: settings), "already lifted")
        ducker.sentenceStarted(at: 7, duration: 1, settings: settings)
        XCTAssertEqual(ducker.offsetDB(at: 7.4), 0, accuracy: 1e-9)
    }

    func testNoLiftWhenTheSettingIsOff() {
        var settings = DuckingSettings()
        settings.gapLiftDB = 0
        var ducker = Ducker()
        ducker.sentenceStarted(at: 0, duration: 1, settings: settings)
        XCTAssertNil(ducker.gapCheckTime(settings: settings))
    }

    func testResetDropsTheLift() {
        let settings = DuckingSettings()
        var ducker = Ducker()
        ducker.sentenceEnded(at: 0)
        ducker.checkGap(at: 2, settings: settings)
        ducker.reset(at: 2.5)
        XCTAssertEqual(ducker.offsetDB(at: 2.5), 0)
        XCTAssertNil(ducker.voiceUntil)
    }
}

final class TrackRotationTests: XCTestCase {
    private func tracks(_ count: Int) -> [LibraryTrack] {
        (1...count).map { LibraryTrack(id: "t\($0)", file: "calm/t\($0).wav", bucket: .calm) }
    }

    func testAvoidsTheLastThree() {
        var rotation = TrackRotation(avoidLast: 3, seed: 42)
        let pool = tracks(5)
        var history: [String] = []
        for _ in 0..<50 {
            let pick = rotation.pick(from: pool, playing: history.last)!
            XCTAssertFalse(history.suffix(3).contains(pick.id))
            rotation.notePlayed(pick.id)
            history.append(pick.id)
        }
        XCTAssertEqual(Set(history.prefix(5)).count, 5, "every track plays before any repeats")
    }

    func testSmallBucketsRelaxTheRule() {
        var rotation = TrackRotation(avoidLast: 3, seed: 1)
        let two = tracks(2)
        var previous: String?
        for _ in 0..<10 {
            let pick = rotation.pick(from: two, playing: previous)!
            XCTAssertNotEqual(pick.id, previous)
            rotation.notePlayed(pick.id)
            previous = pick.id
        }
        let one = tracks(1)
        XCTAssertEqual(rotation.pick(from: one, playing: "t1")?.id, "t1", "a lone track repeats")
        XCTAssertNil(rotation.pick(from: []))
    }

    func testSameSeedSameChoices() {
        var first = TrackRotation(seed: 9)
        var second = TrackRotation(seed: 9)
        let pool = tracks(8)
        for _ in 0..<20 {
            let a = first.pick(from: pool)!
            let b = second.pick(from: pool)!
            XCTAssertEqual(a.id, b.id)
            first.notePlayed(a.id)
            second.notePlayed(b.id)
        }
    }
}

final class LibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    func testScanReadsMoodFoldersLeniently() throws {
        try touch("Calm/rain 80bpm.wav")
        try touch("sombre/grey morning.m4a")
        try touch("Cozy/notes.txt")
        try touch("Not a mood/loud.wav")
        try touch("Tense/.hidden.wav")
        let library = try MusicLibrary.load(from: folder)
        XCTAssertEqual(library.tracks.map(\.id), ["calm/rain 80bpm", "somber/grey morning"])
        XCTAssertEqual(library.tracks.first?.bpm, 80)
        XCTAssertEqual(library.tracks.first?.file, "Calm/rain 80bpm.wav")
        XCTAssertEqual(library.url(for: library.tracks[1]).lastPathComponent, "grey morning.m4a")
        XCTAssertEqual(Set(library.emptyBuckets), Set(MoodBucket.allCases).subtracting([.calm, .somber]))
    }

    func testManifestComesFirstAndUnlistedFilesAreAdded() throws {
        try touch("Calm/rain 80bpm.wav")
        try touch("Calm/c1.m4a")
        let json = """
        {
          "version": 1,
          "targetLoudness": -16,
          "tracks": [
            {"id": "m1", "file": "Melancholy/m1.m4a", "bucket": "Melancholic", "bpm": 72, "seed": 1234,
             "loudness": -15.5, "source": "suno", "license": "personal"},
            {"id": "c1", "file": "Calm/c1.m4a", "bucket": "calm", "seed": "abc"}
          ]
        }
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("library.json"))
        let library = try MusicLibrary.load(from: folder)
        // "Calm/c1.m4a" is listed, so only the unlisted file is added, after the manifest's tracks.
        XCTAssertEqual(library.tracks.map(\.id), ["m1", "c1", "calm/rain 80bpm"])
        XCTAssertEqual(library.loudness(of: library.tracks[2]), -16)
        XCTAssertEqual(library.tracks[2].bpm, 80)
        XCTAssertEqual(library.tracks[0].bucket, .melancholy)
        XCTAssertEqual(library.tracks[0].seed?.value, "1234")
        XCTAssertEqual(library.loudness(of: library.tracks[0]), -15.5)
        XCTAssertEqual(library.loudness(of: library.tracks[1]), -16)
        XCTAssertEqual(library.tracks[0].barGrid?.bpm, 72)
    }

    func testManifestRoundTrips() throws {
        let manifest = LibraryManifest(targetLoudness: -16, tracks: [
            LibraryTrack(id: "x", file: "Cozy/x.m4a", bucket: .cozy, bpm: 70, key: "F major", seed: "7"),
        ])
        let decoded = try JSONDecoder().decode(LibraryManifest.self, from: manifest.jsonData())
        XCTAssertEqual(decoded, manifest)
    }

    func testManifestCannotPointOutsideItsFolder() throws {
        let json = #"{"version": 1, "tracks": [{"id": "x", "file": "../../etc/passwd", "bucket": "calm"}]}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try MusicLibrary.load(from: folder)) { error in
            XCTAssertEqual(error as? MusicLibrary.LoadError, .unsafePath("../../etc/passwd"))
        }
    }

    func testUnknownBucketIsAnError() throws {
        let json = #"{"version": 1, "tracks": [{"id": "x", "file": "x.m4a", "bucket": "jazzy"}]}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try MusicLibrary.load(from: folder))
    }

    func testEmptyOrMissingFolders() throws {
        XCTAssertThrowsError(try MusicLibrary.load(from: folder)) { error in
            XCTAssertEqual(error as? MusicLibrary.LoadError, .noTracks(self.folder.path))
        }
        let missing = folder.appendingPathComponent("missing")
        XCTAssertThrowsError(try MusicLibrary.load(from: missing)) { error in
            XCTAssertEqual(error as? MusicLibrary.LoadError, .notAFolder(missing.path))
        }
    }

    func testTempoInFileNames() {
        XCTAssertEqual(MusicLibrary.tempo(inFileName: "rainy 72bpm.m4a"), 72)
        XCTAssertEqual(MusicLibrary.tempo(inFileName: "song_90_BPM.wav"), 90)
        XCTAssertEqual(MusicLibrary.tempo(inFileName: "slow-65-bpm.mp3"), 65)
        XCTAssertNil(MusicLibrary.tempo(inFileName: "nobpm.wav"))
        XCTAssertNil(MusicLibrary.tempo(inFileName: "fast 999bpm.wav"))
        XCTAssertNil(MusicLibrary.tempo(inFileName: "plain.wav"))
    }

    func testSafePaths() {
        XCTAssertTrue(MusicLibrary.isSafeRelativePath("Calm/a.m4a"))
        XCTAssertFalse(MusicLibrary.isSafeRelativePath("/etc/passwd"))
        XCTAssertFalse(MusicLibrary.isSafeRelativePath("../x.m4a"))
        XCTAssertFalse(MusicLibrary.isSafeRelativePath("Calm/../../x.m4a"))
        XCTAssertFalse(MusicLibrary.isSafeRelativePath("~/x.m4a"))
        XCTAssertFalse(MusicLibrary.isSafeRelativePath(""))
    }

    func testFallbackOrderStartsWithTheMoodItself() {
        let library = MusicLibrary(root: folder, tracks: [])
        for bucket in MoodBucket.allCases {
            let order = library.fallbackOrder(for: bucket)
            XCTAssertEqual(order.first, bucket)
            XCTAssertEqual(Set(order), Set(MoodBucket.allCases))
        }
        XCTAssertNotEqual(library.fallbackOrder(for: .tense)[1], .calm, "tense falls back to something dark, not calm")
    }
}
