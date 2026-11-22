// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Whether each show's episodes start with an ad (PodcastAds' ShowStarts), kept in
// `Podcasts/show-starts.json`: a few hundred bytes per show, read by `warm()` from a background
// task when a stream's head is made (or when a scan records what it found), never on the main
// actor, which only asks `startsClean`. A missing or broken file starts empty, which means no show
// is known to start clean.
import Foundation
import PodcastAds

final class PodcastShowStarts: @unchecked Sendable {
  static let shared = PodcastShowStarts()

  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(ShowStarts.fileName)
  }

  private let lock = NSLock()
  private var starts: ShowStarts?

  private init() {}

  /// Whether the show's last five checked episodes had no ad in their first 30 seconds. This is
  /// asked on the main actor (Play), so it never reads the file and never waits for the lock: when
  /// the file is not read yet, or is being written, no show is known to start clean.
  func startsClean(show: String) -> Bool {
    guard lock.try() else { return false }
    defer { lock.unlock() }
    return starts?.startsClean(show: show) ?? false
  }

  /// Reads the file, if it was not read. Called from a background task, before Play can be pressed.
  func warm() {
    lock.withLock { _ = current() }
  }

  /// Notes what a stream's head scan found. A scan that did not reach far enough says nothing.
  func record(show: String, ads: [FoundAd], reached: Double) {
    lock.withLock {
      var known = current()
      known.record(show: show, ads: ads, reached: reached)
      starts = known
      do {
        try known.save(to: Self.url)
      } catch {
        NSLog("Podcasts: the starts of the shows could not be saved: \(error)")
      }
    }
  }

  /// The caller holds the lock.
  private func current() -> ShowStarts {
    if let starts { return starts }
    let loaded = ShowStarts.load(from: Self.url)
    starts = loaded
    return loaded
  }
}
