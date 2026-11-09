import Foundation
import LofiMood
import LofiText

/// Finds a book's unzipped EPUB on the device.
public enum BookTextLocator {
    /// Storyteller unzips each readaloud book to `<Documents>/books/extracted/<uuid>/readaloud/`.
    /// If that is not where this book is, the folders above the narrator's audio file are
    /// tried (the audio sits inside the unzipped book).
    public static func epubDirectory(
        bookID: String,
        booksFolder: URL?,
        trackFile: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let booksFolder {
            candidates.append(booksFolder.appendingPathComponent(bookID, isDirectory: true).appendingPathComponent("readaloud", isDirectory: true))
        }
        if let trackFile, trackFile.isFileURL {
            var folder = trackFile.deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(folder)
                let parent = folder.deletingLastPathComponent()
                if parent.path == folder.path { break }
                folder = parent
            }
        }
        return candidates.first { isEPUBRoot($0, fileManager: fileManager) }
    }

    static func isEPUBRoot(_ folder: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: folder.appendingPathComponent("META-INF/container.xml").path)
    }
}

/// A book's score, format 1: one file with Claude's mood reading of the whole book (`mood`,
/// a `MoodTrack`) and its atmosphere cues (`atmosphere`, read by the atmosphere sounds).
/// Either part may be missing, and unknown keys are ignored. It travels inside the
/// read-aloud EPUB at ``pathInBook``, or as `<book>.score.json` next to the Mac's tracks.
public enum BookScore {
    /// Where a score sits inside the unzipped read-aloud EPUB.
    public static let pathInBook = "META-INF/storyteller-lofi/score.json"
    public static let currentFormat = 1

    public enum ScoreError: Error, Equatable {
        case unsupportedFormat(Int)
    }

    private struct File: Decodable {
        var format: Int
        var mood: MoodTrack?
    }

    /// The mood track in a file that holds either a plain mood track or a score. Nil when
    /// the file is a score without a mood part.
    public static func moodTrack(at url: URL) throws -> MoodTrack? {
        let data = try Data(contentsOf: url)
        if let track = try? MoodTrack.decode(data) { return track }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.format == currentFormat else { throw ScoreError.unsupportedFormat(file.format) }
        guard let mood = file.mood else { return nil }
        // Through MoodTrack.decode, for its format check and ordering.
        return try MoodTrack.decode(JSONEncoder().encode(mood))
    }
}

/// Finds a saved mood track (Claude's reading of the whole book, made once on the Mac with
/// `lofi-eval track`, or the mood part of a book's score) for the book being narrated.
public enum MoodTrackFinder {
    /// Looks for `<bookID>.json` first, then any track whose first entries match this book's
    /// sentences. A track that does not match the book's text is never used, so a file with
    /// the wrong name does no harm.
    ///
    /// Matching reads only the sentences of the track's first entries, near the start of the
    /// book, and only to compare their fingerprints; nothing read here reaches the music.
    public static func find(
        bookID: String,
        in folders: [URL],
        spoilerGuard: SpoilerGuard,
        fileManager: FileManager = .default
    ) -> MoodTrack? {
        var named: [URL] = []
        var others: [URL] = []
        for folder in folders {
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "json" {
                // "<id>.json", "<id>.track.json" and "<id>.score.json" all name the book.
                if bookName(of: file) == bookID {
                    named.append(file)
                } else {
                    others.append(file)
                }
            }
        }
        for file in named + others.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(200) {
            guard let track = (try? BookScore.moodTrack(at: file)) ?? nil else { continue }
            if matches(track, spoilerGuard: spoilerGuard) { return track }
        }
        return nil
    }

    /// The mood part of the score inside the book itself, if it has one that still matches
    /// the book's text (a score from before a re-sync whose text changed is skipped).
    public static func inBook(epubDirectory: URL, spoilerGuard: SpoilerGuard) -> MoodTrack? {
        let file = epubDirectory.appendingPathComponent(BookScore.pathInBook)
        guard let track = (try? BookScore.moodTrack(at: file)) ?? nil,
              matches(track, spoilerGuard: spoilerGuard)
        else { return nil }
        return track
    }

    static func bookName(of file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        for suffix in [".track", ".score"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// True when the track's first few entries are sentences of this book, unchanged.
    public static func matches(_ track: MoodTrack, spoilerGuard: SpoilerGuard, checking count: Int = 3) -> Bool {
        let entries = track.entries.prefix(count)
        guard !entries.isEmpty else { return false }
        for entry in entries {
            guard let position = try? spoilerGuard.position(chapterOrdinal: entry.chapterOrdinal, sentenceIndex: entry.sentenceIndex),
                  let window = try? spoilerGuard.window(at: position),
                  let line = window.lines.last(where: { $0.chapterOrdinal == entry.chapterOrdinal && $0.sentenceIndex == entry.sentenceIndex }),
                  TextDigest.fnv1a64(line.text) == entry.sentenceDigest
            else { return false }
        }
        return true
    }
}
