import Foundation

/// The only door to a book's text.
///
/// The guard maps the player's position (the sentence being narrated) to a
/// `CausalWindow` that contains that sentence and the ones before it, never
/// anything after it. It reads chapters lazily: building the window for a
/// position touches only that chapter and the chapters before it.
///
/// The rule it enforces, from the plan: mood(p) = f(text up to and including p).
/// `SpoilerGuardPropertyTests` checks it by rewriting and deleting everything
/// after random positions and asserting the window bytes do not change.
public final class SpoilerGuard: @unchecked Sendable {
    /// How much text a window holds.
    public struct Policy: Sendable, Hashable {
        /// Word budget for a window. The plan's starting point is about 400 words
        /// (a few minutes of narration).
        public var maxWords: Int
        /// How many earlier chapters may top up a window that starts near the
        /// beginning of a chapter.
        public var maxEarlierChapters: Int

        public init(maxWords: Int = 400, maxEarlierChapters: Int = 2) {
            self.maxWords = max(1, maxWords)
            self.maxEarlierChapters = max(0, maxEarlierChapters)
        }

        public static let `default` = Policy()
    }

    public let policy: Policy

    private let source: any ReadaloudSource
    private let chapters: [NarratedChapter]
    private let chaptersByPath: [String: [Int]]
    private let lock = NSLock()
    private var sentenceCache: [Int: ChapterSentences] = [:]
    private var cacheOrder: [Int] = []
    private var countCache: [Int: Int] = [:]
    private static let cachedChapters = 4

    /// Opens an unzipped EPUB 3 book with media overlays, such as Storyteller's
    /// `Documents/books/extracted/<uuid>/readaloud/` directory.
    public convenience init(epubDirectory: URL, policy: Policy = .default) throws {
        try self.init(source: EPUBReadaloudSource(files: DirectoryFileAccess(root: epubDirectory)), policy: policy)
    }

    /// A book given as chapters of sentences. For tests and plain-text evaluation.
    public convenience init(chapters: [[String]], policy: Policy = .default) throws {
        try self.init(source: InMemoryReadaloudSource(chapterTexts: chapters), policy: policy)
    }

    init(source: any ReadaloudSource, policy: Policy) throws {
        self.source = source
        self.policy = policy
        let chapters = try source.chapters()
        guard !chapters.isEmpty else { throw ReadaloudBookError.noNarratedChapters }
        self.chapters = chapters
        var byPath: [String: [Int]] = [:]
        for chapter in chapters {
            byPath[chapter.textPath, default: []].append(chapter.ordinal)
        }
        self.chaptersByPath = byPath
    }

    // MARK: - Positions

    /// Maps what the player reports for the clip that just started playing to a
    /// sentence position.
    ///
    /// - Parameters:
    ///   - textResource: the clip's content document (Readium `OverlayPar.textResource`,
    ///     v3 `SMILEntry.textHref`). Container-relative paths work best; a path
    ///     relative to the package document also works.
    ///   - fragmentId: the clip's element id, with or without a leading "#".
    ///   - audioResource: optional; the clip's audio file, as reported by the player.
    ///   - clipBegin: optional; the clip's start time in that file, in seconds.
    ///     With `audioResource`, lets the guard recognise Storyteller's audio-only
    ///     gaps that play *before* a sentence, and map them to the sentence before.
    /// - Returns: `nil` if the clip is not narrated text the guard knows about, or
    ///   if it plays before anything has been narrated.
    public func position(
        textResource: String,
        fragmentId: String,
        audioResource: String? = nil,
        clipBegin: Double? = nil
    ) throws -> SentencePosition? {
        lock.lock()
        defer { lock.unlock() }

        let path = EPUBPath.normalizeReported(textResource)
        var fragment = fragmentId
        if let hash = fragment.lastIndex(of: "#") {
            fragment = String(fragment[fragment.index(after: hash)...])
        }
        fragment = fragment.removingPercentEncoding ?? fragment

        for ordinal in candidateChapters(for: path) {
            let chapter = try loadSentences(ordinal)

            if let audio = audioResource, let begin = clipBegin {
                let key = ChapterSentences.clipKey(audioPath: EPUBPath.normalizeReported(audio), clipBegin: begin)
                if let before = chapter.beforeHoles[key] {
                    return try positionBefore(chapterOrdinal: ordinal, sentenceIndex: before + 1)
                }
            }

            let chapterPath = chapters[ordinal].textPath
            let exactPath = path.isEmpty ? chapterPath : path
            if let index = chapter.indexByFragment[ChapterSentences.key(path: exactPath, fragment: fragment)]
                ?? chapter.indexByFragment[ChapterSentences.key(path: chapterPath, fragment: fragment)]
                ?? chapter.sentences.firstIndex(where: { $0.fragmentID == fragment })
            {
                return try makePosition(chapterOrdinal: ordinal, sentenceIndex: index)
            }
        }
        return nil
    }

    /// The position of a sentence by its chapter ordinal and index. For the eval harness.
    public func position(chapterOrdinal: Int, sentenceIndex: Int) throws -> SentencePosition? {
        lock.lock()
        defer { lock.unlock() }
        guard chapters.indices.contains(chapterOrdinal), sentenceIndex >= 0 else { return nil }
        guard sentenceIndex < (try loadCount(chapterOrdinal)) else { return nil }
        return try makePosition(chapterOrdinal: chapterOrdinal, sentenceIndex: sentenceIndex)
    }

