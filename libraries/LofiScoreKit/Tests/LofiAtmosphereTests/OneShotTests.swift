import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiAudio
import LofiPlaceholders
import LofiText

/// One-off sounds: a knock or a clap of thunder on the sentence that says it happens.
final class OneShotTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("one-shots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Names and quotes

    func testNamesAndWhereAQuoteFalls() throws {
        XCTAssertEqual(OneShotSound(lenient: "Door Knock"), .doorKnock)
        XCTAssertEqual(OneShotSound(lenient: "door_knock"), .doorKnock)
        XCTAssertEqual(OneShotSound.thunderClap.folderName, "ThunderClap")
        XCTAssertNil(OneShotSound(lenient: "gunshot"))

        let guardian = try SpoilerGuard(chapters: [[
            "The fire had burned low.",
            "Then, out of nowhere, there came a knock at the door.",
            "Nobody moved.",
        ]])
        let window = try guardian.window(at: XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 2)))
        let spot = try XCTUnwrap(OneShotMention(sound: .doorKnock, quote: "There came a KNOCK at the door").locate(in: window))
        XCTAssertEqual(spot.line, 1)
        XCTAssertEqual(spot.wordsBefore, 10, "the sound falls on the quote's last word")
        XCTAssertEqual(spot.words, 11)
        XCTAssertNil(OneShotMention(sound: .doorKnock, quote: "a knock at the window").locate(in: window))
        XCTAssertNil(OneShotMention(sound: .doorKnock, quote: "  ").locate(in: window))

        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 1))
        let cue = AtmosphereTrack.Cue(position: position, sentence: "x", sound: .doorKnock, wordsBefore: spot.wordsBefore, words: spot.words)
        XCTAssertEqual(cue.fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(AtmosphereTrack.Cue(position: position, sentence: "x", sound: .doorKnock, wordsBefore: 0, words: 1).fraction, 0)
    }

    func testAnswersMayNameAOneOffSound() throws {
        let memory = PlaceMemory(entries: [])
        func answer(_ oneShot: String) throws -> SceneAnswer {
            try ClaudeSceneEngine.answer(fromJSON: """
                {"place":"new","placeName":"the kitchen","setting":"indoors","sounds":[],"newSounds":[],"moment":"none",
                 "oneShot":\(oneShot),"world":"","cue":"","confidence":0.8}
                """, memory: memory)
        }
        XCTAssertEqual(try answer(#"{"sound":"doorKnock","quote":" a knock at the door "}"#).oneShot,
                       OneShotMention(sound: .doorKnock, quote: "a knock at the door"))
        XCTAssertNil(try answer(#"{"sound":"none","quote":""}"#).oneShot)
        XCTAssertNil(try answer(#"{"sound":"doorKnock","quote":""}"#).oneShot, "without its words it cannot be placed")
        XCTAssertNil(try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"none","placeName":"","setting":"unclear","sounds":[],"world":"","cue":"","confidence":0.2}
            """, memory: memory).oneShot, "answers in the old shape still read")

        let system = ClaudeScenePrompt.system
        XCTAssertTrue(system.contains("- doorKnock: knocking at a door"))
        let properties = try XCTUnwrap(ClaudeScenePrompt.schema["properties"] as? [String: Any])
        let oneShot = try XCTUnwrap(properties["oneShot"] as? [String: Any])
        let sound = try XCTUnwrap((oneShot["properties"] as? [String: Any])?["sound"] as? [String: Any])
        XCTAssertEqual((sound["enum"] as? [String])?.first, "none")
        XCTAssertTrue((ClaudeScenePrompt.schema["required"] as? [String])?.contains("oneShot") == true)
    }

    // MARK: - Tracks

    func testTracksKeepOneCuePerSentenceAndOldTracksStillRead() throws {
        let guardian = try SpoilerGuard(chapters: [(0..<10).map { "Sentence \($0)." }])
        func position(_ index: Int) throws -> SentencePosition {
            try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
        }
        var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10)
        track.insertCue(.init(position: try position(7), sentence: "Sentence 7.", sound: .owlHoot, wordsBefore: 1, words: 2))
        track.insertCue(.init(position: try position(3), sentence: "Sentence 3.", sound: .doorKnock, wordsBefore: 0, words: 2))
        track.insertCue(.init(position: try position(3), sentence: "Sentence 3.", sound: .doorSlam, wordsBefore: 1, words: 2))
        XCTAssertEqual(track.cues.map(\.globalIndex), [3, 7])
        XCTAssertEqual(track.cue(at: 3)?.sound, .doorSlam, "a sentence keeps its newest cue")
        XCTAssertNil(track.cue(at: 4))

        let decoded = try AtmosphereTrack.decode(track.encoded())
        XCTAssertEqual(decoded.cues, track.cues)

        let old = Data(#"{"format":1,"engineID":"x","bookID":"b","wordsBetweenEntries":250,"chapterStarts":[0],"entries":[]}"#.utf8)
        XCTAssertEqual(try AtmosphereTrack.decode(old).cues, [])
    }

    // MARK: - Builder

    /// Hears a knock when the passage has "[knock]", quoting that sentence. With "[later]"
    /// it hears one only from a sentence after the knock's ("It was a knock."), the way an
    /// answer can lean on what follows.
    final class KnockEngine: SceneEngine, @unchecked Sendable {
        let id = "knock/1"
        private let lock = NSLock()
        private(set) var calls: [Int] = []

        func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
            lock.withLock { calls.append(window.position.globalIndex) }
            let text = window.lines.map(\.text).joined(separator: " ")
            var mention: OneShotMention?
            if text.contains("[knock]") {
                mention = OneShotMention(sound: .doorKnock, quote: "a knock at the door")
            } else if text.contains("It was a knock.") {
                mention = OneShotMention(sound: .doorKnock, quote: "something sounded at the door")
            }
            let scene = StoryScene(placeID: nil, placeName: "the kitchen", setting: .indoors, layers: [SceneLayer(.fireplace)], confidence: 0.9)
            let place: SceneAnswer.Place = memory.place(named: "the kitchen").map { .known($0.id) } ?? .new("the kitchen")
            return SceneAnswer(place: place, scene: scene, world: nil, oneShot: mention)
        }
    }

    private func book() -> [String] {
        var sentences = (0..<130).map { "Plain sentence number \($0) with a few more words in it." }
        sentences[10] = "Then there was a knock at the door. [knock]"
        // Far enough on that no window reaching it still has the first knock.
        sentences[100] = "Something sounded at the door."
        sentences[101] = "It was a knock."
        return sentences
    }

    func testACueOnThePassagesLastSentenceIsKeptAsItIs() async throws {
        let guardian = try SpoilerGuard(chapters: [book()])
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "knock/1", bookID: "book", wordsBetweenEntries: 60))
        let engine = KnockEngine()
        let at = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 10))
        let ledger = AtmosphereTrackBuilder.CueLedger(budget: 5, continueIf: nil)
        await builder.placeCue(
            OneShotMention(sound: .doorKnock, quote: "a knock at the door"), foundIn: try guardian.window(at: at),
            into: store, engine: engine, ledger: ledger
        )
        let cue = try XCTUnwrap(store.snapshot.cue(at: 10))
        XCTAssertEqual(cue.sound, .doorKnock)
        XCTAssertEqual(cue.wordsBefore, 7)
        XCTAssertEqual(cue.words, 9)
        XCTAssertEqual(ledger.checks, 0, "judged from the text up to its own sentence: no check needed")
        XCTAssertEqual(engine.calls, [])
    }

    func testACueFoundEarlierInThePassageIsCheckedOnItsOwnSentence() async throws {
        let guardian = try SpoilerGuard(chapters: [book()])
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "knock/1", bookID: "book", wordsBetweenEntries: 60))
        let engine = KnockEngine()
        let ledger = AtmosphereTrackBuilder.CueLedger(budget: 5, continueIf: nil)
        let later = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 14))
        await builder.placeCue(
            OneShotMention(sound: .doorKnock, quote: "a knock at the door"), foundIn: try guardian.window(at: later),
            into: store, engine: engine, ledger: ledger
        )
        XCTAssertEqual(engine.calls, [10], "scored again with a window that ends on the knock")
        XCTAssertEqual(store.snapshot.cue(at: 10)?.sound, .doorKnock)
        XCTAssertEqual(ledger.checks, 1)

        // The same sound on the same sentence is not checked twice.
        await builder.placeCue(
            OneShotMention(sound: .doorKnock, quote: "a knock at the door"), foundIn: try guardian.window(at: later),
            into: store, engine: engine, ledger: ledger
        )
        XCTAssertEqual(ledger.checks, 1)
    }

    func testACueThatLeansOnLaterTextIsDropped() async throws {
        let guardian = try SpoilerGuard(chapters: [book()])
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "knock/1", bookID: "book", wordsBetweenEntries: 60))
        let engine = KnockEngine()
        let ledger = AtmosphereTrackBuilder.CueLedger(budget: 5, continueIf: nil)
        let after = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 101))
        await builder.placeCue(
            OneShotMention(sound: .doorKnock, quote: "something sounded at the door"), foundIn: try guardian.window(at: after),
            into: store, engine: engine, ledger: ledger
        )
        XCTAssertEqual(engine.calls, [100])
        XCTAssertNil(store.snapshot.cue(at: 100), "up to its own sentence the text does not say it was a knock")
        XCTAssertEqual(ledger.rejected, 1)

        // With no budget left, nothing is checked and nothing is kept.
        let empty = AtmosphereTrackBuilder.CueLedger(budget: 0, continueIf: nil)
        let knock = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 14))
        await builder.placeCue(
            OneShotMention(sound: .doorKnock, quote: "a knock at the door"), foundIn: try guardian.window(at: knock),
            into: store, engine: engine, ledger: empty
        )
        XCTAssertNil(store.snapshot.cue(at: 10))
    }

    func testABuiltTrackHasItsCues() async throws {
        let guardian = try SpoilerGuard(chapters: [book()])
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "knock/1", bookID: "book", wordsBetweenEntries: 60))
        let report = try await builder.build(into: store, engine: KnockEngine(), concurrency: 2)
        let track = store.snapshot
        XCTAssertEqual(track.cues.map(\.globalIndex), [10], "the knock that leans on the next sentence is not kept")
        XCTAssertEqual(report.cues, 1)
        XCTAssertGreaterThanOrEqual(report.cuesRejected, 1)

        let off = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60, oneShots: false))
        let none = AtmosphereTrackStore(AtmosphereTrack(engineID: "knock/1", bookID: "book", wordsBetweenEntries: 60))
        _ = try await off.build(into: none, engine: KnockEngine(), concurrency: 2)
        XCTAssertEqual(none.snapshot.cues, [])
    }

    // MARK: - Library and stand-ins

    func testTheLibraryReadsOneShotFoldersAndKeepsEachEditionsRecordings() throws {
        let folder = try temporaryFolder()
        for file in ["DoorKnock/knock-fs1.m4a", "DoorKnock/knock-c1.m4a", "Thunder Clap/clap.wav", "Gunshot/bang.wav", "DoorKnock/notes.txt"] {
            let url = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        let manifest = OneShotLibrary.Manifest(sounds: [
            OneShotRecording(id: "doorKnock/fs1", file: "DoorKnock/knock-fs1.m4a", sound: .doorKnock, loudness: -18, use: "personal"),
            OneShotRecording(id: "doorKnock/c1", file: "DoorKnock/knock-c1.m4a", sound: .doorKnock, loudness: -21, use: "publish"),
        ])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("sounds.json"))

        let personal = try OneShotLibrary.load(from: folder)
        XCTAssertEqual(Set(personal.recordings.map(\.file)), ["DoorKnock/knock-fs1.m4a", "Thunder Clap/clap.wav"])
        XCTAssertEqual(personal.sounds, [.doorKnock, .thunderClap])
        XCTAssertEqual(personal.loudness(of: personal.recordings(of: .thunderClap)[0]), OneShotLibrary.assumedLoudness)

        let publish = try OneShotLibrary.load(from: folder, edition: .publish)
        XCTAssertEqual(Set(publish.recordings.map(\.file)), ["DoorKnock/knock-c1.m4a", "Thunder Clap/clap.wav"],
                       "a published build never plays a personal-use recording")

        let stand = OneShotLibrary(folder: URL(fileURLWithPath: "/standins"), recordings: [
            OneShotRecording(id: "doorKnock/synth", file: "DoorKnock/synth.wav", sound: .doorKnock),
            OneShotRecording(id: "owlHoot/synth", file: "OwlHoot/synth.wav", sound: .owlHoot),
        ])
        let merged = personal.filling(from: stand)
        XCTAssertEqual(merged.recordings(of: .doorKnock).map(\.file), ["DoorKnock/knock-fs1.m4a"], "imported first")
        XCTAssertEqual(merged.url(for: merged.recordings(of: .owlHoot)[0]).path, "/standins/OwlHoot/synth.wav")
    }

    func testStandInsAreShortLevelledAndEndInSilence() throws {
        for sound in AmbienceSynth.oneShotStandIns {
            let audio = AmbienceSynth.renderOneShot(sound, sampleRate: 16_000)
            XCTAssertEqual(audio.duration, sound.sketchSeconds, accuracy: 0.01, "\(sound)")
            XCTAssertEqual(Loudness.integrated(audio), AmbienceSynth.oneShotTargetLoudness, accuracy: 1.5, "\(sound)")
            let peak = audio.left.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.01, "\(sound) is heard")
            XCTAssertLessThanOrEqual(peak, 0.9, "\(sound)")
            XCTAssertLessThan(abs(audio.left[audio.frames - 1]) + abs(audio.right[audio.frames - 1]), 1e-3, "\(sound) ends in silence")
        }
        let folder = try temporaryFolder().appendingPathComponent("OneShots")
        let library = try AmbienceSynth.prepareOneShots(at: folder, sounds: [.doorKnock, .owlHoot], sampleRate: 16_000)
        XCTAssertEqual(library.sounds, [.doorKnock, .owlHoot])
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: library.recordings(of: .doorKnock)[0]).path))
        let again = try AmbienceSynth.prepareOneShots(at: folder, sounds: [.doorKnock, .owlHoot], sampleRate: 16_000)
        XCTAssertEqual(again, library, "a current set is kept")
    }

    // MARK: - Player

    final class Harness {
        let scheduler = ManualScheduler()
        let backend = FakeAmbienceBackend()
        let player: AmbiencePlayer
        var events: [AmbienceEvent] = []

        init(cues: [(index: Int, sound: OneShotSound, wordsBefore: Int, words: Int)], oneShots: [OneShotRecording]? = nil) throws {
            let guardian = try SpoilerGuard(chapters: [(0..<200).map { "Sentence \($0)." }])
            var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10, chapterStarts: [0])
            let start = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 0))
            track.insert(.init(position: start, sentence: "Sentence 0.", scene: StoryScene(
                placeID: "p1", placeName: "the kitchen", setting: .indoors, layers: [SceneLayer(.fireplace, .soft)], confidence: 0.9
            )))
            for cue in cues {
                let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: cue.index))
                track.insertCue(.init(position: position, sentence: "Sentence \(cue.index).", sound: cue.sound, wordsBefore: cue.wordsBefore, words: cue.words))
            }
            let beds = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
                AmbienceRecording(id: "fireplace/a", file: "Fireplace/fire.wav", sound: .fireplace, loudness: -23),
            ])
            let library = OneShotLibrary(folder: URL(fileURLWithPath: "/sounds/OneShots"), recordings: oneShots ?? [
                OneShotRecording(id: "doorKnock/a", file: "DoorKnock/knock.wav", sound: .doorKnock, loudness: -20),
                OneShotRecording(id: "owlHoot/a", file: "OwlHoot/owl.wav", sound: .owlHoot, loudness: -20),
            ])
            player = AmbiencePlayer(library: beds, oneShots: library, backend: backend, scheduler: scheduler, seed: 3)
            player.onEvent = { [unowned self] in events.append($0) }
            player.openBook(id: "book")
            player.setTrack(track, forBook: "book")
            player.narratorDidPlay()
            player.sentenceDidStart(globalSentenceIndex: 0, duration: 4)
            scheduler.advance(by: 10)
        }

        func narrate(_ index: Int, duration: TimeInterval = 4, then seconds: TimeInterval) {
            player.sentenceDidStart(globalSentenceIndex: index, duration: duration)
            scheduler.advance(by: seconds)
        }

        var played: [String] { backend.oneShots.map(\.file) }

        func snapshot() -> AmbienceSnapshot {
            var result: AmbienceSnapshot!
            player.snapshot { result = $0 }
            return result
        }
    }

    func testOneOffSoundsAreOffByDefault() throws {
        let h = try Harness(cues: [(5, .doorKnock, 0, 4)])
        for index in 1...8 { h.narrate(index, then: 4) }
        XCTAssertEqual(h.played, [])
        XCTAssertFalse(h.snapshot().oneShotsEnabled)
        XCTAssertEqual(h.snapshot().oneShotSounds, 2)
    }

    func testAOneOffSoundPlaysWhereItsWordsAreRead() throws {
        let h = try Harness(cues: [(5, .doorKnock, 5, 11)])
        h.player.setOneShotsEnabled(true)
        for index in 1...4 { h.narrate(index, then: 4) }
        h.narrate(5, duration: 6, then: 2.9)
        XCTAssertEqual(h.played, [], "halfway through the sentence, not at its start")
        h.scheduler.advance(by: 0.2)
        XCTAssertEqual(h.played, ["knock.wav"])
        let gain = try XCTUnwrap(h.backend.oneShots.first?.gain)
        XCTAssertGreaterThan(gain, 0)
        XCTAssertLessThanOrEqual(gain, 1)
        XCTAssertTrue(h.events.contains(.oneShot(.doorKnock)))
        h.narrate(5, duration: 6, then: 4)
        XCTAssertEqual(h.played.count, 1, "the same sentence again does not play it twice")
    }

    func testTheNextSentencePlaysAWaitingSoundAtOnce() throws {
        let h = try Harness(cues: [(5, .doorKnock, 9, 10)])
        h.player.setOneShotsEnabled(true)
        for index in 1...4 { h.narrate(index, then: 4) }
        h.narrate(5, duration: 20, then: 3)
        XCTAssertEqual(h.played, [], "near the end of a long sentence, capped at 8 s")
        h.narrate(6, then: 0)
        XCTAssertEqual(h.played, ["knock.wav"], "the narrator already read its words")
    }

    func testNoOneOffSoundsWhileReadingOnScreenAfterAJumpOrTooOften() throws {
        let h = try Harness(cues: [(5, .doorKnock, 0, 4), (8, .owlHoot, 0, 4), (12, .doorKnock, 0, 4), (40, .owlHoot, 0, 4)])
        h.player.setOneShotsEnabled(true)
        // Reading on screen: sentences without a duration.
        for index in 1...6 { h.narrate(index, duration: 0, then: 2) }
        XCTAssertEqual(h.played, [], "page turns never play one")

        h.player.narratorDidSeek(toGlobalSentenceIndex: 8)
        h.narrate(8, then: 1)
        XCTAssertEqual(h.played, [], "not right after a seek")

        h.narrate(9, then: 4)
        h.narrate(10, then: 4)
        h.narrate(11, then: 4)
        h.narrate(12, then: 4)
        XCTAssertEqual(h.played, ["knock.wav"])
        h.narrate(40, then: 4)
        XCTAssertEqual(h.played, ["knock.wav"], "at least 30 s apart")
    }

    func testPausingOrTurningThemOffDropsAWaitingSound() throws {
        let h = try Harness(cues: [(5, .doorKnock, 5, 11), (50, .doorKnock, 5, 11)])
        h.player.setOneShotsEnabled(true)
        h.narrate(5, duration: 6, then: 1)
        h.player.narratorDidPause()
        h.scheduler.advance(by: 5)
        XCTAssertEqual(h.played, [])

        h.player.narratorDidPlay()
        h.scheduler.advance(by: 10)
        h.narrate(50, duration: 6, then: 1)
        h.player.setOneShotsEnabled(false)
        h.scheduler.advance(by: 5)
        XCTAssertEqual(h.played, [])
    }

    func testPausingAJumpOrPullingTheHeadphonesCutsAPlayingSound() throws {
        let h = try Harness(cues: [(5, .doorKnock, 0, 4), (50, .owlHoot, 0, 4), (100, .doorKnock, 0, 4)])
        h.player.setOneShotsEnabled(true)
        for index in 1...4 { h.narrate(index, then: 4) }
        h.narrate(5, then: 0.1)
        XCTAssertEqual(h.backend.oneShotPlaying, "knock.wav")
        h.player.narratorDidPause()
        XCTAssertNil(h.backend.oneShotPlaying, "a knock does not carry on after the narrator stops")
        XCTAssertEqual(h.backend.log.last, "stop once 1.0")

        h.player.narratorDidPlay()
        h.scheduler.advance(by: 40)
        h.narrate(50, then: 0.1)
        XCTAssertEqual(h.backend.oneShotPlaying, "owl.wav")
        h.player.narratorDidSeek(toGlobalSentenceIndex: 70)
        XCTAssertNil(h.backend.oneShotPlaying, "cut when the listener jumps")
        XCTAssertEqual(h.backend.log.last, "stop once 0.3")

        h.scheduler.advance(by: 40)
        for index in 96...99 { h.narrate(index, then: 4) }
        h.narrate(100, then: 0.1)
        XCTAssertEqual(h.backend.oneShotPlaying, "knock.wav")
        h.backend.simulateRoute(.builtIn, previousOutputLost: true)
        XCTAssertNil(h.backend.oneShotPlaying, "and at once when the headphones are pulled")
        XCTAssertEqual(h.backend.log.last, "stop once 0.1")
    }

    func testASoundWithNoRecordingIsListedAsMissing() throws {
        let h = try Harness(cues: [(5, .wolfHowl, 0, 4)])
        h.player.setOneShotsEnabled(true)
        for index in 1...6 { h.narrate(index, then: 4) }
        XCTAssertEqual(h.played, [])
        XCTAssertEqual(h.snapshot().missingOneShots, [.wolfHowl])
    }
}
