// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Searches the words spoken in every finished transcript on the phone. The rules are
// PodcastTranscripts' TranscriptSearch; this reads the files and shapes the answer for the app.

import Foundation
import PodcastDownloads
import PodcastTranscripts

extension PodcastTranscriber {
  /// The hits for `query`, one object per hit with the episode's id, the line's start in
  /// seconds, its text and the lines before and after. Reads the files on a background
  /// thread, not the caller's.
  func search(_ query: String) async -> [[String: Any]] {
    await Task.detached(priority: .userInitiated) { [self] in searchNow(query) }.value
  }

  private func searchNow(_ query: String) -> [[String: Any]] {
    guard let downloads = PodcastDownloader.shared.store else { return [] }
    var episodes: [(id: String, lines: [TranscriptLine])] = []
    for info in all() {
      guard info["state"] as? String == "done", let id = info["episodeId"] as? String,
        let entry = downloads.entry(for: id),
        case .downloaded(_, let sha, _, _) = entry.state,
        let folder = try? downloads.folder(for: id),
        let transcript = TranscriptStore(folder: folder, sha256: sha).loadTranscript()
      else { continue }
      episodes.append((id: id, lines: transcript.lines))
    }
    var found: [[String: Any]] = []
    for episode in TranscriptSearch.search(query, episodes: episodes) {
      for hit in episode.hits {
        found.append([
          "episodeId": episode.episodeId, "seconds": hit.start, "text": hit.text,
          "before": hit.before, "after": hit.after,
        ])
      }
    }
    return found
  }
}
