// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The skip log: one line of JSON for each ad skip, with how it ended and the words around both
// edges, kept as `Podcasts/skip-log.jsonl` in Application Support. The rules (how a skip ends,
// the 500-line cap, the file's text) are `SkipWatch` and `SkipLog` in PodcastAds. The file stays
// on the phone and nothing is sent by this code: it only makes a copy in the caches folder when
// the listener taps "Send skip log" in Profile, for the share sheet. The words come from the
// episode's transcript, so the file is never committed.

import Foundation
import PodcastAds
import PodcastDownloads
import PodcastTranscripts

/// What the player tells the log, called where the stats are counted (PodcastPlayer+Ads.swift).
@MainActor
final class PodcastSkipLogger {
  static let shared = PodcastSkipLogger()

  private var watch = SkipWatch()
  private var settleTask: Task<Void, Never>?

  private init() {}

  private var now: Double { ProcessInfo.processInfo.systemUptime }

  private func context(_ episodeId: String) -> SkipContext {
    SkipContext(
      time: Date().timeIntervalSince1970, episode: episodeId,
      show: PodcastPlayer.shared.current?.showId, source: nil,
      tapToSkip: PodcastTimeline.secondsSinceTap(episodeId))
  }

  private func write(_ entries: [SkipLogEntry]) {
    if !entries.isEmpty { SkipLogFile.append(entries) }
  }

  /// The player skipped an ad.
  func skipped(_ skip: AdSkip, episodeId: String) {
    write(watch.skipped(skip, context: context(episodeId), now: now))
    // A skip with no complaint for 20 seconds is kept: nothing else would tell the watch.
    settleTask?.cancel()
    settleTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64((SkipWatch.settleSeconds + 1) * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      self.write(self.watch.settle(now: self.now))
    }
  }

  /// The listener tapped Undo on the note.
  func undone() { write(watch.undone()) }

  /// The listener went back into the skipped ad, and `AdSkipper` made this trim.
  func trimmed(_ trim: AdTrim) { write(watch.trimmed(trim)) }

  /// The listener (or Undo, or a lock screen button) is moving the playhead to `position`; the
  /// player still reads the old place. `knownAds` are the ads that will be skipped.
  func seeked(to position: Double, knownAds: [FoundAd]) {
    guard let episodeId = PodcastPlayer.shared.current?.id else { return }
    write(
      watch.seeked(
        from: PodcastPlayer.shared.position, to: position, knownAds: knownAds,
        context: context(episodeId), now: now))
  }
}

/// The words of the stream head that is being checked, which it keeps in memory only. The log
/// reads them for a skip made before the download is filed and transcribed.
enum SkipLogWords {
  private static let lock = NSLock()
  private static var noted: (episodeId: String, words: [TranscriptWord])?

  /// Called by the head scan with all the words so far.
  static func note(_ words: [TranscriptWord], for episodeId: String) {
    lock.withLock { noted = (episodeId, words) }
  }

  /// The episode's words: its transcript when it has one (finished or so far), else the head's.
  static func words(for episodeId: String) -> [TranscriptWord] {
    if let downloads = PodcastDownloader.shared.store,
      let (_, transcripts) = PodcastAdFinder.shared.stores(for: episodeId, in: downloads)
    {
      if let transcript = transcripts.loadTranscript() { return transcript.words }
      if let partial = transcripts.loadPartial() { return partial.words }
    }
    return lock.withLock { noted?.episodeId == episodeId ? (noted?.words ?? []) : [] }
  }
}

/// The log file. Every read and write goes through one queue, so two skips close together
/// cannot write over each other.
enum SkipLogFile {
  private static let queue = DispatchQueue(label: "StorytellerLofi.skipLog", qos: .utility)

  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("skip-log.jsonl")
  }

  /// Adds the entries, with the words around their edges, and keeps the newest 500 lines.
  static func append(_ entries: [SkipLogEntry]) {
    queue.async {
      let file = SkipLogFile.url
      var log = SkipLog(text: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
      var words: [String: [TranscriptWord]] = [:]
      for var entry in entries {
        if words[entry.episode] == nil { words[entry.episode] = SkipLogWords.words(for: entry.episode) }
        entry.addWords(from: words[entry.episode] ?? [])
        log.append(entry)
      }
      do {
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(log.text.utf8).write(to: file, options: .atomic)
      } catch {
        NSLog("Podcasts: the skip log could not be saved: \(error)")
      }
    }
  }

  /// A copy of the log in the caches folder, for the share sheet (the sharing code reads only
  /// the app's own document and caches folders). Nil when nothing is logged yet.
  static func copyForSharing() -> URL? {
    queue.sync { () -> URL? in
      guard let data = try? Data(contentsOf: SkipLogFile.url), !data.isEmpty else { return nil }
      let copy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("skip-log.jsonl")
      do {
        try data.write(to: copy, options: .atomic)
        return copy
      } catch {
        NSLog("Podcasts: the skip log could not be copied: \(error)")
        return nil
      }
    }
  }
}
