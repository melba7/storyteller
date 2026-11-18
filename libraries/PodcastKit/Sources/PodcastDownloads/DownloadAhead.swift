// LOFI-FORK: downloading what is next in Up Next ahead of time (see FORK.md).
//
// With "Skip ads" on, an episode is checked for ads from its file, so one that is already
// downloaded when it comes up can skip its first ad at 0:00. These are the rules for which
// episodes in Up Next the app fetches by itself, on Wi-Fi, as a new episode's automatic
// download, and which of those fetches it takes back. Plain values; the player reads the
// queue, the index and the network and acts on the answer (PodcastDownloadAhead).
import Foundation

public enum DownloadAhead {
  /// At most this many episodes are fetched ahead at one time. They are about 50 to 100 MB each.
  public static let count = 2

  /// One episode in Up Next.
  public struct Item: Sendable, Equatable {
    public var id: String
    /// The episode's audio address.
    public var url: String
    /// "Skip ads" is on for the episode's show (its own choice, else the listener's). There is
    /// nothing to gain from a file in advance otherwise.
    public var skipAds: Bool

    public init(id: String, url: String, skipAds: Bool) {
      self.id = id
      self.url = url
      self.skipAds = skipAds
    }
  }

  /// What to do now, as episode ids.
  public struct Plan: Sendable, Equatable {
    /// Episodes to download ahead, in Up Next's order.
    public var start: [String]
    /// Ahead downloads of the episode that is playing now: it is the listener's from here on, so
    /// the mark comes off and the ordinary rules for a played download apply.
    public var adopt: [String]
    /// Ahead downloads whose episode is no longer in Up Next and was never started: they are
    /// deleted, or cancelled while they are still moving.
    public var drop: [String]

    public init(start: [String] = [], adopt: [String] = [], drop: [String] = []) {
      self.start = start
      self.adopt = adopt
      self.drop = drop
    }
  }

  /// The plan for this moment. `upNext` is the queue after the playing episode, in order.
  /// Nothing starts off Wi-Fi, but the other two still happen, so a switch of network or of
  /// "Skip ads" never leaves files behind.
  ///
  /// The next episodes of Up Next that can be fetched, have "Skip ads" on and have no download
  /// of any kind (finished, moving, failed, the listener's own) start, but never so many that more
  /// than `count` ahead downloads exist at once. An ahead download that failed does not count and
  /// is not tried again by this rule: the listener can tap it.
  public static func plan(
    upNext: [Item], playingId: String?, entries: [DownloadEntry], onWiFi: Bool
  ) -> Plan {
    let queued = Set(upNext.map(\.id))
    let marked = entries.filter(\.ahead)
    var plan = Plan()
    plan.adopt = marked.filter { $0.episodeId == playingId }.map(\.episodeId)
    plan.drop = marked.filter { $0.episodeId != playingId && !queued.contains($0.episodeId) }
      .map(\.episodeId)
    guard onWiFi else { return plan }

    let alive = marked.filter { entry in
      queued.contains(entry.episodeId) && entry.episodeId != playingId && !isFailed(entry)
    }
    var room = max(0, count - alive.count)
    var have = Set(entries.map(\.episodeId))
    for item in upNext where room > 0 {
      guard item.id != playingId, item.skipAds, canFetch(item), have.insert(item.id).inserted
      else { continue }
      plan.start.append(item.id)
      room -= 1
    }
    return plan
  }

  private static func isFailed(_ entry: DownloadEntry) -> Bool {
    if case .failed = entry.state { return true }
    return false
  }

  /// Not an added file or a preview, a usable folder name, and a web address.
  private static func canFetch(_ item: Item) -> Bool {
    guard DownloadFile.isSafeEpisodeId(item.id), !item.id.hasPrefix(AudioImport.idPrefix),
      let url = URL(string: item.url), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty
    else { return false }
    return true
  }
}
