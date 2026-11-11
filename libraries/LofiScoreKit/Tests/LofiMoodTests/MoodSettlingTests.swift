import Foundation
import LofiScoreCore
import LofiText
import Testing

@testable import LofiMood

@Suite("Mood settling")
struct MoodSettlingTests {
    /// An entry at sentence `g` whose reading names `mood` and lists `also`
    /// the way the Claude engine does (half the best mood's score).
    static func entry(_ g: Int, _ mood: MoodBucket, also: [MoodBucket] = []) throws -> MoodTrack.Entry {
        var scores: [MoodBucket: Double]?
        if !also.isEmpty {
            scores = [mood: 1]
            also.forEach { scores?[$0] = 0.5 }
        }
        let reading = MoodReading(
            bucket: mood, valence: mood.anchor.valence, arousal: mood.anchor.arousal,
            confidence: 0.8, scores: scores, engineID: "test/1"
        )
        let readingJSON = String(decoding: try JSONEncoder().encode(reading), as: UTF8.self)
        let json = #"{"chapterOrdinal":0,"sentenceIndex":\#(g),"globalIndex":\#(g),"sentenceDigest":"0","reading":\#(readingJSON)}"#
        return try JSONDecoder().decode(MoodTrack.Entry.self, from: Data(json.utf8))
    }

    static func mood(_ short: Substring) throws -> MoodBucket {
        try #require(MoodBucket.allCases.first { $0.rawValue.hasPrefix(short) }, "no mood starts with \(short)")
    }

