import Foundation
import LofiAtmosphere

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

/// A book's score, format 1: one file with its atmosphere cues (`atmosphere`, an
/// `AtmosphereTrack`) and, from the shelved music, Claude's mood reading of the whole book
/// (`mood`, which this version keeps but does not read). Either part may be missing, and
/// unknown keys are ignored. It travels inside the read-aloud EPUB at ``pathInBook``, or as
/// `<book>.score.json` next to the Mac's tracks.
public enum BookScore {
    /// Where a score sits inside the unzipped read-aloud EPUB.
    public static let pathInBook = "META-INF/storyteller-lofi/score.json"
    public static let currentFormat = 1

    public enum ScoreError: Error, Equatable {
        case notAScore
        case unsupportedFormat(Int)
        /// Neither a mood track nor an atmosphere track.
        case empty
    }

    /// What a score holds. Throws when the data is not a score of this format, or holds
    /// neither part.
    public static func contents(of data: Data) throws -> (mood: Bool, atmosphere: Bool) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let format = object["format"] as? Int
        else { throw ScoreError.notAScore }
        guard format == currentFormat else { throw ScoreError.unsupportedFormat(format) }
        let mood = object["mood"] is [String: Any]
        let atmosphere = object["atmosphere"] is [String: Any]
        guard mood || atmosphere else { throw ScoreError.empty }
        return (mood, atmosphere)
    }

    /// The atmosphere track in a file that holds either a plain atmosphere track or a book
    /// score. Nil when the file is a score without an atmosphere part (or one this version
    /// cannot read).
    public static func atmosphereTrack(at url: URL) throws -> AtmosphereTrack? {
        let data = try Data(contentsOf: url)
        if let track = try? AtmosphereTrack.decode(data) { return track }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let format = object?["format"] as? Int else { return nil }
        guard format == currentFormat else { throw ScoreError.unsupportedFormat(format) }
        guard let part = object?["atmosphere"], JSONSerialization.isValidJSONObject(part) else { return nil }
        return try? AtmosphereTrack.decode(JSONSerialization.data(withJSONObject: part))
    }
}
