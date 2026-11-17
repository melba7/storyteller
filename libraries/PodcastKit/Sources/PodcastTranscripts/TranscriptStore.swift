// LOFI-FORK: the podcast transcripts' files (see FORK.md).
import Foundation

/// The transcript files of one downloaded episode, in its download folder next to the audio
/// (`<sha256>.transcript.json`, `.transcript.partial.json` and `.transcript.skip.json`).
/// Deleting the download deletes the folder, so they go with it.
public struct TranscriptStore: Sendable {
  public let folder: URL
  public let sha256: String

  public init(folder: URL, sha256: String) {
    self.folder = folder
    self.sha256 = sha256
  }

  public var transcriptURL: URL { folder.appendingPathComponent("\(sha256).transcript.json") }
  public var partialURL: URL { folder.appendingPathComponent("\(sha256).transcript.partial.json") }
  public var skipURL: URL { folder.appendingPathComponent("\(sha256).transcript.skip.json") }

  public var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  /// The finished transcript, or nil when there is none or it cannot be read.
  public func loadTranscript() -> Transcript? {
    guard let data = try? Data(contentsOf: transcriptURL),
      let transcript = try? JSONDecoder().decode(Transcript.self, from: data),
      transcript.version == Transcript.currentVersion
    else { return nil }
    return transcript
  }

  /// The transcript's JSON as saved, for the app to read.
  public func transcriptJSON() -> String? {
    guard loadTranscript() != nil, let data = try? Data(contentsOf: transcriptURL) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Saves the finished transcript and removes the partial file.
  public func finish(_ transcript: Transcript) throws {
    try Self.encoder.encode(transcript).write(to: transcriptURL, options: .atomic)
    try? FileManager.default.removeItem(at: partialURL)
  }

  public func savePartial(_ partial: PartialTranscript) throws {
    try Self.encoder.encode(partial).write(to: partialURL, options: .atomic)
  }

  /// The partial file. A file that cannot be read is removed and counts as none, so the
  /// transcription starts over.
  public func loadPartial() -> PartialTranscript? {
    guard let data = try? Data(contentsOf: partialURL) else { return nil }
    if let partial = try? JSONDecoder().decode(PartialTranscript.self, from: data) { return partial }
    try? FileManager.default.removeItem(at: partialURL)
    return nil
  }

  public func saveSkip(_ skip: TranscriptSkip) throws {
    try Self.encoder.encode(skip).write(to: skipURL, options: .atomic)
  }

  public func loadSkip() -> TranscriptSkip? {
    guard let data = try? Data(contentsOf: skipURL) else { return nil }
    return try? JSONDecoder().decode(TranscriptSkip.self, from: data)
  }

  /// Where the episode stands from its files alone: done, or waiting with the percent a
  /// partial file reached, or not supported when it was skipped.
  public func status() -> TranscriptStatus {
    if hasTranscript { return .done }
    if let skip = loadSkip() { return .notSupported(reason: skip.reason) }
    return .waiting
  }
}

/// The language each downloaded episode is to be transcribed in (the feed's), noted when the
/// download starts, because the downloader does not know the show. Saved as one small file.
public final class TranscriptLanguages: @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var languages: [String: String]

  public init(url: URL) {
    self.url = url
    if let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode([String: String].self, from: data)
    {
      languages = saved
    } else {
      languages = [:]
    }
  }

  public func language(for episodeId: String) -> String? {
    lock.withLock { languages[episodeId] }
  }

  /// Notes the language for an episode; an empty or missing one forgets it.
  public func note(_ language: String?, for episodeId: String) {
    lock.withLock {
      if let language, !language.isEmpty { languages[episodeId] = language } else { languages[episodeId] = nil }
      save()
    }
  }

  /// Forgets the episodes that are not in `keep` (their downloads are gone).
  public func prune(keeping keep: Set<String>) {
    lock.withLock {
      let before = languages.count
      languages = languages.filter { keep.contains($0.key) }
      if languages.count != before { save() }
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(languages) { try? data.write(to: url, options: .atomic) }
  }
}
