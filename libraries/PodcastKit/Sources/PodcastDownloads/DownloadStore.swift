// LOFI-FORK: the podcast downloads' files and index (see FORK.md).
//
// The store owns one folder: `<root>/<episodeId>/<sha256>.<ext>` for each downloaded
// episode (its side files, such as `<sha256>.transcript.json`, sit next to it), an
// `index.json` with every episode's state, and `.incoming` where a finished download waits
// while it is hashed. Everything is synchronous, because URLSession deletes its temporary
// file the moment the delegate method returns.
import Foundation

public final class DownloadStore: @unchecked Sendable {
  public let root: URL
  private let lock = NSLock()
  private var index = DownloadIndex()

  private var indexURL: URL { root.appendingPathComponent("index.json") }
  private var incomingURL: URL { root.appendingPathComponent(".incoming", isDirectory: true) }

  /// Opens the store in `root`, making the folder if needed and reading the index. An index
  /// that cannot be read is set aside as `index.corrupt.json` and the store starts empty.
  public init(root: URL) throws {
    self.root = root
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try? fm.removeItem(at: incomingURL)
    if let data = try? Data(contentsOf: indexURL) {
      if let loaded = try? Self.decoder.decode(DownloadIndex.self, from: data) {
        index = loaded
      } else {
        let aside = root.appendingPathComponent("index.corrupt.json")
        try? fm.removeItem(at: aside)
        try? fm.moveItem(at: indexURL, to: aside)
      }
    }
  }

  // MARK: Reading

  public func entries() -> [DownloadEntry] {
    lock.withLock { index.entries }
  }

  public func entry(for episodeId: String) -> DownloadEntry? {
    lock.withLock { index.entries.first { $0.episodeId == episodeId } }
  }

  /// The sum of the downloaded files' bytes. Downloads still moving do not count.
  public func storageUsed() -> Int64 {
    lock.withLock {
      index.entries.reduce(0) { total, entry in
        if case .downloaded(_, _, let bytes, _) = entry.state { return total + bytes }
        return total
      }
    }
  }

  /// The folder for an episode. Throws for an id that is not a safe folder name.
  public func folder(for episodeId: String) throws -> URL {
    guard DownloadFile.isSafeEpisodeId(episodeId) else {
      throw DownloadError.unsafeEpisodeId(episodeId)
    }
    return root.appendingPathComponent(episodeId, isDirectory: true)
  }

