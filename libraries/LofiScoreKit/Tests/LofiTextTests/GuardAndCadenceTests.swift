import Foundation
import LofiScoreCore
import Testing

@testable import LofiText

@Suite("Spoiler guard")
struct SpoilerGuardTests {
    static let book: [[String]] = [
        ["Chapter One.", "It was a quiet morning.", "The kettle sang."],
        ["Chapter Two.", "A knock came at the door.", "Nobody was there.", "The wind rose."],
        ["Chapter Three.", "She ran."],
    ]

    @Test func windowsEndAtThePositionAndTopUpFromEarlierChapters() throws {
        let guardian = try SpoilerGuard(chapters: Self.book, policy: .init(maxWords: 16, maxEarlierChapters: 2))
        let position = try #require(try guardian.position(chapterOrdinal: 1, sentenceIndex: 1))
        #expect(position.globalIndex == 4)
        let window = try guardian.window(at: position)
        #expect(window.lines.map(\.text) == ["It was a quiet morning.", "The kettle sang.", "Chapter Two.", "A knock came at the door."])
        #expect(window.text == "It was a quiet morning. The kettle sang.\n\nChapter Two. A knock came at the door.")
        #expect(window.wordCount == 16)
        #expect(window.currentChapterLines.count == 2)
        #expect(window.recentText(maxWords: 3) == "at the door.")
        #expect(window.recentLines(maxWords: 6).map(\.text) == ["A knock came at the door."])
    }

    @Test func earlierChapterTopUpIsLimited() throws {
        let guardian = try SpoilerGuard(chapters: Self.book, policy: .init(maxWords: 400, maxEarlierChapters: 0))
        let window = try guardian.window(at: try #require(try guardian.position(chapterOrdinal: 2, sentenceIndex: 0)))
        #expect(window.lines.map(\.text) == ["Chapter Three."])
    }

    @Test func overlongSentenceKeepsItsLastWords() throws {
        let guardian = try SpoilerGuard(chapters: [["one two three four five six"]], policy: .init(maxWords: 4))
        let window = try guardian.window(at: try #require(try guardian.firstPosition()))
        #expect(window.lines.map(\.text) == ["three four five six"])
        #expect(window.isTruncated)
    }

    @Test func walksPositionsForward() throws {
        let guardian = try SpoilerGuard(chapters: Self.book)
        var all: [SentencePosition] = []
        var next = try guardian.firstPosition()
        while let position = next {
            all.append(position)
            next = try guardian.position(after: position)
        }
        #expect(all.map(\.globalIndex) == Array(0..<9))
        #expect(at(all.last) == [2, 1])
        #expect(try guardian.position(chapterOrdinal: 0, sentenceIndex: 3) == nil)
        #expect(try guardian.position(chapterOrdinal: 7, sentenceIndex: 0) == nil)
    }

    @Test func mapsAudioOnlyGapsBeforeASentenceToTheSentenceBefore() throws {
        var book = FixtureBook(chapters: [
            .init(id: "a", sentences: [.init(text: "First one."), .init(text: "Second one.", holeBefore: true)]),
            .init(id: "b", sentences: [.init(text: "Third one.", holeBefore: true), .init(text: "Fourth one.")]),
        ])
        book.wordLevel = false
        let dir = try TemporaryDirectory()
        try book.write(to: dir.url)
        let guardian = try SpoilerGuard(epubDirectory: dir.url)

        // While the gap before "Second one." plays, the player already reports a-s1.
        let gap = try #require(book.holeBeforeClipBegin(chapter: book.chapters[0], index: 1))
        let duringGap = try guardian.position(
            textResource: "OEBPS/Text/a.xhtml", fragmentId: "a-s1",
            audioResource: "OEBPS/Audio/book.mp3", clipBegin: gap
        )
        #expect(at(duringGap) == [0, 0])

        // The sentence's own clip maps to the sentence.
        let own = try guardian.position(
            textResource: "OEBPS/Text/a.xhtml", fragmentId: "a-s1",
            audioResource: "OEBPS/Audio/book.mp3", clipBegin: gap + 2.5
        )
        #expect(at(own) == [0, 1])

        // A gap at the start of chapter b belongs to the end of chapter a.
        let chapterGap = try #require(book.holeBeforeClipBegin(chapter: book.chapters[1], index: 0))
        let atChapterStart = try guardian.position(
            textResource: "OEBPS/Text/b.xhtml", fragmentId: "b-s0",
            audioResource: "OEBPS/Audio/book.mp3", clipBegin: chapterGap
        )
        #expect(at(atChapterStart) == [0, 1])
    }

    @Test func unknownClipsHaveNoPosition() throws {
        let book = FixtureBook(chapters: [.init(id: "a", sentences: [.init(text: "Only one.")])])
        let dir = try TemporaryDirectory()
        try book.write(to: dir.url)
        let guardian = try SpoilerGuard(epubDirectory: dir.url)
        #expect(try guardian.position(textResource: "OEBPS/Text/a.xhtml", fragmentId: "nope") == nil)
        #expect(try guardian.position(textResource: "OEBPS/Text/a.xhtml", fragmentId: "a-s0") != nil)
    }

    @Test func refusesBooksWithoutNarration() throws {
        #expect(throws: ReadaloudBookError.noNarratedChapters) {
            try SpoilerGuard(chapters: [])
        }
        let dir = try TemporaryDirectory()
        #expect(throws: ReadaloudBookError.missingContainer) {
            try SpoilerGuard(epubDirectory: dir.url)
        }
    }
}

