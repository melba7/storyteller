// LOFI-FORK: the file of the finder guard (see FinderGuard.swift for how to use it). Foundation
// only.
import Foundation

// MARK: The file

extension FinderGuard {
  /// The guard in `text`, made for `appBuild`. Text that is missing, too big, damaged or of an
  /// unknown version reads as an empty guard. Text from another build keeps the listener's
  /// answers but starts the marks and traps again: the new build may have fixed the crash.
  public static func read(_ text: String?, appBuild: String) -> FinderGuard {
    let build = name(appBuild)
    guard let text, text.utf8.count <= maxFileBytes,
      var file = try? JSONDecoder().decode(FinderGuard.self, from: Data(text.utf8)),
      file.version == currentVersion
    else { return FinderGuard(appBuild: build) }
    if file.appBuild != build {
      file.appBuild = build
      file.marks = []
      file.traps = [:]
      file.trapped = []
    }
    file.clamp()
    return file
  }

  /// The guard saved at `url`. A missing, unreadable or too big file reads as an empty guard.
  public static func load(from url: URL, appBuild: String) -> FinderGuard {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return FinderGuard(appBuild: name(appBuild))
    }
    defer { try? handle.close() }
    // One byte more than the limit is enough to know the file is too big, whatever its size.
    let data = (try? handle.read(upToCount: maxFileBytes + 1)) ?? Data()
    return read(String(data: data, encoding: .utf8), appBuild: appBuild)
  }

  /// The guard as the text of its file: one line of JSON with sorted keys. Answers that no
  /// longer count at `now` are left out.
  public func text(now: Date) -> String {
    var kept = self
    kept.prune(now: now)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(kept) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  /// Writes the file whole in one step (a half-written file is never seen), making its folder.
  public func save(to url: URL, now: Date) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text(now: now).utf8).write(to: url, options: .atomic)
  }
}
