import XCTest
import LofiScoreCore
@testable import LofiAudio

final class GainTests: XCTestCase {
    func testEqualPowerKeepsTheSummedPowerLevel() {
        for step in 0...100 {
            let gains = Gain.equalPower(Double(step) / 100)
            XCTAssertEqual(gains.a * gains.a + gains.b * gains.b, 1, accuracy: 1e-12)
        }
        XCTAssertEqual(Gain.equalPower(0).a, 1)
        XCTAssertEqual(Gain.equalPower(1).b, 1)
        XCTAssertEqual(Gain.equalPower(0.5).a, sqrt(0.5), accuracy: 1e-12)
        XCTAssertEqual(Gain.equalPower(-1).a, 1, "positions are clamped")
    }

    func testDecibelConversions() {
        XCTAssertEqual(Gain.linear(fromDB: -6), 0.501, accuracy: 1e-3)
        XCTAssertEqual(Gain.linear(fromDB: 0), 1)
        XCTAssertEqual(Gain.linear(fromDB: -200), 0)
        XCTAssertEqual(Gain.decibels(fromLinear: 0.5), -6.02, accuracy: 1e-2)
        XCTAssertEqual(Gain.decibels(fromLinear: 0), -.infinity)
    }

    func testRampsMoveSmoothlyAndCanBeRedirected() {
        var ramp = Ramp(value: 0)
        ramp.go(to: 1, over: 2, at: 10, shape: .linear)
        XCTAssertEqual(ramp.value(at: 9), 0)
        XCTAssertEqual(ramp.value(at: 11), 0.5, accuracy: 1e-12)
        XCTAssertTrue(ramp.isRunning(at: 11))
        ramp.go(to: 0, over: 1, at: 11, shape: .linear)
        XCTAssertEqual(ramp.value(at: 11), 0.5, accuracy: 1e-12, "a new target starts from the current value")
        XCTAssertEqual(ramp.value(at: 12), 0)
        XCTAssertFalse(ramp.isRunning(at: 12))

        var fade = Ramp(value: 0)
        fade.go(to: 1, over: 2, at: 0, shape: .equalPower)
        XCTAssertEqual(fade.value(at: 1), sin(.pi / 4), accuracy: 1e-12)
        fade.go(to: 0, over: 2, at: 2, shape: .equalPower)
        XCTAssertEqual(fade.value(at: 3), cos(.pi / 4), accuracy: 1e-12)
    }

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

final class SchedulerTests: XCTestCase {
    func testManualSchedulerRunsInTimeOrder() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        _ = scheduler.schedule(after: 2) { log.append("b") }
        _ = scheduler.schedule(after: 1) { log.append("a") }
        _ = scheduler.schedule(after: 2) { log.append("c") }
        let cancelled = scheduler.schedule(after: 1.5) { log.append("x") }
        cancelled.cancel()
        scheduler.advance(by: 3)
        XCTAssertEqual(log, ["a", "b", "c"])
        XCTAssertEqual(scheduler.now, 3)
    }

    func testRepeatingTimerCanCancelItself() {
        let scheduler = ManualScheduler()
        var count = 0
        var handle: LofiCancellable?
        handle = scheduler.scheduleRepeating(every: 0.5) {
            count += 1
            if count == 3 { handle?.cancel() }
        }
        scheduler.advance(by: 10)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testActionsScheduledFromActionsRunInTheSameAdvance() {
        let scheduler = ManualScheduler()
        var fired: [TimeInterval] = []
        _ = scheduler.schedule(after: 1) {
            fired.append(scheduler.now)
            _ = scheduler.schedule(after: 1) { fired.append(scheduler.now) }
        }
        scheduler.advance(by: 5)
        XCTAssertEqual(fired, [1, 2])
    }

    func testDispatchSchedulerRunsOnItsQueue() {
        let scheduler = DispatchScheduler(label: "test")
        let done = expectation(description: "ran")
        _ = scheduler.schedule(after: 0.01) {
            XCTAssertTrue(scheduler.isCurrent)
            var nested = false
            scheduler.perform { nested = true }
            XCTAssertTrue(nested, "perform runs inline when already on the queue")
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertFalse(scheduler.isCurrent)
    }
}
