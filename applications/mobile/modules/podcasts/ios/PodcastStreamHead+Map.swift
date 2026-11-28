// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A stream and the Mac's episode map (PodcastEpisodeMaps.swift). While a stream's file arrives it
// is lined up against the map again for every megabyte that came, when the map comes, and once
// more when the file is whole, so the Mac's marks are carried over well ahead of the listener,
// also after the head scan's first minutes are over. What the map gives is kept here and goes
// into every write of the stream's ads file (`persist`). Each look reads only the new bytes and
// runs in its own background task, one at a time.
import Foundation
import PodcastAds

/// What the Mac's map gives for a stream so far.
final class HeadMap: @unchecked Sendable {
  /// A look is made for every this many bytes that arrive (about a minute of audio).
  static let step: Int64 = 1 << 20

  let following = MapFollowing()
  private let lock = NSLock()
  private var found: [FoundAd] = []
  /// What an earlier look gave and the map gives no more.
  private var gone: [FoundAd] = []
  private var looking = false
  private var again = false
  private var lookedAt: Int64 = 0

  /// The skips the map gives now.
  var ads: [FoundAd] { lock.withLock { found } }

  /// Whether the map gives a skip over any part of `ad`.
  func overlaps(_ ad: FoundAd) -> Bool {
    ads.contains { $0.start < ad.end && ad.start < $0.end }
  }

  /// Whether enough bytes arrived since the last look for another one.
  func due(_ available: Int64) -> Bool {
    lock.withLock { () -> Bool in
      guard available - lookedAt >= Self.step else { return false }
      lookedAt = available
      return true
    }
  }

  /// Notes that a look starts. False while one is running: that one then looks once more.
  func begin() -> Bool {
    lock.withLock { () -> Bool in
      if looking {
        again = true
        return false
      }
      looking = true
      return true
    }
  }

  /// Keeps what a look gave. Says whether it changed, and whether another look was asked for
  /// meanwhile (the look then goes on).
  func end(_ ads: [FoundAd]?) -> (changed: Bool, more: Bool) {
    lock.withLock { () -> (changed: Bool, more: Bool) in
      var changed = false
      // A look iOS held no time for (nil) leaves what the last one gave.
      if let ads, ads != found {
        changed = true
        gone = (gone + found).filter { !ads.contains($0) }
        found = ads
      }
      let more = again
      again = false
      if !more { looking = false }
      return (changed: changed, more: more)
    }
  }

  /// The ads of the file on disk without the ones an earlier look gave and the map gives no
  /// more, so a copy that turns out not to line up loses what the map gave before.
  func standing(_ before: [FoundAd]) -> [FoundAd] {
    lock.withLock { before.filter { !gone.contains($0) } }
  }
}

extension PodcastStreamHead {
  /// More of the file is on disk: the map is looked at again when enough came.
  func noteBytesForMap(_ available: Int64) {
    if map.due(available) { lookAtMap() }
  }

  /// Lines the audio on disk up against the Mac's map of the episode, in the background, and
  /// writes the stream's ads again when what the map gives changed. Nothing happens when the
  /// episode has no map on the phone or its copy does not line up.
  func lookAtMap() {
    guard map.begin() else { return }
    Task.detached(priority: .utility) { [self] in
      var more = true
      while more {
        let found = audioFile.flatMap {
          PodcastEpisodeMaps.shared.skips(
            episode: episodeId, staged: $0, following: map.following)
        }
        let done = map.end(found)
        if done.changed {
          PodcastTimeline.mark(episodeId, "the Mac's map: \(map.ads.count) ads on this copy")
          persist()
        }
        more = done.more
      }
    }
  }
}