    /// "12:ten+mys 30:cal" -> entries: sentence, mood, moods that also fit.
    static func entries(_ tokens: String) throws -> [MoodTrack.Entry] {
        try tokens.split(whereSeparator: \.isWhitespace).map { token in
            let parts = token.split(separator: ":")
            let moods = try parts[1].split(separator: "+").map(mood)
            return try entry(try #require(Int(parts[0])), moods[0], also: Array(moods.dropFirst()))
        }
    }

    static func short(_ moods: [MoodBucket]) -> String {
        moods.map { String($0.rawValue.prefix(3)) }.joined(separator: " ")
    }

    @Test func aMoodThatPassesWithinAMinuteIsLeftOut() throws {
        // Calm, six sentences of tense, calm again.
        let passing = try Self.entries("0:cal 30:cal 60:ten 66:cal 100:cal")
        #expect(MoodSettling.standard.moods(for: passing).allSatisfy { $0 == .calm })
        // The same turn lasting forty sentences is followed, there and back.
        let lasting = try Self.entries("0:cal 30:cal 60:ten 80:ten 100:cal 130:cal")
        #expect(Self.short(MoodSettling.standard.moods(for: lasting)) == "cal cal ten ten cal cal")
    }

    @Test func aMoodTheReadingsStillListKeepsPlaying() throws {
        // Tense and mysterious trade places, each listing the other.
        let tokens = "0:ten 20:mys+ten 40:ten+mys 60:mys+ten 80:ten 100:mys+ten 120:ten"
        #expect(MoodSettling.standard.moods(for: try Self.entries(tokens)).allSatisfy { $0 == .tense })
        // Without the lists every twenty-sentence turn is worth following.
        let bare = tokens.replacingOccurrences(of: "+ten", with: "").replacingOccurrences(of: "+mys", with: "")
        #expect(Self.short(MoodSettling.standard.moods(for: try Self.entries(bare))) == "ten mys ten mys ten mys ten")
        // A long stretch where the other mood is best is followed even though the old one is listed.
        let long = try Self.entries("0:ten 20:mys+ten 60:mys+ten 100:mys+ten 140:mys+ten 180:ten")
        #expect(Self.short(MoodSettling.standard.moods(for: long)) == "ten mys mys mys mys ten")
    }

    @Test func aClassifiersSmallScoresDoNotCountAsAlsoFitting() throws {
        let reading = MoodReading(
            bucket: .calm, valence: 0.2, arousal: 0.1, confidence: 0.6,
            scores: [.calm: 0.5, .cozy: 0.3, .dreamy: 0.15, .tense: 0.05], engineID: "classifier/1"
        )
        #expect(MoodSettling.lists(reading, .calm) && MoodSettling.lists(reading, .cozy))
        #expect(!MoodSettling.lists(reading, .dreamy) && !MoodSettling.lists(reading, .tense))
        #expect(!MoodSettling.lists(reading, .somber), "a mood with no score")
    }

    /// The same 90 entries and answers as `Tools/eval/track_stats.py`'s `app`
    /// rule gives (python3 -I Tools/eval/track_stats.py TRACK --settled-out F
    /// against `lofi-eval settle TRACK --out F`), so the two stay in step.
    static let reference = """
        3:rom+cal 6:cal 27:cal+coz 48:cal 53:cal+dre+coz 87:rom+dre 92:rom+coz 126:rom+coz 128:coz+rom
        133:dre+coz 167:hop 201:cal+coz+dre 222:rom+coz+dre 256:rom+coz+dre 296:pla 297:pla+adv
        310:pla+dre+adv 346:pla 386:hop+pla 388:pla 424:adv+hop+pla 425:coz+dre+rom 461:rom+coz+dre
        497:pla+adv 498:hop+pla 538:hop+adv 572:hop+adv 608:adv 629:hop 650:dre+coz+hop 653:adv+hop
        656:dre+coz 692:dre+coz 732:dre+rom 753:dre+coz 756:rom+coz 761:pla+adv 795:pla+dre 835:hop
        856:hop+pla 859:coz+rom+dre 895:dre+rom+coz 931:mys+dre 932:dre+coz 968:coz+rom+dre 976:coz+rom
        997:coz+rom 998:pla 1001:rom+dre 1037:coz+dre 1073:dre+coz 1074:pla+adv 1114:dre+coz
        1127:dre+coz 1140:dre+rom 1180:dre+rom 1183:rom+dre 1219:coz+rom 1224:cal+coz+dre 1227:cal+dre
        1267:dre 1272:dre+rom 1285:rom+dre 1306:dre+coz 1309:rom+dre 1343:dre+rom+coz 1379:dre+rom+coz
        1413:pla 1447:pla 1455:pla 1491:pla 1493:pla+dre 1506:hop+adv+pla 1519:adv+pla 1524:hop
        1532:adv+hop+pla 1566:hop 1600:pla 1605:pla+adv 1606:pla+adv 1627:adv 1663:pla+adv
        1699:pla+dre+adv 1735:ten+mys 1737:ten 1740:ten 1743:ten 1748:som+mys 1782:mys+dre+som
        1816:som+mel+mys
        """
    static let referenceStandard = """
        rom cal cal cal cal rom rom rom rom dre hop cal rom rom pla pla pla pla pla pla pla coz rom rom
        hop hop hop hop hop hop hop dre dre dre dre dre pla pla hop hop coz dre dre dre coz coz coz coz
        rom coz coz pla dre dre dre dre dre dre dre dre dre dre dre dre dre dre dre pla pla pla pla pla
        hop hop hop hop hop pla pla pla adv pla pla ten ten ten ten som som som
        """
    static let referenceQuick = """
        rom cal cal cal cal rom rom rom rom dre hop cal rom rom pla pla pla pla pla pla pla coz rom rom
        hop hop hop adv hop hop hop dre dre dre dre dre pla pla hop hop coz dre dre dre coz coz coz coz
        rom coz coz pla dre dre dre dre rom rom cal cal dre dre rom rom rom dre dre pla pla pla pla pla
        hop hop hop adv hop pla pla pla adv pla pla ten ten ten ten som mys mys
        """
    static let referenceStrict = """
        rom cal cal cal cal rom rom rom rom dre hop cal rom rom pla pla pla pla pla pla pla coz rom rom
        hop hop hop hop hop dre dre dre dre dre dre dre pla pla hop hop coz dre dre dre coz coz coz coz
        rom coz coz pla dre dre dre dre rom rom cal cal dre dre rom rom rom dre dre pla pla pla pla pla
        hop hop hop adv hop pla pla pla adv pla pla ten ten ten ten som mys som
        """

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func matchesTheReferenceImplementation() throws {
        let entries = try Self.entries(Self.reference)
        #expect(entries.count == 90)
        #expect(Self.short(MoodSettling.standard.moods(for: entries)) == Self.oneLine(Self.referenceStandard))
        #expect(Self.short(MoodSettling(changeCost: 4).moods(for: entries)) == Self.oneLine(Self.referenceQuick))
        #expect(Self.short(MoodSettling(changeCost: 9, alsoCost: 1).moods(for: entries)) == Self.oneLine(Self.referenceStrict))
    }

    @Test func aSceneOnlyStartsOnAnEntryWhoseOwnMoodItIs() throws {
        // Whatever the costs: the music never turns to a mood at an entry
        // that reads as another one, so never before the text reads that way.
        let entries = try Self.entries(Self.reference)
        for settling in [MoodSettling.standard, .init(changeCost: 0), .init(changeCost: 2, alsoCost: 0), .init(changeCost: 40, alsoCost: 0.5), .init(changeCost: 400)] {
            let moods = settling.moods(for: entries)
            #expect(moods.count == entries.count)
            #expect(moods[0] == entries[0].reading.bucket)
            for i in 1..<moods.count where moods[i] != moods[i - 1] {
                #expect(moods[i] == entries[i].reading.bucket, "\(settling): scene \(moods[i]) starts at entry \(i), which reads \(entries[i].reading.bucket)")
            }
            let scenes = settling.scenes(in: entries)
            #expect(scenes.first?.start == 0 && scenes.map(\.mood) == moods.enumerated().filter { $0.offset == 0 || $0.element != moods[$0.offset - 1] }.map(\.element))
        }
        // No cost for changing: every reading is played as it is.
        #expect(MoodSettling(changeCost: 0).moods(for: entries) == entries.map(\.reading.bucket))
        // A prohibitive cost: one scene.
        #expect(Set(MoodSettling(changeCost: 100_000).moods(for: entries)).count == 1)
    }

    @Test func emptyAndSingleEntryTracks() throws {
        #expect(MoodSettling.standard.moods(for: []).isEmpty)
        #expect(MoodSettling.standard.moods(for: [try Self.entry(5, .somber)]) == [.somber])
        #expect(MoodSettling.standard.scenes(in: []).isEmpty)
    }
}

@Suite("Settled playback")
struct SettledPlaybackTests {
    /// 3 chapters of 30 sentences; planned entries at global 2, 12, ..., 82.
    static func setup(
        refinement: MoodTrackBuilder.Refinement? = .init(resolutionSentences: 3, probeBudget: 1),
        settling: MoodSettling? = .standard
    ) throws -> (SpoilerGuard, MoodTrackBuilder, MoodTrackStore) {
        let guardian = try SpoilerGuard(chapters: sampleBook(chapters: 3, sentences: 30))
        let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 120, refinement: refinement, settling: settling))
        let store = MoodTrackStore(MoodTrack(engineID: "step/1", bookID: "sample", wordsBetweenEntries: 120))
        return (guardian, builder, store)
    }

    /// Calm, five sentences of tense at 40, calm, then tense from 69 on.
    static let steps: [(from: Int, bucket: MoodBucket)] = [(0, .calm), (40, .tense), (45, .calm), (69, .tense)]

    @Test func probesGoToTheChangesTheMusicFollows() async throws {
        let (_, builder, store) = try Self.setup()
        let engine = StepEngine(Self.steps)
        let report = try await builder.build(into: store, engine: engine)
        // The passing tense reading at 42 is left alone; the lasting change
        // is pinned: 62..72 -> 67 (calm) -> 69 (tense).
        #expect(report.probes == 2 && report.unrefinedChanges == 0)
        #expect(Set(engine.calls).isSuperset(of: [67, 69]))
        #expect(!engine.calls.contains { (33...41).contains($0) || (43...51).contains($0) })

        // With settling off every turn is pinned, as before.
        let (_, every, plain) = try Self.setup(settling: nil)
        let all = try await every.build(into: plain, engine: StepEngine(Self.steps))
        #expect(all.probes > report.probes && all.unrefinedChanges == 0)
    }

    @Test func playbackSkipsAPassingMoodAndFollowsALastingOneFromItsOwnSentence() async throws {
        let (guardian, builder, store) = try Self.setup()
        _ = try await builder.build(into: store, engine: StepEngine(Self.steps))
        let settled = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine())
        let plain = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine(), settling: nil)

        var p = try guardian.position(chapterOrdinal: 0, sentenceIndex: 2)
        while let position = p {
            let window = try guardian.window(at: position)
            let reading = try #require(settled.trackReading(for: window))
            let own = try #require(plain.trackReading(for: window))
            let g = position.globalIndex
            // The same entry either way, and never one from later in the book.
            #expect(reading.engineID == own.engineID)
            let echoed = try #require(echoedPosition(reading))
            #expect(echoed <= (position.chapterOrdinal, position.sentenceIndex))
            #expect(reading.bucket == (g >= 69 ? .tense : .calm), "sentence \(g)")
            if (42..<52).contains(g) {
                // The entry here reads tense; the scene is calm.
                #expect(own.bucket == .tense)
                #expect(reading.point == MoodBucket.calm.anchor && reading.scores == nil && reading.confidence == own.confidence)
            } else {
                #expect(reading == own)
            }
            p = try guardian.position(after: position)
        }
    }

    @Test func theSettledViewFollowsTheTrackAsItGrows() async throws {
        // Only chapter 0 is scored so far, and it is calm throughout.
        let (guardian, builder, store) = try Self.setup(refinement: nil)
        _ = try await builder.build(into: store, engine: StepEngine([(0, .calm), (40, .tense)]), chapters: 0...0)
        let engine = TrackedMoodEngine(store: store, fallback: LexiconMoodEngine())
        let at25 = try window(guardian, 0, 25)
        #expect(engine.trackReading(for: at25)?.bucket == .calm)
        let before = store.version

        // Chapter 1 arrives: tense from 40 on, which lasts.
        _ = try await builder.build(into: store, engine: StepEngine([(0, .calm), (40, .tense)]), chapters: 1...1)
        #expect(store.version > before)
        #expect(engine.trackReading(for: at25)?.bucket == .calm)
        #expect(engine.trackReading(for: try window(guardian, 1, 11))?.bucket == .calm, "sentence 41: the entry at 32 still stands")
        #expect(engine.trackReading(for: try window(guardian, 1, 12))?.bucket == .tense)
        #expect(engine.trackReading(for: try window(guardian, 1, 29))?.bucket == .tense)
    }
}
