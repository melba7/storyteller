// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The phone's own library of ad sounds (PodcastAudioMatch's OwnAdSounds), kept in
// `Podcasts/own-ad-sounds.json`: a print of each sure ad the phone skipped and the listener did
// not undo. The file is read the first time something needs it and only from a background task
// (the ad finder, the head scan and the answers). A missing, damaged or too big file starts an
// empty library. The type is pure; this class adds the lock, the file and the save.
import Foundation
import PodcastAudioMatch

final class PodcastOwnSounds: @unchecked Sendable {
  static let shared = PodcastOwnSounds(url: defaultURL)

  static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(OwnAdSounds.fileName)
  }

  private let url: URL
  private let lock = NSLock()
  private var memory: OwnAdSounds?
  private var changes = 0

  init(url: URL) { self.url = url }

  /// How many times the library changed in this launch. A cached scan of a file is stale when
  /// this has moved on.
  var revision: Int { lock.withLock { changes } }

  /// The sounds to scan an episode of `show` with (its own and those seen twice or more).
  func library(for show: String) -> AdSoundLibrary {
    access { $0.library(for: show) }
  }

  /// Learns the stretches (sure ads that were skipped and not undone) from the frames of their
  /// file. How many sounds were added.
  @discardableResult
  func learn(
    show: String, frames: [MP3Frame], stretches: [MarkedStretch], mac: AdSoundLibrary,
    now: Date = Date()
  ) -> Int {
    mutate {
      $0.learn(
        show: show, frames: frames, stretches: stretches, mac: mac, now: now.timeIntervalSince1970)
    }
  }

  /// The listener undid the skip from `start` to `end`: the prints found in it are dropped, and
  /// the stretch is not learned again. How many sounds were dropped.
  @discardableResult
  func forget(frames: [MP3Frame], start: Double, end: Double, now: Date = Date()) -> Int {
    mutate { $0.forget(frames: frames, start: start, end: end, now: now.timeIntervalSince1970) }
  }

  /// Runs `work` on the library, reading the file first when it has not been read.
  private func access<T>(_ work: (OwnAdSounds) -> T) -> T {
    lock.withLock { work(current()) }
  }

  /// Changes the library and writes the file before the lock is let go, when it changed.
  private func mutate(_ change: (inout OwnAdSounds) -> Int) -> Int {
    lock.withLock {
      let before = current()
      var own = before
      memory = nil  // so the change below does not copy the whole library twice
      let count = change(&own)
      memory = own
      guard own != before else { return count }
      changes += 1
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try own.data.write(to: url, options: .atomic)
      } catch {
        NSLog("Podcasts: the phone's own ad sounds could not be saved: \(error)")
      }
      return count
    }
  }

  /// The caller holds the lock. The file is read up to its limit plus one byte, so a file that
  /// is too big is known without being read whole.
  private func current() -> OwnAdSounds {
    if let memory { return memory }
    var loaded = OwnAdSounds()
    if let handle = try? FileHandle(forReadingFrom: url) {
      defer { try? handle.close() }
      if let data = try? handle.read(upToCount: OwnAdSounds.maxBytes + 1) {
        loaded = OwnAdSounds.read(data)
      }
    }
    memory = loaded
    return loaded
  }
}
