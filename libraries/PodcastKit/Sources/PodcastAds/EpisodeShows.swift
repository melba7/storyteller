// LOFI-FORK: which show each episode is of (see FORK.md).
//
// The ad finder and the head scan know an episode by its id, and the ads they remember are
// remembered by show. The player notes the show when it loads an episode, and this keeps the
// notes in one small file (`episode-shows.json`): the newest 500, in the order they were noted.
import Foundation

public final class EpisodeShows: @unchecked Sendable {
  public static let fileName = "episode-shows.json"
  public static let most = 500

  private struct Note: Codable, Equatable {
    var episode: String
    var show: String
  }

  private let url: URL
  private let lock = NSLock()
  private var notes: [Note]

  public init(url: URL) {
    self.url = url
    if let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode([Note].self, from: data)
    {
      notes = Array(saved.suffix(Self.most))
    } else {
      notes = []
    }
  }

  public var count: Int { lock.withLock { notes.count } }

  public func show(for episodeId: String) -> String? {
    lock.withLock { notes.last { $0.episode == episodeId }?.show }
  }

  /// Notes the show of an episode, as the newest note. A missing or empty show leaves what was
  /// noted alone, so a start that does not know the show never erases it.
  public func remember(_ show: String?, for episodeId: String) {
    guard let show, !show.isEmpty else { return }
    lock.withLock {
      notes.removeAll { $0.episode == episodeId }
      notes.append(Note(episode: episodeId, show: show))
      if notes.count > Self.most { notes.removeFirst(notes.count - Self.most) }
      // The folder may not exist yet (the first note of a new install), as in KnownAds.save.
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let data = try? JSONEncoder().encode(notes) { try? data.write(to: url, options: .atomic) }
    }
  }
}
