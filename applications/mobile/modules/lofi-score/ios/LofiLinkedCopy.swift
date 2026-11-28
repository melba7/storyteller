// LOFI-FORK: the Storyteller Lofi fork's native module (see FORK.md).
//
// Copies one big file (an episode's audio the Mac prepared) out of the linked sounds folder to a
// place of the app's own. It is made like `LinkedFolderFile.fetch`, which reads small text files:
// the folder is opened through its bookmark, the path may not leave the folder, and a file iCloud
// has not put on the phone yet is asked for and reported as `waiting`, never waited for. After a
// good copy the iCloud download is given back, so the audio is not kept twice.

import Foundation
import LofiScoreHost

enum LinkedFolderCopy {
  enum Outcome: Equatable {
    case copied(bytes: Int64)
    /// iCloud has the file and has been asked for it; it is not on the phone yet.
    case waiting
    case missing
    case notLinked
    case folderGone
    case unreadable(String)
  }

  /// Copies the file at `path` below the linked folder to `destination`, replacing what is there.
  /// Runs on a background queue: a copy of 50 MB takes a while.
  static func copy(_ path: String, to destination: URL) async -> Outcome {
    guard let bookmark = AtmosphereSettings().linkedFolderBookmark else { return .notLinked }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        guard let folder = try? FolderBookmark.resolve(bookmark) else {
          return continuation.resume(returning: .folderGone)
        }
        continuation.resume(returning: copy(path, to: destination, in: folder))
      }
    }
  }

  static func copy(
    _ path: String, to destination: URL, in folder: URL, fileManager: FileManager = .default
  ) -> Outcome {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty, !path.hasPrefix("/"),
      !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else { return .unreadable("The file's path is not allowed.") }
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
    var isFolder: ObjCBool = false
    guard fileManager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue
    else { return .folderGone }
    let file = parts.reduce(folder) { $0.appendingPathComponent($1) }
    guard fileManager.fileExists(atPath: file.path) else {
      let stub = file.deletingLastPathComponent().appendingPathComponent(
        ".\(file.lastPathComponent).icloud")
      guard fileManager.fileExists(atPath: stub.path) else { return .missing }
      try? fileManager.startDownloadingUbiquitousItem(at: file)
      return .waiting
    }
    // A link inside the folder that leads out of it is not followed.
    let inside = folder.resolvingSymlinksInPath().path + "/"
    guard file.resolvingSymlinksInPath().path.hasPrefix(inside) else {
      return .unreadable("The file's path is not allowed.")
    }
    // A file that shows under its own name but is not up to date on the phone (a placeholder, or
    // still downloading) would make the read below wait for iCloud: it is asked for and left for
    // the next run.
    let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
      .ubiquitousItemDownloadingStatus
    if let status, status != .current {
      try? fileManager.startDownloadingUbiquitousItem(at: file)
      return .waiting
    }
    try? fileManager.removeItem(at: destination)
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(
      readingItemAt: file, options: [.withoutChanges], error: &coordinationError
    ) { url in
      do { try fileManager.copyItem(at: url, to: destination) } catch { copyError = error }
    }
    if let error = coordinationError ?? copyError {
      try? fileManager.removeItem(at: destination)
      return .unreadable(error.localizedDescription)
    }
    guard let size = (try? fileManager.attributesOfItem(atPath: destination.path))?[.size] as? Int64
    else {
      try? fileManager.removeItem(at: destination)
      return .unreadable("The copy can't be read.")
    }
    // The copy is the phone's now: iCloud may take its own download back. A failure of this
    // (the file is not an iCloud item, or iCloud is busy) changes nothing.
    try? fileManager.evictUbiquitousItem(at: file)
    return .copied(bytes: size)
  }
}
