import Foundation
import Testing

@testable import LofiText

/// The no-spoiler property from the plan: for random positions p, changing or
/// deleting any text after p must leave the window for p byte-for-byte identical.
///
/// Each trial renders a random Storyteller-style book to disk, takes the window
/// at a random sentence, then rewrites the book so that everything after that
/// sentence is different (rewritten, deleted, extended, reordered, truncated
/// mid-file, or no longer narrated), opens the rewritten book with a fresh
/// guard, and compares window bytes. 100 books x 10 positions = 1,000 positions.
@Suite("Spoiler guard property")
struct SpoilerGuardPropertyTests {
    enum Mutation: CaseIterable {
        case rewriteLater
        case deleteLater
        case appendMore
        case dropLaterChapters
        case shuffleLaterChapters
        case laterChaptersNotNarrated
        case truncateFilesAfterPosition
    }

    static let books = 100
    static let positionsPerBook = 10

    @Test("Text after the position never changes the window", arguments: 0..<books)
    func windowIgnoresEverythingAfterPosition(seed: Int) throws {
        var rng = SplitMix64(seed: UInt64(seed) &* 7919 &+ 17)
        let book = FixtureBook.random(&rng)
        let policy = SpoilerGuard.Policy(
            maxWords: [12, 40, 120, 400].randomElement(using: &rng)!,
            maxEarlierChapters: Int.random(in: 0...2, using: &rng)
        )

        let base = try TemporaryDirectory()
        let original = base.url.appendingPathComponent("original")
        try book.write(to: original)
        let guardA = try SpoilerGuard(epubDirectory: original, policy: policy)

        let narrated = book.narratedChapters
        for trial in 0..<Self.positionsPerBook {
            let chapterOrdinal = Int.random(in: 0..<narrated.count, using: &rng)
            let chapter = narrated[chapterOrdinal]
            let index = Int.random(in: 0..<chapter.sentences.count, using: &rng)
            let fragment = fragmentToReport(book: book, chapter: chapter, index: index, rng: &rng)

            let positionA = try #require(
                try guardA.position(textResource: book.textPath(chapter), fragmentId: fragment)
            )
            #expect(positionA.chapterOrdinal == chapterOrdinal)
            #expect(positionA.sentenceIndex == index)
            let windowA = try guardA.window(at: positionA)

            let mutation = Mutation.allCases.randomElement(using: &rng)!
            let mutatedDir = base.url.appendingPathComponent("mutated-\(trial)")
            try writeMutated(book, after: chapter.id, index: index, mutation: mutation, to: mutatedDir, rng: &rng)

            let guardB = try SpoilerGuard(epubDirectory: mutatedDir, policy: policy)
            let positionB = try #require(
                try guardB.position(textResource: book.textPath(chapter), fragmentId: fragment),
                "seed \(seed) trial \(trial) \(mutation): position lost"
            )
            #expect(positionB == positionA, "seed \(seed) trial \(trial) \(mutation)")
            let windowB = try guardB.window(at: positionB)
            #expect(
                windowB.canonicalData == windowA.canonicalData,
                "seed \(seed) trial \(trial) \(mutation): window changed"
            )
        }
    }

    @Test("Windows hold exactly the narrated text up to the position", arguments: 0..<40)
    func windowMatchesTheBookModel(seed: Int) throws {
        var rng = SplitMix64(seed: UInt64(seed) &+ 1_000)
        let book = FixtureBook.random(&rng)
        let policy = SpoilerGuard.Policy(maxWords: [15, 60, 400].randomElement(using: &rng)!, maxEarlierChapters: 2)
        let dir = try TemporaryDirectory()
        try book.write(to: dir.url)
        let guardian = try SpoilerGuard(epubDirectory: dir.url, policy: policy)

        let narrated = book.narratedChapters
        for _ in 0..<10 {
            let c = Int.random(in: 0..<narrated.count, using: &rng)
            let i = Int.random(in: 0..<narrated[c].sentences.count, using: &rng)
            let position = try #require(
                try guardian.position(textResource: book.textPath(narrated[c]), fragmentId: "\(narrated[c].id)-s\(i)")
            )
            let window = try guardian.window(at: position)
            let expected = oracleLines(narrated: narrated, chapter: c, index: i, policy: policy)
            #expect(window.lines.map(\.text) == expected, "seed \(seed) at ch\(c) s\(i)")
            #expect(window.lines.last?.sentenceIndex == i)
            #expect(window.lines.last?.chapterOrdinal == c)
            let expectedGlobal = narrated[..<c].reduce(0) { $0 + $1.sentences.count } + i
            #expect(position.globalIndex == expectedGlobal)
        }
    }

    // MARK: - Helpers

    /// What a player would report for the sentence: its id, or for word-level books
    /// sometimes the id of one of its words.
    private func fragmentToReport(book: FixtureBook, chapter: FixtureBook.Chapter, index: Int, rng: inout SplitMix64) -> String {
        let id = "\(chapter.id)-s\(index)"
        guard book.wordLevel, Bool.random(using: &rng) else { return id }
        let words = chapter.sentences[index].text.split(separator: " ").count
        return "\(id)-w\(Int.random(in: 0..<words, using: &rng))"
    }

    /// An independent re-statement of the window rule over the book model.
    private func oracleLines(narrated: [FixtureBook.Chapter], chapter c: Int, index i: Int, policy: SpoilerGuard.Policy) -> [String] {
        var lines: [String] = []
        var words = 0
        var chapter = c
        var upper = i
        var earlier = 0
        outer: while chapter >= 0 {
            var j = min(upper, narrated[chapter].sentences.count - 1)
            while j >= 0 {
                let text = FixtureBook.expectedText(narrated[chapter].sentences[j])
                j -= 1
                let w = text.split(separator: " ").count
                if w == 0 { continue }
                if words + w > policy.maxWords {
                    if lines.isEmpty {
                        lines.append(text.split(separator: " ").suffix(policy.maxWords).joined(separator: " "))
                    }
                    break outer
                }
                lines.append(text)
                words += w
            }
            chapter -= 1
            earlier += 1
            if earlier > policy.maxEarlierChapters { break }
            upper = Int.max
        }
        return lines.reversed()
    }

    private func writeMutated(
        _ book: FixtureBook,
        after chapterID: String,
        index: Int,
        mutation: Mutation,
        to dir: URL,
        rng: inout SplitMix64
    ) throws {
        var mutated = book
        let c = mutated.chapters.firstIndex { $0.id == chapterID }!
        let laterRange = (c + 1)..<mutated.chapters.count

        switch mutation {
        case .rewriteLater:
            for j in (index + 1)..<max(index + 1, mutated.chapters[c].sentences.count) {
                mutated.chapters[c].sentences[j] = FixtureBook.randomSentence(&rng)
            }
            for k in laterRange {
                mutated.chapters[k].sentences = mutated.chapters[k].sentences.map { _ in FixtureBook.randomSentence(&rng) }
            }
        case .deleteLater:
            mutated.chapters[c].sentences.removeSubrange((index + 1)...)
            mutated.chapters.removeSubrange(laterRange)
        case .appendMore:
            let extra = (0..<Int.random(in: 1...10, using: &rng)).map { _ in FixtureBook.randomSentence(&rng) }
            mutated.chapters[c].sentences.insert(contentsOf: extra, at: index + 1)
            mutated.chapters.append(FixtureBook.Chapter(id: "late_addition", sentences: extra))
        case .dropLaterChapters:
            mutated.chapters.removeSubrange(laterRange)
        case .shuffleLaterChapters:
            var later = Array(mutated.chapters[laterRange])
            later.shuffle(using: &rng)
            mutated.chapters.replaceSubrange(laterRange, with: later)
        case .laterChaptersNotNarrated:
            for k in laterRange {
                if Bool.random(using: &rng) { mutated.chapters[k].hasOverlay = false } else { mutated.chapters[k].linear = false }
            }
        case .truncateFilesAfterPosition:
            try mutated.write(to: dir)
            let chapter = mutated.chapters[c]
            let nextID = "id=\"\(chapter.id)-s\(index + 1)"
            try truncate(file: dir.appendingPathComponent(mutated.textPath(chapter)), atFirst: nextID)
            try truncate(file: dir.appendingPathComponent(mutated.smilPath(chapter)), atFirst: nextID)
            for k in laterRange {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(mutated.textPath(mutated.chapters[k])))
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(mutated.smilPath(mutated.chapters[k])))
            }
            return
        }
        try mutated.write(to: dir)
    }

    /// Cuts a file off at the first occurrence of `marker`, mid-tag, leaving
    /// everything after it out. Files without the marker are left alone.
    private func truncate(file: URL, atFirst marker: String) throws {
        let data = try Data(contentsOf: file)
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: marker) else { return }
        // Cut a few bytes into the tag so the file ends mid-markup.
        let cut = text.utf8.distance(from: text.startIndex, to: range.lowerBound) + 3
        try Data(data.prefix(cut)).write(to: file)
    }
}

/// A directory under the system temp folder, removed when the value is released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lofiscorekit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
