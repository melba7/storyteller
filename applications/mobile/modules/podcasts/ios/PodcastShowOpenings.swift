// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The words each show opens with (PodcastAds' ShowOpenings), kept in
// `Podcasts/show-openings.json`: one entry for each of at most 200 shows, read the first time it
// is asked, from a background task (the head scan and the ad finder). A missing or broken file
// starts empty, which means no show has an opening.
import Foundation
import PodcastAds
import PodcastTranscripts

final class PodcastShowOpenings: @unchecked Sendable {
  static let shared = PodcastShowOpenings()

  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(ShowOpenings.fileName)
  }

  private let lock = NSLock()
  private var openings: ShowOpenings?

  private init() {}

  /// The words the show opens with, when they are known.
  func opening(show: String) -> String? {
    lock.withLock { current().opening(for: show) }
  }

  /// Learns from a checked episode: its final ads file and transcript.
  func learn(file: AdsFile, transcript: Transcript, show: String, episode: String) {
    lock.withLock {
      var known = current()
      known.learn(from: file, transcript: transcript, show: show, episode: episode)
      openings = known
      do {
        try known.save(to: Self.url)
      } catch {
        NSLog("Podcasts: the openings of the shows could not be saved: \(error)")
      }
    }
  }

  /// The caller holds the lock.
  private func current() -> ShowOpenings {
    if let openings { return openings }
    let loaded = ShowOpenings.load(from: Self.url)
    openings = loaded
    return loaded
  }
}
