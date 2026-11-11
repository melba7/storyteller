import Foundation

/// A place in the narration: one sentence of one narrated chapter.
///
/// Only `SpoilerGuard` creates positions, so `globalIndex` always agrees with
/// the chapter and sentence numbers.
public struct SentencePosition: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    /// 0-based ordinal among narrated chapters.
    public let chapterOrdinal: Int
    /// 0-based index of the sentence within its chapter.
    public let sentenceIndex: Int
    /// 0-based index across the book. Computed only from chapters at or before this one.
    public let globalIndex: Int

    init(chapterOrdinal: Int, sentenceIndex: Int, globalIndex: Int) {
        self.chapterOrdinal = chapterOrdinal
        self.sentenceIndex = sentenceIndex
        self.globalIndex = globalIndex
    }

    public static func < (lhs: SentencePosition, rhs: SentencePosition) -> Bool {
        (lhs.chapterOrdinal, lhs.sentenceIndex) < (rhs.chapterOrdinal, rhs.sentenceIndex)
    }

    public var description: String { "ch\(chapterOrdinal):s\(sentenceIndex) (#\(globalIndex))" }
}

/// The text a mood engine may look at for one position: the sentence being
/// narrated and the sentences just before it, oldest first.
///
/// Only `SpoilerGuard.window(at:)` can make one, and it never reads past the
/// position it is given. Engines accept nothing else, so no engine can see text
/// that has not been narrated yet. A window carries no file paths, no book title
/// and nothing about how long the book or chapter is.
public struct CausalWindow: Sendable, Hashable {
    /// One narrated sentence inside the window.
    public struct Line: Sendable, Hashable {
        public let chapterOrdinal: Int
        public let sentenceIndex: Int
        /// The sentence's element id, e.g. "chapter_one-s12". Useful for debugging.
        public let fragmentID: String
        public let text: String
    }

    /// The sentence being narrated. Always the last line.
    public let position: SentencePosition
    /// Oldest first. Never empty unless nothing at all has been narrated yet.
    public let lines: [Line]
    /// Words across all lines.
    public let wordCount: Int
    /// True when the oldest line was cut to fit the word budget.
    public let isTruncated: Bool

    init(position: SentencePosition, lines: [Line], wordCount: Int, isTruncated: Bool) {
        self.position = position
        self.lines = lines
        self.wordCount = wordCount
        self.isTruncated = isTruncated
    }

    /// The window as plain text, oldest first. Sentences are joined with spaces;
    /// a chapter change is marked with a blank line.
    public var text: String {
        var out = ""
        var previousChapter: Int? = nil
        for line in lines {
            if let previous = previousChapter {
                out += previous == line.chapterOrdinal ? " " : "\n\n"
            }
            out += line.text
            previousChapter = line.chapterOrdinal
        }
        return out
    }

    /// The last `maxWords` words of the window, for engines with a small input.
    public func recentText(maxWords: Int) -> String {
        TextNormalizer.suffix(text, maxWords: maxWords)
    }

    /// The most recent sentences whose combined length stays within `maxWords`
    /// (always at least the current sentence), joined like `text`.
    public func recentLines(maxWords: Int) -> [Line] {
        var kept: [Line] = []
        var words = 0
        for line in lines.reversed() {
            let w = TextNormalizer.wordCount(line.text)
            if !kept.isEmpty && words + w > maxWords { break }
            kept.append(line)
            words += w
        }
        return kept.reversed()
    }

    /// Lines narrated in the current chapter only.
    public var currentChapterLines: [Line] {
        lines.filter { $0.chapterOrdinal == position.chapterOrdinal }
    }

    /// A stable byte encoding of everything an engine can see. Two windows with
    /// equal bytes give every deterministic engine the same input. The spoiler
    /// property test compares these bytes.
    public var canonicalData: Data {
        var s = "lofi-window/1\n"
        s += "position \(position.chapterOrdinal) \(position.sentenceIndex) \(position.globalIndex)\n"
        s += "words \(wordCount) truncated \(isTruncated)\n"
        for line in lines {
            s += "\(line.chapterOrdinal)\t\(line.sentenceIndex)\t\(line.fragmentID)\t\(line.text)\n"
        }
        return Data(s.utf8)
    }
}
