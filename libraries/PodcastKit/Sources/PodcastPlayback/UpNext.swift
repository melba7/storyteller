// LOFI-FORK: the podcast player's Up Next rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// An episode in Up Next, with everything the player needs to start it without JavaScript.
public struct QueueItem: Sendable, Equatable, Codable {
  public var id: String
  /// The episode's audio address.
  public var url: String
  /// The feed's audio type (audio/mpeg, ...).
  public var type: String
  public var title: String
  public var showTitle: String
  public var artworkUrl: String?
  public var duration: Double?
  /// Where the listener left off, in seconds.
  public var position: Double
  /// The show the episode belongs to, for the show's settings (speed, intro, outro). Files
  /// saved before this existed have none.
  public var showId: String?
  /// The feed's JSON chapters file, so chapters work for the next episode with no JavaScript.
  /// Files saved before this existed have none.
  public var chaptersUrl: String?
  /// The show's language, so the next episode is transcribed in it when it plays through its
  /// own download. Files saved before this existed have none.
  public var language: String?

  public init(
    id: String, url: String, type: String = "", title: String, showTitle: String = "",
    artworkUrl: String? = nil, duration: Double? = nil, position: Double = 0, showId: String? = nil,
    chaptersUrl: String? = nil, language: String? = nil
  ) {
    self.id = id
    self.url = url
    self.type = type
    self.title = title
    self.showTitle = showTitle
    self.artworkUrl = artworkUrl
    self.duration = duration
    self.position = position
    self.showId = showId
    self.chaptersUrl = chaptersUrl
    self.language = language
  }
}

/// Where in the queue an added episode goes.
public enum QueuePlace: String, Sendable, Equatable, Codable {
  /// The top: it plays after the current episode.
  case next
  /// The bottom.
  case last
}

/// The episodes after the one playing now, in the order they will play. The playing episode
/// is never in it, and an episode is in it once.
public struct UpNextQueue: Sendable, Equatable, Codable {
  public private(set) var items: [QueueItem]

  public init(items: [QueueItem] = []) {
    var seen = Set<String>()
    self.items = items.filter { seen.insert($0.id).inserted }
  }

  public var isEmpty: Bool { items.isEmpty }

  public func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

  /// Puts an episode at the top or the bottom. One already queued moves (and takes the new
  /// details). The episode playing now is not queued.
  public mutating func add(_ item: QueueItem, at place: QueuePlace, playingId: String? = nil) {
    guard item.id != playingId else { return }
    items.removeAll { $0.id == item.id }
    switch place {
    case .next: items.insert(item, at: 0)
    case .last: items.append(item)
    }
  }

  /// Moves the item at `from` to `to`. Places outside the list are clamped.
  public mutating func move(from: Int, to: Int) {
    guard !items.isEmpty else { return }
    let last = items.count - 1
    let moved = items.remove(at: min(max(from, 0), last))
    items.insert(moved, at: min(max(to, 0), last))
  }

  public mutating func remove(_ id: String) {
    items.removeAll { $0.id == id }
  }

  public mutating func clear() { items = [] }

  /// An episode started playing, from a list, from the queue or from the lock screen: it is
  /// not "next" any more.
  public mutating func startedPlaying(_ id: String) { remove(id) }

  /// When an episode starts by the listener's choice while `previous` was playing, `previous`
  /// goes back to the top with its place, unless it had finished or is the same episode. The
  /// new episode leaves the queue.
  public mutating func startedFromList(
    _ id: String, previous: QueueItem?, previousFinished: Bool
  ) {
    startedPlaying(id)
    guard let previous, previous.id != id, !previousFinished else { return }
    add(previous, at: .next)
  }

  /// An episode ended: the first one that can be played comes off the queue. Items that cannot
  /// be played (no file and no usable address) are dropped on the way.
  public mutating func takeNext(canPlay: (QueueItem) -> Bool = { _ in true }) -> QueueItem? {
    while !items.isEmpty {
      let first = items.removeFirst()
      if canPlay(first) { return first }
    }
    return nil
  }

  // MARK: The file

  /// The queue saved in `file`. A missing or unreadable file is an empty queue.
  public static func load(from file: URL) -> UpNextQueue {
    guard let data = try? Data(contentsOf: file),
      let saved = try? JSONDecoder().decode(UpNextQueue.self, from: data)
    else { return UpNextQueue() }
    return UpNextQueue(items: saved.items)
  }

  public func save(to file: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: file, options: .atomic)
  }
}

/// Where a queued episode plays from.
public enum QueueSource {
  /// The downloaded file when there is one; otherwise the address, if it is a usable http or
  /// https link (a deleted download streams); otherwise nil, and the item is skipped.
  public static func url(for item: QueueItem, localFile: URL?) -> URL? {
    if let localFile { return localFile }
    guard let address = URL(string: item.url), let scheme = address.scheme?.lowercased(),
      scheme == "http" || scheme == "https", address.host != nil
    else { return nil }
    return address
  }
}
