// LOFI-FORK: the files the Mac's teaching run gives the phone (see FORK.md).
import Foundation

/// The files the Mac's teaching run gives the phone, kept in one folder of the app.
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
  public static func load(folder: URL, now: Date = Date()) -> TeachingFiles {
    var files = TeachingFiles()
    files.model = read(AdWordModel.fileName, in: folder).flatMap { AdWordModel(data: $0) }
    if let data = read(AdLibraryFile.fileName, in: folder) {
      files.seeds = AdLibrary.seeds(from: data, now: now)
    }
    if let data = read(ShowHabits.fileName, in: folder), let habits = ShowHabits(data: data) {
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

  /// Checks `data` and writes it as `name` in `folder`. False when the name is not one of the
  /// three files, the data is larger than `maxBytes`, or it does not read as that file. A refused
  /// file leaves the old one in place.
  public static func install(name: String, data: Data, folder: URL) -> Bool {
    guard data.count <= maxBytes else { return false }
    switch name {
    case AdWordModel.fileName:
      guard AdWordModel(data: data) != nil else { return false }
    case AdLibraryFile.fileName:
      guard let file = try? JSONDecoder().decode(AdLibraryFile.self, from: data),
        file.version == AdLibraryFile.currentVersion
      else { return false }
    case ShowHabits.fileName:
      guard ShowHabits(data: data) != nil else { return false }
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
}