  /// The downloaded audio file, or nil when the episode has none (or the file is gone).
  public func localFile(for episodeId: String) -> URL? {
    guard let folder = try? folder(for: episodeId) else { return nil }
    return lock.withLock {
      guard let entry = index.entries.first(where: { $0.episodeId == episodeId }),
        case .downloaded(let file, _, _, _) = entry.state
      else { return nil }
      let url = folder.appendingPathComponent(file)
      return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
  }

  // MARK: Changing

  /// Adds or replaces an episode's entry and saves the index.
  public func put(_ entry: DownloadEntry) throws {
    _ = try folder(for: entry.episodeId)
    try lock.withLock {
      replace(entry)
      try save()
    }
  }

  /// Notes how far a download has come. Kept in memory only (it changes all the time); the
  /// index file is written when a download starts, finishes or fails. Does nothing for an
  /// episode that is not moving, and returns the entry as it now stands.
  @discardableResult
  public func updateProgress(episodeId: String, bytes: Int64, expected: Int64?) -> DownloadEntry? {
    lock.withLock {
      guard let at = index.entries.firstIndex(where: { $0.episodeId == episodeId }),
        index.entries[at].state.isActive
      else { return nil }
      index.entries[at].state = .downloading(bytes: bytes, expected: expected)
      index.entries[at].updatedAt = Date()
      return index.entries[at]
    }
  }

  /// Marks an episode failed, keeping the address and extension so it can try again.
  @discardableResult
  public func markFailed(episodeId: String, reason: String) throws -> DownloadEntry? {
    try lock.withLock {
      guard let at = index.entries.firstIndex(where: { $0.episodeId == episodeId }) else {
        return nil
      }
      index.entries[at].state = .failed(reason: reason)
      index.entries[at].updatedAt = Date()
      try save()
      return index.entries[at]
    }
  }

  /// Takes the "ahead" mark, and the mark of a copy taken only for the list, off an episode's
  /// entry: it is being played or the listener asked for it, so it is theirs now. Done inside the
  /// store's lock, so it cannot undo a progress report that arrives at the same time. Returns the
  /// entry as it now stands, or nil when it had neither mark (or was not there).
  @discardableResult
  public func clearAhead(episodeId: String) throws -> DownloadEntry? {
    try lock.withLock {
      guard let at = index.entries.firstIndex(where: { $0.episodeId == episodeId }),
        index.entries[at].ahead || index.entries[at].copyForList
      else { return nil }
      index.entries[at].ahead = false
      index.entries[at].copyForList = false
      try save()
      return index.entries[at]
    }
  }

  /// Moves the file URLSession finished into `.incoming`, on the same volume, so the move is
  /// a rename. Call it before the delegate method returns.
  public func stage(_ temporary: URL, episodeId: String) throws -> URL {
    _ = try folder(for: episodeId)
    let fm = FileManager.default
    try fm.createDirectory(at: incomingURL, withIntermediateDirectories: true)
    let staged = incomingURL.appendingPathComponent("\(episodeId)-\(UUID().uuidString)")
    try fm.moveItem(at: temporary, to: staged)
    return staged
  }

  /// A new empty file in `.incoming`, for a download that is written there as it arrives. It is
  /// on the same volume as the episode's folder, so `install` can still file it with a rename.
  public func newStagingFile(episodeId: String) throws -> URL {
    _ = try folder(for: episodeId)
    let fm = FileManager.default
    try fm.createDirectory(at: incomingURL, withIntermediateDirectories: true)
    let staged = incomingURL.appendingPathComponent("\(episodeId)-\(UUID().uuidString)")
    guard fm.createFile(atPath: staged.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return staged
  }

  /// Puts a staged, hashed file in place as `<root>/<episodeId>/<sha256>.<ext>` and marks the
  /// episode downloaded. An older download of the same episode is removed first, with its side
  /// files (a new file is a new identity). With `requireEntry` (a finished download) nothing is
  /// filed when the episode was removed meanwhile: the staged file is deleted and it throws.
  @discardableResult
  public func install(
    episodeId: String, staged: URL, sha256: String, fileExtension: String, bytes: Int64,
    date: Date = Date(), requireEntry: Bool = false
  ) throws -> DownloadEntry {
    let folder = try folder(for: episodeId)
    guard DownloadFile.isSha256(sha256) else { throw DownloadError.badHash(sha256) }
    guard DownloadFile.isSafeExtension(fileExtension) else {
      throw DownloadError.badExtension(fileExtension)
    }
    let name = DownloadFile.name(sha256: sha256, fileExtension: fileExtension)
    return try lock.withLock {
      let fm = FileManager.default
      if requireEntry, !index.entries.contains(where: { $0.episodeId == episodeId }) {
        try? fm.removeItem(at: staged)
        throw DownloadError.noEntry(episodeId)
      }
      try? fm.removeItem(at: folder)
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
      try fm.moveItem(at: staged, to: folder.appendingPathComponent(name))
      let previous = index.entries.first { $0.episodeId == episodeId }
      let entry = DownloadEntry(
        episodeId: episodeId, url: previous?.url ?? "", fileExtension: fileExtension,
        state: .downloaded(file: name, sha256: sha256, bytes: bytes, date: date), updatedAt: date,
        automatic: previous?.automatic ?? false, ahead: previous?.ahead ?? false,
        copyForList: previous?.copyForList ?? false)
      replace(entry)
      try save()
      return entry
    }
  }

  /// Removes the episode's whole folder (the audio and every side file) and its entry.
  /// Returns whether there was anything to remove.
  @discardableResult
  public func delete(episodeId: String) throws -> Bool {
    let folder = try folder(for: episodeId)
    return try lock.withLock {
      let fm = FileManager.default
      let hadFolder = fm.fileExists(atPath: folder.path)
      if hadFolder { try fm.removeItem(at: folder) }
      let before = index.entries.count
      index.entries.removeAll { $0.episodeId == episodeId }
      let hadEntry = index.entries.count != before
      if hadEntry { try save() }
      return hadFolder || hadEntry
    }
  }

  /// Applies `Relaunch`'s rule after the app starts, given the episodes that still have a
  /// URLSession task. Entries that lost their task are marked failed, unfinished play-through
  /// ones are removed; the ones to start again are returned.
  public func reconcile(liveEpisodeIds: Set<String>) throws -> [DownloadEntry] {
    try lock.withLock {
      let plan = Relaunch.plan(entries: index.entries, liveEpisodeIds: liveEpisodeIds)
      var restart: [DownloadEntry] = []
      var dropped: [String] = []
      for at in index.entries.indices {
        let entry = index.entries[at]
        switch plan[entry.episodeId] ?? .keep {
        case .keep: break
        case .restart: restart.append(entry)
        case .drop: dropped.append(entry.episodeId)
        case .fail(let reason):
          index.entries[at].state = .failed(reason: reason)
          index.entries[at].updatedAt = Date()
        }
      }
      for id in dropped {
        index.entries.removeAll { $0.episodeId == id }
        if let folder = try? folder(for: id) { try? FileManager.default.removeItem(at: folder) }
      }
      try save()
      return restart
    }
  }

  // MARK: The index file

  private func replace(_ entry: DownloadEntry) {
    if let at = index.entries.firstIndex(where: { $0.episodeId == entry.episodeId }) {
      index.entries[at] = entry
    } else {
      index.entries.append(entry)
    }
  }

  private func save() throws {
    index.entries.sort { $0.episodeId < $1.episodeId }
    try Self.encoder.encode(index).write(to: indexURL, options: .atomic)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
