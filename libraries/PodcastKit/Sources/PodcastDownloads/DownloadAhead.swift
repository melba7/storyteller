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
  /// `started` is every episode this run of the app has already started ahead. Nothing starts
  /// off Wi-Fi, while the network is in Low Data Mode (`lowData`: the listener asked the phone to
  /// use less data, and an episode is 50 to 100 MB), or once an ahead download failed for lack of
  /// room (`phoneFull`), but the other two still happen, so a switch of network or of "Skip ads"
  /// never leaves files behind.
  ///
  /// The next episodes of Up Next that can be fetched, have "Skip ads" on and have no download
  /// of any kind (finished, moving, failed, the listener's own) start, but never so many that more
  /// than `count` ahead downloads exist at once. An ahead download that failed still counts while
  /// its episode is in Up Next, and is not tried again by this rule (the listener can tap it), so
  /// a run of failures never works through the queue. An episode in `started` is never started
  /// again, even when its file is gone (the listener deleted it), and while it is still in Up
  /// Next it keeps its place among the two, so the third in line is not fetched in its stead.
  public static func plan(
    upNext: [Item], playingId: String?, entries: [DownloadEntry], started: Set<String>,
    onWiFi: Bool, lowData: Bool, phoneFull: Bool
  ) -> Plan {
    let queued = Set(upNext.map(\.id))
    let marked = entries.filter(\.ahead)
    var plan = Plan()
    plan.adopt = marked.filter { $0.episodeId == playingId }.map(\.episodeId)
    plan.drop = marked.filter { $0.episodeId != playingId && !queued.contains($0.episodeId) }
      .map(\.episodeId)
    guard onWiFi, !lowData, !phoneFull else { return plan }

    var taken = Set(
      marked.filter { queued.contains($0.episodeId) && $0.episodeId != playingId }
        .map(\.episodeId))
    taken.formUnion(started.filter { queued.contains($0) && $0 != playingId })
    var room = max(0, count - taken.count)
    var have = Set(entries.map(\.episodeId))
    for item in upNext where room > 0 {
      guard item.id != playingId, !started.contains(item.id), item.skipAds, canFetch(item),
        have.insert(item.id).inserted
      else { continue }
      plan.start.append(item.id)
      room -= 1
    }
    return plan
  }

  /// Whether an ahead download failed because the phone had no room. The player remembers it
  /// for the rest of the run and passes it to `plan` as `phoneFull`.
  public static func phoneIsFull(in entries: [DownloadEntry]) -> Bool {
    entries.contains { entry in
      entry.ahead && entry.state == .failed(reason: DownloadRecovery.phoneFullReason)
    }
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
