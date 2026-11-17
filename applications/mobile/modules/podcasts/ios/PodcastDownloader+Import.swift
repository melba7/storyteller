// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Audio files the listener adds from the Files app. A file is copied into the app, hashed and
// installed exactly like a finished download (`<episodeId>/<sha256>.<ext>`, an entry that says
// downloaded), so playing offline, Up Next, the transcript, ad finding and chapters all work
// on it without knowing where it came from. The naming rules are PodcastKit's AudioImport.
import AVFoundation
import Foundation
import PodcastDownloads

extension PodcastDownloader {
  /// Copies the picked file in and installs it. A file that is already installed (the same
  /// bytes) is left alone, so its transcript and ad finding are kept. Returns what the
  /// library needs to make the episode: its id, title, length, size and extension.
  func importAudioFile(uri: String, fileName: String?) async throws -> [String: Any] {
    guard let store else { throw PodcastFetchError(message: "Downloads are not available.") }
    let source = Self.fileURL(from: uri)
    let name = fileName ?? source.lastPathComponent
    guard let ext = AudioImport.fileExtension(fileName: name) else {
      throw PodcastFetchError(message: "This isn't an audio file the app can play.")
    }
    let (entry, isNew) = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(
          with: Result { try Self.copyAndInstall(source, fileExtension: ext, into: store) })
      }
    }
    if isNew {
      emit(entry)
      PodcastTranscriber.shared.downloaded(entry.episodeId)
    }
    guard case .downloaded(_, _, let bytes, _) = entry.state,
      let file = store.localFile(for: entry.episodeId)
    else { throw PodcastFetchError(message: "The file couldn't be added.") }
    let details = await Self.details(of: file)
    var object: [String: Any] = [
      "episodeId": entry.episodeId,
      "title": AudioImport.title(fileName: name, tagTitle: details.title),
      "bytes": Double(bytes),
      "fileExtension": ext,
    ]
    if let seconds = details.seconds { object["durationSeconds"] = seconds }
    return object
  }

  private static func fileURL(from uri: String) -> URL {
    if let url = URL(string: uri), url.isFileURL { return url }
    return URL(fileURLWithPath: uri)
  }

  /// The slow part, on a background queue: copy, hash and move into place.
  private static func copyAndInstall(
    _ source: URL, fileExtension ext: String, into store: DownloadStore
  ) throws -> (DownloadEntry, Bool) {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    let fm = FileManager.default
    let copy = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    try fm.copyItem(at: source, to: copy)
    do {
      let hash = try FileHash.sha256(of: copy)
      let bytes = (try fm.attributesOfItem(atPath: copy.path)[.size] as? Int64) ?? 0
      guard let id = AudioImport.episodeId(sha256: hash) else {
        throw PodcastFetchError(message: "The file couldn't be read.")
      }
      if let have = store.entry(for: id), AudioImport.isInstalled(have, sha256: hash),
        store.localFile(for: id) != nil
      {
        try? fm.removeItem(at: copy)
        return (have, false)
      }
      let staged = try store.stage(copy, episodeId: id)
      let done = try store.install(
        episodeId: id, staged: staged, sha256: hash, fileExtension: ext, bytes: bytes)
      return (done, true)
    } catch {
      try? fm.removeItem(at: copy)
      throw error
    }
  }

  /// The title from the file's tag (ID3 or M4A) and its length. Either may be missing.
  private static func details(of file: URL) async -> (title: String?, seconds: Double?) {
    let asset = AVURLAsset(url: file)
    var title: String?
    if let items = try? await asset.load(.commonMetadata) {
      let found = AVMetadataItem.metadataItems(
        from: items, filteredByIdentifier: .commonIdentifierTitle)
      if let item = found.first { title = try? await item.load(.stringValue) }
    }
    var seconds: Double?
    if let duration = try? await asset.load(.duration), duration.isNumeric {
      let value = CMTimeGetSeconds(duration)
      if value.isFinite, value > 0 { seconds = value }
    }
    return (title, seconds)
  }
}
