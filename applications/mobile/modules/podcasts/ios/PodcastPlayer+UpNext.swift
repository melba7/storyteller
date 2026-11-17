// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Up Next in Swift. The queue (PodcastPlayback's UpNextQueue) is saved in Application Support
// after every change, so it survives a restart, and the player starts the next episode
// itself when one ends, with the screen locked and no JavaScript running.

import Foundation
import PodcastPlayback

enum UpNextFile {
  /// Next to the downloads' index, not inside any episode's folder.
  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("up-next.json")
  }
}

@MainActor
extension PodcastPlayer {
  // MARK: Starting the next one

  /// The loaded episode as a queue item, with where it is now, when it is playing.
  func playingItem() -> QueueItem? {
    guard var item = current, wantsToPlay || player.timeControlStatus == .playing else {
      return nil
    }
    item.position = position
    return item
  }

  /// Starts the first queued episode that can be played, from its saved place. Items with no
  /// file and no usable address are dropped. Returns whether one started.
  func startNextInQueue() -> Bool {
    var source: URL?
    let next = queue.takeNext { item in
      source = QueueSource.url(
        for: item, localFile: PodcastDownloader.shared.localFile(for: item.id))
      return source != nil
    }
    saveQueue()
    emitQueue()
    guard let next, let source else { return false }
    // JavaScript follows along: it loads this episode's details for the mini player.
    sink?("onPlaybackAdvanced", ["episodeId": next.id])
    begin(
      Episode(
        id: next.id, url: source, title: next.title, showTitle: next.showTitle,
        artworkUrl: next.artworkUrl, savedPosition: next.position, duration: next.duration,
        played: false, autoplay: true, type: next.type, showId: next.showId,
        chaptersUrl: next.chaptersUrl,
        // As the app asks when the listener plays an episode: through its own download while
        // Skip ads is on, so its ads can be skipped (PodcastPlayer+Stream.swift checks the rest).
        playThroughDownload: AdSkipDefaults.settings.skipAds))
    return true
  }

  // MARK: Changing the queue

  func upNextObjects() -> [[String: Any]] { queue.items.map(Self.object) }

  func addToUpNext(_ item: QueueItem, at place: QueuePlace) {
    queue.add(item, at: place, playingId: current?.id)
    changed()
  }

  func moveInUpNext(from: Int, to: Int) {
    queue.move(from: from, to: to)
    changed()
  }

  func removeFromUpNext(_ id: String) {
    queue.remove(id)
    changed()
  }

  func clearUpNext() {
    queue.clear()
    changed()
  }

  private func changed() {
    saveQueue()
    emitQueue()
  }

  func saveQueue() {
    do {
      try queue.save(to: UpNextFile.url)
    } catch {
      NSLog("Podcasts: Up Next could not be saved: \(error)")
    }
  }

  func emitQueue() {
    sink?("onUpNextChange", ["items": upNextObjects()])
  }

  static func object(_ item: QueueItem) -> [String: Any] {
    var object: [String: Any] = [
      "id": item.id, "url": item.url, "type": item.type, "title": item.title,
      "showTitle": item.showTitle, "position": item.position,
    ]
    if let artwork = item.artworkUrl { object["artworkUrl"] = artwork }
    if let duration = item.duration { object["duration"] = duration }
    if let showId = item.showId { object["showId"] = showId }
    if let chapters = item.chaptersUrl { object["chaptersUrl"] = chapters }
    return object
  }
}