    /// The first narrated sentence of the book.
    public func firstPosition() throws -> SentencePosition? {
        try position(chapterOrdinal: 0, sentenceIndex: 0)
    }

    /// The sentence after `position`, crossing into the next chapter when needed.
    /// For the eval harness, which walks a book from start to end. Returns no text.
    public func position(after position: SentencePosition) throws -> SentencePosition? {
        lock.lock()
        defer { lock.unlock() }
        var ordinal = position.chapterOrdinal
        var index = position.sentenceIndex + 1
        while chapters.indices.contains(ordinal) {
            if index < (try loadCount(ordinal)) {
                // Chapters with no sentences in between add nothing to the global count.
                return SentencePosition(chapterOrdinal: ordinal, sentenceIndex: index, globalIndex: position.globalIndex + 1)
            }
            ordinal += 1
            index = 0
        }
        return nil
    }

    // MARK: - Windows

    /// The causal window for `position`: the sentence being narrated and the
    /// sentences before it, up to `policy.maxWords` words, topped up from the end
    /// of earlier chapters near a chapter start.
    public func window(at position: SentencePosition) throws -> CausalWindow {
        lock.lock()
        defer { lock.unlock() }

        var collected: [CausalWindow.Line] = []
        var words = 0
        var truncated = false
        var ordinal = position.chapterOrdinal
        var upper = position.sentenceIndex
        var earlierChapters = 0

        outer: while ordinal >= 0 {
            let chapter = try loadSentences(ordinal)
            var index = min(upper, chapter.sentences.count - 1)
            while index >= 0 {
                let sentence = chapter.sentences[index]
                defer { index -= 1 }
                guard !sentence.text.isEmpty else { continue }
                let w = TextNormalizer.wordCount(sentence.text)
                if words + w > policy.maxWords {
                    if collected.isEmpty {
                        // The current sentence alone is over budget: keep its last words.
                        let cut = TextNormalizer.suffix(sentence.text, maxWords: policy.maxWords)
                        collected.append(CausalWindow.Line(
                            chapterOrdinal: ordinal,
                            sentenceIndex: index,
                            fragmentID: sentence.fragmentID,
                            text: cut
                        ))
                        words = TextNormalizer.wordCount(cut)
                        truncated = true
                    }
                    break outer
                }
                collected.append(CausalWindow.Line(
                    chapterOrdinal: ordinal,
                    sentenceIndex: index,
                    fragmentID: sentence.fragmentID,
                    text: sentence.text
                ))
                words += w
            }
            ordinal -= 1
            earlierChapters += 1
            if earlierChapters > policy.maxEarlierChapters || ordinal < 0 { break }
            upper = Int.max
        }

        return CausalWindow(
            position: position,
            lines: collected.reversed(),
            wordCount: words,
            isTruncated: truncated
        )
    }

    // MARK: - Internals (lock held)

    private func candidateChapters(for path: String) -> [Int] {
        if let exact = chaptersByPath[path] { return exact }
        if path.isEmpty { return chapters.map(\.ordinal) }
        // The player may report a path relative to the package document rather
        // than the container root ("Text/ch1.xhtml" vs "OEBPS/Text/ch1.xhtml").
        let suffixMatches = chapters.filter {
            $0.textPath.hasSuffix("/" + path) || path.hasSuffix("/" + $0.textPath)
        }
        if !suffixMatches.isEmpty { return suffixMatches.map(\.ordinal) }
        return chapters.map(\.ordinal)
    }

    private func makePosition(chapterOrdinal: Int, sentenceIndex: Int) throws -> SentencePosition {
        var global = sentenceIndex
        for ordinal in 0..<chapterOrdinal {
            global += try loadCount(ordinal)
        }
        return SentencePosition(chapterOrdinal: chapterOrdinal, sentenceIndex: sentenceIndex, globalIndex: global)
    }

    /// The sentence just before (chapterOrdinal, sentenceIndex), or nil at the very start.
    private func positionBefore(chapterOrdinal: Int, sentenceIndex: Int) throws -> SentencePosition? {
        if sentenceIndex > 0 {
            return try makePosition(chapterOrdinal: chapterOrdinal, sentenceIndex: sentenceIndex - 1)
        }
        var ordinal = chapterOrdinal - 1
        while ordinal >= 0 {
            let count = try loadCount(ordinal)
            if count > 0 { return try makePosition(chapterOrdinal: ordinal, sentenceIndex: count - 1) }
            ordinal -= 1
        }
        return nil
    }

    private func loadSentences(_ ordinal: Int) throws -> ChapterSentences {
        if let cached = sentenceCache[ordinal] {
            cacheOrder.removeAll { $0 == ordinal }
            cacheOrder.append(ordinal)
            return cached
        }
        let loaded = try source.sentences(of: chapters[ordinal])
        sentenceCache[ordinal] = loaded
        countCache[ordinal] = loaded.sentences.count
        cacheOrder.append(ordinal)
        while cacheOrder.count > Self.cachedChapters {
            sentenceCache[cacheOrder.removeFirst()] = nil
        }
        return loaded
    }

    private func loadCount(_ ordinal: Int) throws -> Int {
        if let cached = countCache[ordinal] { return cached }
        let count = try source.sentenceCount(of: chapters[ordinal])
        countCache[ordinal] = count
        return count
    }
}
