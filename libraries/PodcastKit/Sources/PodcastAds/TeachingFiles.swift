// LOFI-FORK: the files the Mac's teaching run gives the phone (see FORK.md).
import Foundation

/// The files the Mac's teaching run gives the phone, kept in one folder of the app. They are the
/// Mac's own files: a show is named in them by its feed address, and `load` turns that into the
/// app's show id with a table.
public struct TeachingFiles: Sendable {
  public static let maxBytes = 5_000_000
  public var model: AdWordModel?
  public var seeds: KnownAds
  public var habits: ShowHabits
  public var local: LocalAds { LocalAds(model: model) }

  /// Nothing taught yet.
  public init() {
    model = nil
    seeds = KnownAds()
    habits = ShowHabits()
  }

  /// What the folder holds. A missing or unreadable file gives no model, no seeds, no habits.
  /// `shows` maps a feed key (`FeedKey.key`) to the app's show id. An ad of one show, or the
  /// habits of a show, whose feed is not in it is left out; an ad of every show is kept.
  public static func load(
    folder: URL, now: Date = Date(), shows: [String: String] = [:]
  ) -> TeachingFiles {
    var files = TeachingFiles()
    files.model = read(AdWordModel.fileName, in: folder).flatMap { AdWordModel(data: $0) }
    let showOf = MacFiles.table(shows)
    if let data = read(AdLibraryFile.fileName, in: folder) {
      files.seeds = MacFiles.library(data: data, now: now, showOf: showOf)
    }
    if let data = read(ShowHabits.fileName, in: folder),
      let habits = MacFiles.habits(data: data, showOf: showOf)
    {
      files.habits = habits
    }
    return files
  }

  private static func read(_ name: String, in folder: URL) -> Data? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
      data.count <= maxBytes
    else { return nil }
    return data
  }

  /// Whether `data` is a version 1 object that holds a list under `key`, which is all the phone
  /// asks of the library and the habits before it keeps them. Each entry is read leniently later.
  private static func isVersion1(_ data: Data, list key: String) -> Bool {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let version = root["version"] as? Int, version == 1, root[key] is [Any]
    else { return false }
    return true
  }

  /// Checks `data` and writes it as `name` in `folder`. False when the name is not one of the
  /// three files, the data is larger than `maxBytes`, or it is not what the Mac writes under that
  /// name (a version 1 file with the right list). A refused file leaves the old one in place.
  public static func install(name: String, data: Data, folder: URL) -> Bool {
    guard data.count <= maxBytes else { return false }
    switch name {
    case AdWordModel.fileName:
      guard AdWordModel(data: data) != nil else { return false }
    case AdLibraryFile.fileName:
      guard isVersion1(data, list: "ads") else { return false }
    case ShowHabits.fileName:
      guard isVersion1(data, list: "shows") else { return false }
    default:
      return false
    }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: folder.appendingPathComponent(name), options: .atomic)
      return true
    } catch {
      return false
    }
  }

  // MARK: The model's numbers

  /// What the model's file says about how it was trained. Any of it may be missing.
  public struct ModelInfo: Sendable, Equatable {
    public var writtenAt: Double?
    public var episodes: Int?
    /// How well it found ads of any sort in the episodes it never trained on.
    public var precision: Double?
    public var recall: Double?

    public init(
      writtenAt: Double? = nil, episodes: Int? = nil, precision: Double? = nil, recall: Double? = nil
    ) {
      self.writtenAt = writtenAt
      self.episodes = episodes
      self.precision = precision
      self.recall = recall
    }
  }

  /// The numbers in the model file's `trained` part. Nil when the data is not a JSON object.
  public static func modelInfo(data: Data) -> ModelInfo? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    guard let trained = root["trained"] as? [String: Any] else { return ModelInfo() }
    let any = ((trained["heldOut"] as? [String: Any])?["anyAd"]) as? [String: Any]
    func number(_ value: Any?) -> Double? {
      // Whole numbers come as Int on Linux and any number as NSNumber on Apple systems.
      if let whole = value as? Int { return Double(whole) }
      guard let found = value as? Double, found.isFinite else { return nil }
      return found
    }
    return ModelInfo(
      writtenAt: number(trained["writtenAt"]),
      episodes: number(trained["episodes"]).flatMap { Int(exactly: $0) },
      precision: number(any?["precision"]), recall: number(any?["recall"]))
  }

  /// The numbers of the model installed in `folder`, or nil when there is none.
  public static func modelInfo(in folder: URL) -> ModelInfo? {
    read(AdWordModel.fileName, in: folder).flatMap { modelInfo(data: $0) }
  }
}
