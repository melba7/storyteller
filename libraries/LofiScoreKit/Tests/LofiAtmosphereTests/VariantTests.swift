import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiAudio
import LofiText

/// More specific sounds (variants), personal-use recordings, and the short narration
/// pauses for swells and hushes.
final class VariantTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("variants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Names and files

    func testVariantIDsAndFolders() {
        XCTAssertEqual(SoundVariant.normalizedID("church bells"), "churchBells")
        XCTAssertEqual(SoundVariant.normalizedID("ChurchBells"), "churchBells")
        XCTAssertEqual(SoundVariant.normalizedID("church_bells"), "churchBells")
        XCTAssertEqual(SoundVariant.normalizedID("waterfall"), "waterfall")
        XCTAssertNil(SoundVariant.normalizedID("heavy rain"), "a built-in sound is not a variant")
        XCTAssertNil(SoundVariant.normalizedID("rain2"))
        XCTAssertNil(SoundVariant.normalizedID("2fast"))
        XCTAssertNil(SoundVariant.normalizedID("café"))
        XCTAssertNil(SoundVariant.normalizedID(String(repeating: "x", count: 33)))
        XCTAssertNil(SoundVariant.normalizedID(" - "))

        let bells = SoundVariant(id: "churchBells", of: .oldTown, about: "church bells", search: "church bells")
        XCTAssertEqual(bells.folderName, "OldTown.ChurchBells")
        XCTAssertEqual(SoundVariant.parseFolder("OldTown.ChurchBells")?.sound, .oldTown)
        XCTAssertEqual(SoundVariant.parseFolder("old town.church bells")?.id, "churchBells")
        XCTAssertNil(SoundVariant.parseFolder("Bagpipes.Drone"))
        XCTAssertNil(SoundVariant.parseFolder("OldTown"))
        XCTAssertNil(AmbientSound(lenient: "OldTown.ChurchBells"), "a variant folder is not a plain sound's")
    }

    func testLayersCarryTheirVariant() throws {
        let scene = StoryScene(placeID: "p1", layers: [
            SceneLayer(.oldTown, .soft),
            SceneLayer(.oldTown, .soft, variant: "churchBells"),
            SceneLayer(.rain, .full),
            SceneLayer(.rain, .faint, variant: "drizzle"),
        ])
        XCTAssertEqual(scene.layers, [SceneLayer(.rain, .full), SceneLayer(.oldTown, .soft, variant: "churchBells")],
                       "the loudest layer wins, then the one with a variant")
        XCTAssertEqual(scene.description, "p1 [unclear]: rain full, oldTown.churchBells soft")

        let plain = try String(decoding: JSONEncoder().encode(SceneLayer(.rain)), as: UTF8.self)
        XCTAssertFalse(plain.contains("variant"), "a plain layer is written as before")
        let decoded = try JSONDecoder().decode(StoryScene.self, from: Data("""
            {"placeID":"p2","layers":[{"sound":"crowd","level":"soft","variant":"tavern"}],"moment":"thunderclap"}
            """.utf8))
        XCTAssertEqual(decoded.layers, [SceneLayer(.crowd, .soft, variant: "tavern")])
        XCTAssertNil(decoded.moment, "an unknown moment is ignored")
        XCTAssertTrue(decoded.replacesMusic, "a crowd's variant is still a crowd")
    }

    func testTracksKeepTheirVariantsWithTheirFirstUse() throws {
        var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10)
        track.addVariant(SoundVariant(id: "waterfall", of: .river, about: "a waterfall", search: "waterfall", firstIndex: 40))
        track.addVariant(SoundVariant(id: "churchBells", of: .oldTown, about: "bells", search: "church bells", firstIndex: 12))
        track.addVariant(SoundVariant(id: "waterfall", of: .river, about: "a waterfall", search: "waterfall", firstIndex: 30))
        track.addVariant(SoundVariant(id: "waterfall", of: .river, about: "a waterfall", search: "waterfall", firstIndex: 50))
        XCTAssertEqual(track.variants.map(\.id), ["churchBells", "waterfall"])
        XCTAssertEqual(track.variants.map(\.firstIndex), [12, 30], "a variant keeps its earliest use")
        XCTAssertEqual(track.variants(before: 30).map(\.id), ["churchBells"])
        XCTAssertEqual(track.variants(before: 31).map(\.id), ["churchBells", "waterfall"])

        let reloaded = try AtmosphereTrack.decode(track.encoded())
        XCTAssertEqual(reloaded.variants, track.variants)
        let old = try AtmosphereTrack.decode(Data("""
            {"format":1,"engineID":"claude.opus-5-5/a1","bookID":"old","wordsBetweenEntries":250,"chapterStarts":[0],"entries":[]}
            """.utf8))
        XCTAssertEqual(old.variants, [], "a track from before variants still reads")
    }

    func testTheCatalogNeverOffersABooksOwnVariantsBack() throws {
        let catalog = SoundVariantCatalog(variants: [
            .init(id: "churchBells", of: .oldTown, about: "bells", search: "church bells", books: ["Dracula"], starter: true),
            .init(id: "dragonRoost", of: .strongWind, about: "a dragon's roost", search: "cave wind", books: ["Dracula"]),
            .init(id: "ghostWail", of: .wind, about: "a wailing wind", search: "wind howl", books: ["Dracula", "Emma"]),
            .init(id: "rain", of: .rain, about: "not a variant", search: "rain"),
        ])
        XCTAssertEqual(catalog.offered(toBook: "Dracula").map(\.id), ["churchBells"],
                       "the starter set, never this book's own requests (they may come from later chapters)")
        XCTAssertEqual(catalog.offered(toBook: "Persuasion").map(\.id), ["churchBells", "dragonRoost", "ghostWail"])
        let data = try JSONEncoder().encode(catalog)
        XCTAssertEqual(try JSONDecoder().decode(SoundVariantCatalog.self, from: data), catalog)
    }

    // MARK: - Library and editions

    func testTheLibraryReadsVariantFoldersAndKeepsEachEditionsRecordings() throws {
        let folder = try temporaryFolder()
        let files = [
            "Rain/rain-commons.wav", "Rain/rain-fs1.m4a", "Rain/rain-fs2.m4a",
            "OldTown/town.wav", "OldTown.ChurchBells/bells-fs3.m4a", "Bagpipes.Drone/drone.wav",
            "Fireplace/fire-nc.m4a",
        ]
        for file in files {
            let url = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        let manifest = AmbienceLibrary.Manifest(sounds: [
            AmbienceRecording(id: "rain/wc1", file: "Rain/rain-commons.wav", sound: .rain, loudness: -25, use: "publish"),
            AmbienceRecording(id: "rain/fs1", file: "Rain/rain-fs1.m4a", sound: .rain, loudness: -22, use: "personal"),
            AmbienceRecording(id: "rain/fs2", file: "Rain/rain-fs2.m4a", sound: .rain, loudness: -22, use: "personal"),
            AmbienceRecording(id: "oldTown.churchBells/fs3", file: "OldTown.ChurchBells/bells-fs3.m4a", sound: .oldTown,
                              variant: "ChurchBells", loudness: -24, use: "personal"),
            AmbienceRecording(id: "fireplace/nc", file: "Fireplace/fire-nc.m4a", sound: .fireplace, license: "CC BY-NC", use: "personal"),
        ])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(AmbienceLibrary.manifestName))

        let mine = try AmbienceLibrary.load(from: folder)
        XCTAssertEqual(Set(mine.recordings(of: .rain).map(\.id)), ["rain/fs1", "rain/fs2"],
                       "Mo's build plays the better personal-use rain, not the publishing stand-by")
        XCTAssertEqual(mine.recordings(of: .oldTown).map(\.file), ["OldTown/town.wav"], "a plain sound never plays a variant")
        XCTAssertEqual(mine.recordings(of: .oldTown, variant: "churchBells").map(\.id), ["oldTown.churchBells/fs3"])
        XCTAssertEqual(mine.sounds, [.rain, .oldTown, .fireplace])
        XCTAssertEqual(mine.variants, ["oldTown.churchBells"])
        XCTAssertFalse(mine.recordings.contains { $0.file.hasPrefix("Bagpipes") })

        let published = try AmbienceLibrary.load(from: folder, edition: .publish)
        XCTAssertEqual(published.recordings.map(\.file).sorted(), ["OldTown/town.wav", "Rain/rain-commons.wav"],
                       "a published build never plays a personal-use recording")
        XCTAssertEqual(published.variants, [])

        // A layer plays its variant's recording when there is one, otherwise its plain sound's.
        let bells = SceneLayer(.oldTown, .soft, variant: "churchBells")
        XCTAssertEqual(mine.recording(for: bells, key: "k")?.variant, "churchBells")
        XCTAssertEqual(published.recording(for: bells, key: "k")?.file, "OldTown/town.wav")
        XCTAssertEqual(mine.recording(for: SceneLayer(.oldTown, .soft, variant: "fairground"), key: "k")?.file, "OldTown/town.wav")
        XCTAssertNil(mine.recording(for: SceneLayer(.seaShore, .soft, variant: "harbour"), key: "k"))
    }

    func testAPlayerPlaysAVariantOrItsPlainSound() throws {
        let library = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
            AmbienceRecording(id: "oldTown/a", file: "OldTown/town.wav", sound: .oldTown, loudness: -23),
            AmbienceRecording(id: "oldTown.churchBells/a", file: "OldTown.ChurchBells/bells.wav", sound: .oldTown, variant: "churchBells", loudness: -23),
        ])
        let track = try testTrack([
            (0, "p1", [SceneLayer(.oldTown, .soft, variant: "churchBells")], 0.9),
            (10, "p2", [SceneLayer(.oldTown, .soft, variant: "fairground")], 0.9),
            (20, "p1", [SceneLayer(.oldTown, .soft, variant: "churchBells")], 0.9),
        ])
        let scheduler = ManualScheduler()
        let backend = FakeAmbienceBackend()
        let player = AmbiencePlayer(library: library, backend: backend, scheduler: scheduler, seed: 3)
        player.openBook(id: "book")
        player.setTrack(track, forBook: "book")
        player.narratorDidPlay()
        player.sentenceDidStart(globalSentenceIndex: 0, duration: 4)
        scheduler.advance(by: 25)
        XCTAssertEqual(Set(backend.audible.keys), ["bells.wav"])
        player.sentenceDidStart(globalSentenceIndex: 10, duration: 4)
        scheduler.advance(by: 25)
        XCTAssertEqual(Set(backend.audible.keys), ["town.wav"], "a variant with no recording plays its plain sound")
        player.sentenceDidStart(globalSentenceIndex: 20, duration: 4)
        scheduler.advance(by: 25)
        XCTAssertEqual(Set(backend.audible.keys), ["bells.wav"])
    }

    // MARK: - Claude

    private func memory(variants: [SoundVariant] = []) throws -> PlaceMemory {
        let guardian = try SpoilerGuard(chapters: [["One.", "Two."]])
        let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 0))
        var memory = PlaceMemory(entries: [AtmosphereTrack.Entry(
            position: position, sentence: "One.",
            scene: StoryScene(placeID: "p1", placeName: "the square", setting: .outdoors, layers: [SceneLayer(.oldTown)])
        )])
        memory.offer(variants)
        return memory
    }

    func testAnswersMayUseAndAddVariants() throws {
        let waterfall = SoundVariant(id: "waterfall", of: .river, about: "a waterfall close by", search: "waterfall")
        let memory = try memory(variants: [waterfall])
        let answer = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"p1","placeName":"the square","setting":"outdoors",
             "sounds":[{"sound":"oldTown","level":"soft","variant":"church bells"},{"sound":"forest","level":"faint","variant":"waterfall"},
                       {"sound":"wind","level":"faint","variant":"ghostWail"},{"sound":"rain","level":"faint","variant":""}],
             "newSounds":[{"id":"churchBells","of":"oldTown","about":"church bells across the square","search":"church bells town"},
                          {"id":"pigeons","of":"birdsong","about":"pigeons cooing","search":"pigeons"}],
             "moment":"swell","world":"","cue":"","confidence":0.8}
            """, memory: memory)
        XCTAssertEqual(Set(answer.scene.layers), [
            SceneLayer(.oldTown, .soft, variant: "churchBells"),
            SceneLayer(.river, .faint, variant: "waterfall"),
            SceneLayer(.wind, .faint),
            SceneLayer(.rain, .faint),
        ], "a variant decides its own sound; an unknown variant leaves the plain sound")
        XCTAssertEqual(answer.newVariants, [SoundVariant(id: "churchBells", of: .oldTown, about: "church bells across the square", search: "church bells town")],
                       "one new sound per answer, and only one the scene uses")
        XCTAssertEqual(answer.scene.moment, .swell)

        let rejected = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"none","placeName":"","setting":"unclear","sounds":[{"sound":"rain","level":"soft","variant":"heavyRain"}],
             "newSounds":[{"id":"heavyRain","of":"rain","about":"","search":""},{"id":"waterfall","of":"river","about":"x","search":"y"}],
             "moment":"hush","world":"","cue":"","confidence":0.5}
            """, memory: memory)
        XCTAssertEqual(rejected.scene.layers, [SceneLayer(.rain, .soft)])
        XCTAssertEqual(rejected.newVariants, [], "built-in names and variants already offered are not new")
        XCTAssertNil(rejected.scene.moment, "no moment without a place")

        let before = try ClaudeSceneEngine.answer(fromJSON: """
            {"place":"p1","placeName":"","setting":"outdoors","sounds":[],"world":"","cue":"","confidence":0.9}
            """, memory: memory)
        XCTAssertEqual(before.newVariants, [], "answers in the old shape still read")
        XCTAssertNil(before.scene.moment)
    }

    func testThePromptOffersSharedVariantsOnceAndTheBooksOwnWithThePassage() throws {
        let shared = [SoundVariant(id: "cafe", of: .crowd, about: "a cafe: low chatter, cups", search: "cafe ambience")]
        let own = SoundVariant(id: "churchBells", of: .oldTown, about: "church bells across a town", search: "church bells", firstIndex: 0)
        let memory = try memory(variants: [own] + shared)
        let guardian = try SpoilerGuard(chapters: [["One.", "The bells rang out over the square."]])
        let window = try guardian.window(at: try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: 1)))
        let engine = ClaudeSceneEngine(apiKey: "k", configuration: .init(model: "claude-haiku-5-5", sharedVariants: shared))
        let body = engine.body(for: window, memory: memory)
        let system = try XCTUnwrap(((body["system"] as? [[String: Any]])?.first)?["text"] as? String)
        let message = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first)?["content"] as? String)
        XCTAssertTrue(system.contains("- cafe (crowd): a cafe: low chatter, cups"))
        XCTAssertTrue(system.contains("swell"))
        XCTAssertFalse(message.contains("cafe"), "shared variants sit in the cached system prompt only")
        XCTAssertTrue(message.contains("- churchBells (oldTown): church bells across a town"))
        XCTAssertTrue(ClaudeScenePrompt.system.contains("available in every book (variant (the sound it is a kind of): what it is): none"))

        let properties = try XCTUnwrap(ClaudeScenePrompt.schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["newSounds"])
        XCTAssertEqual((properties["moment"] as? [String: Any])?["enum"] as? [String], ["none", "swell", "hush"])
        XCTAssertEqual(engine.id, "claude.haiku-5-5/a2")
    }

    // MARK: - Builder

    /// "[square]" puts the story in the town square; "[bells]" adds church bells, asked for
    /// as a new sound the first time; "[hall]" is a crowded hall, a swell when its sentence
    /// is the passage's last.
    final class BellsEngine: SceneEngine, @unchecked Sendable {
        let id = "bells/1"
        private let lock = NSLock()
        private(set) var offered: [(position: Int, variants: [String])] = []

        func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer {
            lock.withLock { offered.append((window.position.globalIndex, memory.variants.map(\.id))) }
            let text = window.lines.map(\.text).joined(separator: " ")
            if text.contains("[hall]") {
                let moment: StoryScene.Moment? = window.lines.last?.text.contains("[hall]") == true ? .swell : nil
                let scene = StoryScene(placeID: nil, placeName: "the hall", setting: .indoors, layers: [SceneLayer(.crowd, .soft)], confidence: 0.9, moment: moment)
                return SceneAnswer(place: memory.place(named: "the hall").map { .known($0.id) } ?? .new("the hall"), scene: scene, world: nil)
            }
            guard text.contains("[square]") else {
                return SceneAnswer(place: .none, scene: StoryScene(placeID: nil, layers: [], confidence: 0.9), world: nil)
            }
            var layers = [SceneLayer(.oldTown, .soft)]
            var new: [SoundVariant] = []
            if text.contains("[bells]") {
                layers = [SceneLayer(.oldTown, .soft, variant: "churchBells")]
                if memory.variant("churchBells") == nil {
                    new = [SoundVariant(id: "churchBells", of: .oldTown, about: "church bells", search: "church bells")]
                }
            }
            let scene = StoryScene(placeID: nil, placeName: "the square", setting: .outdoors, layers: layers, confidence: 0.9)
            let place: SceneAnswer.Place = memory.place(named: "the square").map { .known($0.id) } ?? .new("the square")
            return SceneAnswer(place: place, scene: scene, world: nil, newVariants: new)
        }
    }

    func testVariantsAreOfferedOnlyAfterTheBookFirstAskedForThem() async throws {
        var one = (0..<80).map { "Plain sentence number \($0) with a few more words in it." }
        one[2] = "They came out into the square. [square]"
        one[40] = "Then the bells began to ring across the square. [square] [bells]"
        let guardian = try SpoilerGuard(chapters: [one])
        let starter = SoundVariant(id: "cafe", of: .crowd, about: "a cafe", search: "cafe")
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60), offeredVariants: [starter])
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "bells/1", bookID: "book", wordsBetweenEntries: 60))
        let engine = BellsEngine()
        let report = try await builder.build(into: store, engine: engine, concurrency: 2)

        let track = store.snapshot
        let bells = try XCTUnwrap(track.variants.first { $0.id == "churchBells" })
        let first = try XCTUnwrap(bells.firstIndex)
        XCTAssertEqual(bells.of, .oldTown)
        XCTAssertTrue((40...43).contains(first), "refinement pins the first use near its sentence, never before it (\(first))")
        XCTAssertEqual(track.variants.map(\.id), ["churchBells"], "an offered variant nobody used stays out of the track")
        for call in engine.offered {
            XCTAssertTrue(call.variants.contains("cafe"), "the starter set is offered everywhere")
            if call.variants.contains("churchBells") {
                XCTAssertGreaterThan(call.position, first, "the book's own variant only after a sentence that asked for it")
            }
        }
        XCTAssertTrue(engine.offered.contains { $0.variants.contains("churchBells") }, "and offered from then on")
        XCTAssertEqual(report.variants, 1)
        XCTAssertEqual(report.newVariants, 1)
        XCTAssertEqual(track.entry(atOrBefore: first - 1)?.scene.layers.compactMap(\.variant), [], "no bells before they ring")
        XCTAssertEqual(track.entry(atOrBefore: first)?.scene.layers, [SceneLayer(.oldTown, .soft, variant: "churchBells")])
    }

    func testASwellIsPinnedToItsOwnSentence() async throws {
        var one = (0..<90).map { "Plain sentence number \($0) with a few more words in it." }
        one[2] = "They came out into the square. [square]"
        one[47] = "The doors of the great hall swung open. [hall]"
        let guardian = try SpoilerGuard(chapters: [one])
        let builder = AtmosphereTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 60))
        let store = AtmosphereTrackStore(AtmosphereTrack(engineID: "bells/1", bookID: "book", wordsBetweenEntries: 60))
        _ = try await builder.build(into: store, engine: BellsEngine(), concurrency: 2)
        let track = store.snapshot
        let first = try XCTUnwrap(track.entries.first { $0.scene.placeName == "the hall" })
        XCTAssertEqual(first.globalIndex, 47, "a swell is pinned to one sentence, not three")
        XCTAssertEqual(first.scene.moment, .swell)
    }

    // MARK: - Pauses

    final class PauseHarness {
        let scheduler = ManualScheduler()
        let backend = FakeAmbienceBackend()
        let player: AmbiencePlayer
        var requests: [TimeInterval] = []
        var accept = true

        init(track: AtmosphereTrack) {
            let library = AmbienceLibrary(folder: URL(fileURLWithPath: "/sounds"), recordings: [
                AmbienceRecording(id: "oldTown/a", file: "OldTown/town.wav", sound: .oldTown, loudness: -23),
                AmbienceRecording(id: "crowd/a", file: "Crowd/crowd.wav", sound: .crowd, loudness: -23),
            ])
            player = AmbiencePlayer(library: library, backend: backend, scheduler: scheduler, seed: 5)
            player.requestNarrationHold = { [unowned self] seconds in
                requests.append(seconds)
                return accept
            }
            player.openBook(id: "book")
            player.setTrack(track, forBook: "book")
            player.narratorDidPlay()
        }

        func narrate(_ index: Int, then seconds: TimeInterval) {
            player.sentenceDidStart(globalSentenceIndex: index, duration: 4)
            scheduler.advance(by: seconds)
        }

        func gain(_ file: String) -> Double { Double(backend.audible[file] ?? 0) }
    }

    private func pauseTrack(moment: StoryScene.Moment = .swell) throws -> AtmosphereTrack {
        let guardian = try SpoilerGuard(chapters: [(0..<200).map { "Sentence \($0)." }])
        var track = AtmosphereTrack(engineID: "test/1", bookID: "book", wordsBetweenEntries: 10, chapterStarts: [0])
        func add(_ index: Int, _ place: String, _ layers: [SceneLayer], _ moment: StoryScene.Moment? = nil) throws {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: index))
            let scene = StoryScene(placeID: place, placeName: place, setting: .indoors, layers: layers, confidence: 0.9, moment: moment)
            track.insert(.init(position: position, sentence: "Sentence \(index).", scene: scene))
        }
        try add(0, "p1", [SceneLayer(.oldTown, .soft)])
        try add(30, "p2", moment == .swell ? [SceneLayer(.crowd, .soft)] : [], moment)
        try add(60, "p3", [SceneLayer(.crowd, .soft)], .swell)
        return track
    }

    func testASwellPausesTheNarratorWhileTheCrowdRisesThenSettles() throws {
        let h = PauseHarness(track: try pauseTrack())
        h.narrate(0, then: 15)
        XCTAssertEqual(h.requests, [], "no pause for a scene without a moment")
        // The hall arrives 15 s after the square: a swell does not wait for the dwell.
        h.narrate(30, then: 0.1)
        XCTAssertEqual(h.requests, [0.8])
        h.scheduler.advance(by: 3.9)
        // crowd at soft: -18 voice, -28 bed, -3 crowd, -5 soft, file at -23: 31 dB down.
        let settled = pow(10, -31.0 / 20)
        h.player.narrationHold(began: true)
        h.scheduler.advance(by: 0.6)
        XCTAssertEqual(h.gain("crowd.wav"), settled * pow(10, 8.0 / 20), accuracy: 0.001, "the crowd rises 8 dB while the narrator is quiet")
        h.player.narrationHold(began: false)
        h.scheduler.advance(by: 3.5)
        XCTAssertEqual(h.gain("crowd.wav"), settled, accuracy: 0.001, "and settles under the voice")

        // The next swell comes too soon after this one: no second pause.
        h.narrate(60, then: 5)
        XCTAssertEqual(h.requests.count, 1)
        var snapshot: AmbienceSnapshot?
        h.player.snapshot { snapshot = $0 }
        XCTAssertEqual(snapshot?.pausesEnabled, true)
        XCTAssertEqual(snapshot?.pausesAvailable, true)
    }

    func testNoPauseRightAfterStartingOrWhenTurnedOffOrRefused() throws {
        // Seconds after pressing play.
        let early = PauseHarness(track: try pauseTrack())
        early.narrate(30, then: 1)
        XCTAssertEqual(early.requests, [], "never within 10 s of play or a seek")

        let off = PauseHarness(track: try pauseTrack())
        off.player.setPausesEnabled(false)
        off.narrate(0, then: 15)
        off.narrate(30, then: 1)
        XCTAssertEqual(off.requests, [])

        let refused = PauseHarness(track: try pauseTrack())
        refused.accept = false
        refused.narrate(0, then: 15)
        refused.narrate(30, then: 7)
        XCTAssertEqual(refused.requests, [0.8])
        let level = refused.gain("crowd.wav")
        refused.player.narrationHold(began: true)
        refused.scheduler.advance(by: 1)
        XCTAssertEqual(refused.gain("crowd.wav"), level, accuracy: 0.0005, "a refused pause never swells")

        // A pause that was dropped before it began leaves nothing behind.
        let dropped = PauseHarness(track: try pauseTrack())
        dropped.narrate(0, then: 15)
        dropped.narrate(30, then: 7)
        dropped.player.narrationHold(began: false)
        dropped.player.narrationHold(began: true)
        dropped.scheduler.advance(by: 1)
        XCTAssertEqual(dropped.gain("crowd.wav"), pow(10, -31.0 / 20), accuracy: 0.001)
    }

    func testAHushCutsTheOldSoundDuringThePause() throws {
        let h = PauseHarness(track: try pauseTrack(moment: .hush))
        h.narrate(0, then: 15)
        h.narrate(30, then: 0.5)
        XCTAssertEqual(h.requests, [0.8], "a hush asks for a pause too")
        XCTAssertGreaterThan(h.gain("town.wav"), 0, "the square is still fading out")
        h.player.narrationHold(began: true)
        h.scheduler.advance(by: 0.5)
        XCTAssertEqual(h.gain("town.wav"), 0, "and is gone in the pause")
    }
}
