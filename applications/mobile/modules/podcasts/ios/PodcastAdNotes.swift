// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the player tells the Mac about ad skipping (docs/PODCASTS-ADS-TEACHING.md): a note for
// each thing that happened, kept as `Podcasts/pending-ad-notes.jsonl` in Application Support until
// the app's JavaScript has written it to the linked folder, and the tally for each show, kept as
// `Podcasts/ad-tally.json`. The rules (the note's line, the file's text, the counting) are
// `PhoneNote`, `PendingNotes` and `AdTally` in PodcastAds. Every read and write of both files
// goes through one queue, so nothing waits on the disk on the main thread.

import Foundation
import PodcastAds

final class PodcastAdNotes: @unchecked Sendable {
  static let shared = PodcastAdNotes()

  private let queue = DispatchQueue(label: "StorytellerLofi.adNotes", qos: .utility)
  /// The tally, read from its file the first time it is needed. Only used on `queue`.
  private var tally: AdTally?

  private init() {}

  private static var folder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
  }

  static var notesURL: URL { folder.appendingPathComponent("pending-ad-notes.jsonl") }
  static var tallyURL: URL { folder.appendingPathComponent("ad-tally.json") }

  /// Writes the note and counts it for the show. `seconds` is what a skip took out of the
  /// listening (for "skipped" and "undone"; the other kinds ignore it). `by` is the name of the
  /// finder that made the ad the note is about, nil when it is not known.
  func record(
    _ what: PhoneNote.What, episode: String, show: String?, start: Double, end: Double?,
    kind: AdKind?, seconds: Double = 0, by: String? = nil
  ) {
    let time = Date().timeIntervalSince1970 * 1000
    let note = PhoneNote(
      at: time, what: what, episode: episode, show: show, start: start, end: end, kind: kind,
      by: by)
    queue.async {
      self.append(note.line)
      var counted = self.loadedTally()
      counted.count(what, show: show, seconds: seconds, at: time)
      self.tally = counted
      do {
        try counted.save(to: Self.tallyURL)
      } catch {
        NSLog("Podcasts: the ad tally could not be saved: \(error)")
      }
    }
  }

  /// The pending notes as JSON lines, "" when there are none.
  func readPending() async -> String {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: Self.read(Self.notesURL))
      }
    }
  }

  /// Drops the first `count` lines, the ones the app has saved, and only those written at
  /// `upToAt` (milliseconds) or earlier. Notes made since stay.
  func removePending(_ count: Int, upToAt: Double) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      queue.async {
        let kept = PendingNotes.dropping(count, upToAt: upToAt, from: Self.read(Self.notesURL))
        Self.write(kept, to: Self.notesURL, what: "the pending ad notes")
        continuation.resume()
      }
    }
  }

  /// The tally as the JSON text of `getAdTally()`.
  func tallyJSON() async -> String {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: self.loadedTally().json) }
    }
  }

  // MARK: On the queue

  private func loadedTally() -> AdTally {
    if let tally { return tally }
    let loaded = AdTally.load(from: Self.tallyURL)
    tally = loaded
    return loaded
  }

  private func append(_ line: String) {
    guard !line.isEmpty else { return }
    let text = PendingNotes.appending(line, to: Self.read(Self.notesURL))
    Self.write(text, to: Self.notesURL, what: "a pending ad note")
  }

  private static func read(_ file: URL) -> String {
    (try? String(contentsOf: file, encoding: .utf8)) ?? ""
  }

  private static func write(_ text: String, to file: URL, what: String) {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file, options: .atomic)
    } catch {
      NSLog("Podcasts: \(what) could not be saved: \(error)")
    }
  }
}