@Suite("Reading cadence")
struct ReadingCadenceTests {
    /// Positions for a book with the given chapter lengths.
    static func positions(_ lengths: [Int]) throws -> [SentencePosition] {
        let guardian = try SpoilerGuard(chapters: lengths.map { n in (0..<n).map { "Sentence \($0)." } })
        var out: [SentencePosition] = []
        var next = try guardian.firstPosition()
        while let p = next {
            out.append(p)
            next = try guardian.position(after: p)
        }
        return out
    }

    @Test func readsEveryFourSentencesOrTwentySecondsWhicheverIsLater() throws {
        let p = try Self.positions([40])
        var cadence = ReadingCadence()
        var triggers: [(Int, ReadingTrigger)] = []
        // Fast narration: 2 s per sentence, so time is the binding limit (every 10 sentences).
        for (i, position) in p.enumerated() {
            if let t = cadence.observe(position, at: Double(i) * 2) { triggers.append((i, t)) }
        }
        #expect(triggers.map(\.0) == [0, 10, 20, 30])
        #expect(triggers.map(\.1) == [.start, .cadence, .cadence, .cadence])

        // Slow narration: 8 s per sentence, so the sentence count binds (every 4).
        var slow = ReadingCadence()
        var slowIndexes: [Int] = []
        for (i, position) in p.prefix(13).enumerated() where slow.observe(position, at: Double(i) * 8) != nil {
            slowIndexes.append(i)
        }
        #expect(slowIndexes == [0, 4, 8, 12])
    }

    @Test func detectsSeeksAndRepeatsNothingForTheSameSentence() throws {
        let p = try Self.positions([30])
        var cadence = ReadingCadence()
        #expect(cadence.observe(p[0], at: 0) == .start)
        #expect(cadence.observe(p[0], at: 1) == nil)  // word-level books repeat the sentence
        #expect(cadence.observe(p[1], at: 2) == nil)
        #expect(cadence.observe(p[20], at: 3) == .seek)  // forward jump
        #expect(cadence.observe(p[21], at: 4) == nil)
        #expect(cadence.observe(p[5], at: 5) == .seek)  // backward jump
        #expect(cadence.observe(p[5], at: 6, seek: true) == .seek)  // the player says so
        cadence.reset()
        #expect(cadence.observe(p[6], at: 7) == .start)
    }

    @Test func newChapterGetsOneReadingAFewSentencesInAndNoCadenceBefore() throws {
        let p = try Self.positions([10, 1, 12])
        var cadence = ReadingCadence()
        var log: [(SentencePosition, ReadingTrigger)] = []
        for (i, position) in p.enumerated() {
            // 30 s per sentence, so the regular cadence would fire every 4 sentences.
            if let t = cadence.observe(position, at: Double(i) * 30) { log.append((position, t)) }
        }
        let chapterStarts = log.filter { $0.1 == .chapterStart }.map { at($0.0) }
        // Chapter 1 has a single sentence, so its reading is skipped; chapter 2's comes on its third sentence.
        #expect(chapterStarts == [[2, 2]])
        // Nothing fires between leaving chapter 0 and chapter 2's first reading.
        let between = log.filter { $0.0.chapterOrdinal == 1 || ($0.0.chapterOrdinal == 2 && $0.0.sentenceIndex < 2) }
        #expect(between.isEmpty)
        // Within a stretch the global index never goes down.
        let globals = log.map(\.0.globalIndex)
        #expect(globals == globals.sorted())
    }
}

/// [chapterOrdinal, sentenceIndex], for compact expectations.
func at(_ position: SentencePosition?) -> [Int]? {
    position.map { [$0.chapterOrdinal, $0.sentenceIndex] }
}
