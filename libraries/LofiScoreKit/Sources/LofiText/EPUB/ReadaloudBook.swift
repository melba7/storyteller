import Foundation

/// A narrated chapter: one linear spine item with a media overlay.
struct NarratedChapter: Equatable {
    /// 0-based position among narrated chapters, in spine order.
    let ordinal: Int
    /// Container-relative path of the content document.
    let textPath: String
    /// Container-relative path of the SMIL file.
    let overlayPath: String
}

/// One narrated sentence of a chapter.
struct NarratedSentence: Equatable {
    /// The sentence's element id.
    let fragmentID: String
    /// Content document holding the sentence.
    let textPath: String
    /// Normalized text. Empty if the id could not be found.
    let text: String
}

/// The sentences of one chapter plus the lookups needed to map a player's
/// position back to a sentence.
struct ChapterSentences {
    let sentences: [NarratedSentence]
    /// "path#fragment" -> sentence index. Covers sentence ids and word ids.
    let indexByFragment: [String: Int]
    /// Audio-only pars ("holes") that play *before* a sentence's own audio:
    /// "audioPath@clipBegin" -> the index of the last sentence narrated before
    /// the hole, or -1 when the hole comes before the chapter's first sentence.
    let beforeHoles: [String: Int]

    static func key(path: String, fragment: String) -> String { path + "#" + fragment }

    static func clipKey(audioPath: String, clipBegin: Double) -> String {
        audioPath + "@" + String(format: "%.3f", clipBegin)
    }
}

/// Where narrated text comes from. Implemented for unzipped EPUB directories
/// and for in-memory books (tests and the eval harness). Internal on purpose:
/// the only public way to get at a book's text is `SpoilerGuard`.
protocol ReadaloudSource: Sendable {
    /// Narrated chapters in reading order. Reads no chapter text.
    func chapters() throws -> [NarratedChapter]
    /// Number of narrated sentences in a chapter. Reads only that chapter's overlay.
    func sentenceCount(of chapter: NarratedChapter) throws -> Int
    /// All narrated sentences of a chapter, in narration order.
    func sentences(of chapter: NarratedChapter) throws -> ChapterSentences
}

/// An unzipped EPUB 3 book with media overlays, read lazily, one chapter at a time.
struct EPUBReadaloudSource: ReadaloudSource {
    let files: any BookFileAccess

    func chapters() throws -> [NarratedChapter] {
        let packagePath = try EPUBPackage.locatePackage(in: files)
        guard let data = try? files.read(packagePath) else {
            throw ReadaloudBookError.missingPackageDocument(packagePath)
        }
        let package = EPUBPackage.parse(data, packagePath: packagePath)
        var chapters: [NarratedChapter] = []
        for item in package.spine where item.linear {
            guard let manifestItem = package.manifest[item.idref],
                !manifestItem.properties.contains("nav"),
                let overlayID = manifestItem.mediaOverlayID,
                let overlay = package.manifest[overlayID]
            else { continue }
            chapters.append(NarratedChapter(
                ordinal: chapters.count,
                textPath: manifestItem.path,
                overlayPath: overlay.path
            ))
        }
        return chapters
    }

    func sentenceCount(of chapter: NarratedChapter) throws -> Int {
        Self.group(try overlayEntries(of: chapter)).order.count
    }

    func sentences(of chapter: NarratedChapter) throws -> ChapterSentences {
        let grouped = Self.group(try overlayEntries(of: chapter))

        // Read each referenced content document once.
        var wantedByPath: [String: Set<String>] = [:]
        for key in grouped.order {
            wantedByPath[key.path, default: []].insert(key.fragment)
        }
        var textByPath: [String: [String: String]] = [:]
        for (path, wanted) in wantedByPath {
            let data = (try? files.read(path)) ?? Data()
            textByPath[path] = ChapterText.texts(data, wanted: wanted)
        }

        let sentences = grouped.order.map { key in
            NarratedSentence(
                fragmentID: key.fragment,
                textPath: key.path,
                text: textByPath[key.path]?[key.fragment] ?? ""
            )
        }
        return ChapterSentences(
            sentences: sentences,
            indexByFragment: grouped.indexByFragment,
            beforeHoles: grouped.beforeHoles
        )
    }

    private func overlayEntries(of chapter: NarratedChapter) throws -> [OverlayEntry] {
        guard let data = try? files.read(chapter.overlayPath) else {
            throw ReadaloudBookError.unreadableFile(chapter.overlayPath)
        }
        return SMILDocument.entries(data, smilPath: chapter.overlayPath)
    }

    struct SentenceKey: Hashable {
        let path: String
        let fragment: String
    }

    struct Grouped {
        var order: [SentenceKey] = []
        var indexByFragment: [String: Int] = [:]
        var beforeHoles: [String: Int] = [:]
    }

    /// Turns pars into sentences. Consecutive pars of one sentence (several audio
    /// ranges, or one par per word) collapse into one. Audio-only pars only become
    /// sentences when no text par names the same sentence (an audio-only chapter
    /// heading); otherwise a hole that plays before its sentence maps to the
    /// sentence before it, so the guard never runs ahead of the narration.
    static func group(_ entries: [OverlayEntry]) -> Grouped {
        var spoken: Set<SentenceKey> = []
        for entry in entries where !entry.isAudioOnly {
            spoken.insert(SentenceKey(path: entry.textPath, fragment: entry.sentenceFragmentID))
        }

        var result = Grouped()
        var indexByKey: [SentenceKey: Int] = [:]
        for entry in entries {
            let key = SentenceKey(path: entry.textPath, fragment: entry.sentenceFragmentID)
            if entry.isAudioOnly && spoken.contains(key) {
                if indexByKey[key] == nil, let audio = entry.audioPath, let begin = entry.clipBegin {
                    // Plays before the sentence's own text: belongs to whatever precedes it.
                    result.beforeHoles[ChapterSentences.clipKey(audioPath: audio, clipBegin: begin)] = result.order.count - 1
                }
                continue
            }
            let index: Int
            if let existing = indexByKey[key] {
                index = existing
            } else {
                index = result.order.count
                indexByKey[key] = index
                result.order.append(key)
            }
            result.indexByFragment[ChapterSentences.key(path: entry.textPath, fragment: entry.fragmentID)] = index
            result.indexByFragment[ChapterSentences.key(path: key.path, fragment: key.fragment)] = index
        }
        return result
    }
}

/// A book held in memory as chapters of sentences. Used by tests and by the
/// eval harness for plain-text books. Fragment ids are "c<chapter>-s<n>".
struct InMemoryReadaloudSource: ReadaloudSource {
    let chapterTexts: [[String]]

    func chapters() throws -> [NarratedChapter] {
        chapterTexts.indices.map {
            NarratedChapter(ordinal: $0, textPath: "memory/c\($0).xhtml", overlayPath: "memory/c\($0).smil")
        }
    }

    func sentenceCount(of chapter: NarratedChapter) throws -> Int {
        chapterTexts[chapter.ordinal].count
    }

    func sentences(of chapter: NarratedChapter) throws -> ChapterSentences {
        var index: [String: Int] = [:]
        let sentences = chapterTexts[chapter.ordinal].enumerated().map { i, text in
            let id = "c\(chapter.ordinal)-s\(i)"
            index[ChapterSentences.key(path: chapter.textPath, fragment: id)] = i
            return NarratedSentence(fragmentID: id, textPath: chapter.textPath, text: TextNormalizer.clean(text))
        }
        return ChapterSentences(sentences: sentences, indexByFragment: index, beforeHoles: [:])
    }
}
