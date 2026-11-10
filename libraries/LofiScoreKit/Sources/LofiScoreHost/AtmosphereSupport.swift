import Foundation
import LofiAtmosphere
import LofiMood
import LofiText

// The atmosphere's side of the host: the player is what the follower drives, and a book's
// atmosphere track is found by matching its first sentences to the book.

extension AmbiencePlayer: NarrationSink {}

/// Finds a book's atmosphere track: the score inside the book first, then imported scores
/// (`Scores/<book>.score.json`), then plain atmosphere tracks
/// (`AtmosphereTracks/<book>.atmosphere.json`). A track is used only when its first entries
/// are this book's sentences, unchanged; matching reads the fingerprints of a few sentences
/// near the start and nothing else.
public enum AtmosphereTrackFinder {
    public static let tracksFolderName = "AtmosphereTracks"

    public static func find(
        bookID: String,
        epubDirectory: URL?,
        scoreFolders: [URL],
        trackFolders: [URL],
        spoilerGuard: SpoilerGuard,
        fileManager: FileManager = .default
    ) -> (track: AtmosphereTrack, origin: String)? {
        if let epubDirectory,
           let track = (try? BookScore.atmosphereTrack(at: epubDirectory.appendingPathComponent(BookScore.pathInBook))) ?? nil,
           matches(track, spoilerGuard: spoilerGuard) {
            return (track, "the book's score")
        }
        for (folders, origin, scores) in [(scoreFolders, "an imported score", true), (trackFolders, "an imported atmosphere track", false)] {
            let found = TrackMatchMemory.lookUp(
                key: (scores ? "atmosphere-score:" : "atmosphere:") + bookID,
                bookID: bookID,
                folders: folders,
                isCandidate: { isCandidate($0, scores: scores) },
                bookName: bookName(of:),
                decode: { (try? BookScore.atmosphereTrack(at: $0)) ?? nil },
                matches: { matches($0, spoilerGuard: spoilerGuard) },
                fileManager: fileManager
            )
            if let found { return (found.track, origin) }
        }
        return nil
    }

    static func isCandidate(_ file: URL, scores: Bool) -> Bool {
        let name = file.lastPathComponent.lowercased()
        return scores ? name.hasSuffix(".score.json") : name.hasSuffix(".json")
    }

    static func bookName(of file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        for suffix in [".atmosphere", ".score"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// True when the track's first few entries are sentences of this book, unchanged.
    public static func matches(_ track: AtmosphereTrack, spoilerGuard: SpoilerGuard, checking count: Int = 3) -> Bool {
        let entries = track.entries.prefix(count)
        guard !entries.isEmpty else { return false }
        for entry in entries {
            guard let position = try? spoilerGuard.position(chapterOrdinal: entry.chapterOrdinal, sentenceIndex: entry.sentenceIndex),
                  position.globalIndex == entry.globalIndex,
                  let window = try? spoilerGuard.window(at: position),
                  let line = window.lines.last(where: { $0.chapterOrdinal == entry.chapterOrdinal && $0.sentenceIndex == entry.sentenceIndex }),
                  TextDigest.fnv1a64(line.text) == entry.sentenceDigest
            else { return false }
        }
        return true
    }
}

extension LofiAtmosphereHost {
    /// The Info.plist key that says which sounds a build may play: "personal" (Mo's own
    /// builds, the default) or "publish" (an App Store build). The app's `fork.config.ts`
    /// sets it from `LOFI_SOUND_EDITION` at build time.
    public static let soundEditionInfoKey = "LofiScoreSoundEdition"

    /// The edition an Info.plist value names; anything but "publish" is a personal build.
    public static func soundEdition(_ value: Any?) -> SoundEdition {
        (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased() == SoundEdition.publish.rawValue ? .publish : .personal
    }
}
