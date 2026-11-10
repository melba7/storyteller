import Foundation
import LofiAtmosphere
import LofiAudio
import LofiMood
import LofiScoreCore
import LofiText

// The atmosphere's side of the host: the follower drives the music and the atmosphere
// together, a book's atmosphere track is found like its mood track, and the music fades
// out while a crowd is heard.

extension AmbiencePlayer: NarrationMusicSink {
    /// The atmosphere follows its own track, not the live mood.
    public func receive(_ observation: MoodObservation) {}
}

/// Hands the follower's events to the music player and the atmosphere player, either of
/// which may be missing (music off, or no sounds).
final class NarrationFanOut: NarrationMusicSink, @unchecked Sendable {
    private let lock = NSLock()
    private var music: NarrationMusicSink?
    private var atmosphere: NarrationMusicSink?

    func setMusic(_ sink: NarrationMusicSink?) {
        lock.withLock { music = sink }
    }

    func setAtmosphere(_ sink: NarrationMusicSink?) {
        lock.withLock { atmosphere = sink }
    }

    private var all: [NarrationMusicSink] {
        lock.withLock { [music, atmosphere].compactMap { $0 } }
    }

    func openBook(id: String) { all.forEach { $0.openBook(id: id) } }
    func closeBook() { all.forEach { $0.closeBook() } }
    func narratorDidPlay() { all.forEach { $0.narratorDidPlay() } }
    func narratorDidPause() { all.forEach { $0.narratorDidPause() } }
    func narratorDidSeek(toGlobalSentenceIndex index: Int?) { all.forEach { $0.narratorDidSeek(toGlobalSentenceIndex: index) } }
    func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?) {
        all.forEach { $0.sentenceDidStart(globalSentenceIndex: globalSentenceIndex, duration: duration) }
    }

    func receive(_ observation: MoodObservation) {
        lock.withLock { music }?.receive(observation)
    }
}

extension BookScore {
    private struct AtmospherePart: Decodable {
        var format: Int
        var atmosphere: AtmosphereTrack?
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

/// Finds a book's atmosphere track: the score inside the book first, then imported scores
/// (`MoodTracks/<book>.score.json`), then plain atmosphere tracks
/// (`AtmosphereTracks/<book>.atmosphere.json`). Like the mood tracks, a track is used only
/// when its first entries are this book's sentences, unchanged; matching reads the
/// fingerprints of a few sentences near the start and nothing else.
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

/// Fades the music out while the atmosphere has a crowd, and back in after, by stepping
/// the music player's volume.
final class MusicYield: @unchecked Sendable {
    private let scheduler: LofiScheduler
    private let fade: TimeInterval
    private var ramp = Ramp(value: 1)
    private var ticker: LofiCancellable?
    private var target: LofiScorePlayer?
    private(set) var yielding = false

    init(scheduler: LofiScheduler, fade: TimeInterval) {
        self.scheduler = scheduler
        self.fade = fade
    }

    deinit { ticker?.cancel() }

    /// The music player to steer; a new one starts at the current volume.
    func setPlayer(_ player: LofiScorePlayer?) {
        scheduler.perform { [self] in
            target = player
            player?.setMusicVolume(ramp.value(at: scheduler.now))
        }
    }

    func setYielding(_ yield: Bool) {
        scheduler.perform { [self] in
            guard yield != yielding else { return }
            yielding = yield
            let now = scheduler.now
            ramp.go(to: yield ? 0 : 1, over: fade, at: now, shape: .equalPower)
            guard ticker == nil else { return }
            ticker = scheduler.scheduleRepeating(every: 0.05) { [weak self] in
                guard let self else { return }
                let now = self.scheduler.now
                self.target?.setMusicVolume(self.ramp.value(at: now))
                if !self.ramp.isRunning(at: now) {
                    self.ticker?.cancel()
                    self.ticker = nil
                }
            }
        }
    }

    /// The volume now, for tests and the status.
    var volume: Double {
        ramp.value(at: scheduler.now)
    }
}

extension LofiMusicHost {
    /// The Info.plist key that says which sounds a build may play: "personal" (Mo's own
    /// builds, the default) or "publish" (an App Store build). The app's `fork.config.ts`
    /// sets it from `LOFI_SOUND_EDITION` at build time.
    public static let soundEditionInfoKey = "LofiScoreSoundEdition"

    /// The edition an Info.plist value names; anything but "publish" is a personal build.
    public static func soundEdition(_ value: Any?) -> SoundEdition {
        (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased() == SoundEdition.publish.rawValue ? .publish : .personal
    }
}
