// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Bookmarks made with the headphones' next button, which must work with the screen locked and
// no JavaScript running. The player appends each one to `Podcasts/pending-bookmarks.json`
// (PodcastPlayback's PendingBookmarks, which holds the rules and is tested). The app imports
// the file into its database when it runs (`readPendingBookmarks`), then takes out the ones it
// saved (`removePendingBookmarks`), so a failed import loses nothing.

import Foundation
import PodcastPlayback
import UIKit

enum PendingBookmarksStore {
  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("pending-bookmarks.json")
  }
}

@MainActor
extension PodcastPlayer {
  /// The next button, when the listener chose "bookmark": notes the place playing now.
  func bookmarkFromHeadphones() {
    guard let episode = current, PendingBookmarks.canBookmark(episodeId: episode.id) else { return }
    let bookmark = PendingBookmark(
      id: UUID().uuidString, episodeId: episode.id, positionSeconds: position,
      createdAt: (Date().timeIntervalSince1970 * 1000).rounded())
    do {
      try PendingBookmarks.append(bookmark, to: PendingBookmarksStore.url)
    } catch {
      NSLog("Podcasts: the bookmark could not be saved: \(error)")
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      return
    }
    // A tap on the phone, for the listener holding it. The app hears too if it is running.
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    sink?("onBookmarksPending", [:])
  }

  /// The bookmarks waiting in the file, as JSON text. Run on the main actor like the append,
  /// so the two never overlap.
  static func readPendingBookmarks() -> String {
    PendingBookmarks.json(from: PendingBookmarksStore.url)
  }

  /// Takes the bookmarks the app has saved out of the file.
  static func removePendingBookmarks(ids: [String]) throws {
    try PendingBookmarks.remove(ids: Set(ids), from: PendingBookmarksStore.url)
  }
}
