// LOFI-FORK: the podcast downloads' bookkeeping values (see FORK.md). Plain values, no URLSession.
import Foundation

/// Where one episode's download is.
public enum DownloadState: Sendable, Equatable {
  case queued
  /// Bytes received so far, and the bytes expected when the server said.
  case downloading(bytes: Int64, expected: Int64?)
  case downloaded(file: String, sha256: String, bytes: Int64, date: Date)
  /// A short reason in plain words.
  case failed(reason: String)

  public var isActive: Bool {
    switch self {
    case .queued, .downloading: return true
    case .downloaded, .failed: return false
    }
  }
}

extension DownloadState: Codable {
  private enum Kind: String, Codable { case queued, downloading, downloaded, failed }

  private enum Keys: String, CodingKey {
    case kind, bytes, expected, file, sha256, date, reason
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .queued:
      self = .queued
    case .downloading:
      self = .downloading(
        bytes: try c.decode(Int64.self, forKey: .bytes),
        expected: try c.decodeIfPresent(Int64.self, forKey: .expected))
    case .downloaded:
      self = .downloaded(
        file: try c.decode(String.self, forKey: .file),
        sha256: try c.decode(String.self, forKey: .sha256),
        bytes: try c.decode(Int64.self, forKey: .bytes),
        date: try c.decode(Date.self, forKey: .date))
    case .failed:
      self = .failed(reason: try c.decode(String.self, forKey: .reason))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .queued:
      try c.encode(Kind.queued, forKey: .kind)
    case .downloading(let bytes, let expected):
      try c.encode(Kind.downloading, forKey: .kind)
      try c.encode(bytes, forKey: .bytes)
      try c.encodeIfPresent(expected, forKey: .expected)
    case .downloaded(let file, let sha256, let bytes, let date):
      try c.encode(Kind.downloaded, forKey: .kind)
      try c.encode(file, forKey: .file)
      try c.encode(sha256, forKey: .sha256)
      try c.encode(bytes, forKey: .bytes)
      try c.encode(date, forKey: .date)
    case .failed(let reason):
      try c.encode(Kind.failed, forKey: .kind)
      try c.encode(reason, forKey: .reason)
    }
  }
}

/// One episode's row in the index.
public struct DownloadEntry: Sendable, Equatable, Codable {
  public var episodeId: String
  /// The audio address it was asked to fetch.
  public var url: String
  /// The extension the file gets (mp3, m4a, ...), worked out when the download was asked for.
  public var fileExtension: String
  public var state: DownloadState
  public var updatedAt: Date
  /// Started by the app by itself (a new episode), not by the listener. These wait for Wi-Fi
  /// whatever the "Download only on Wi-Fi" switch says.
  public var automatic: Bool

  public init(
    episodeId: String, url: String, fileExtension: String, state: DownloadState,
    updatedAt: Date = Date(), automatic: Bool = false
  ) {
    self.episodeId = episodeId
    self.url = url
    self.fileExtension = fileExtension
    self.state = state
    self.updatedAt = updatedAt
    self.automatic = automatic
  }

  private enum Keys: String, CodingKey {
    case episodeId, url, fileExtension, state, updatedAt, automatic
  }

  /// An index written before automatic downloads has no `automatic`: it means false.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    self.init(
      episodeId: try c.decode(String.self, forKey: .episodeId),
      url: try c.decode(String.self, forKey: .url),
      fileExtension: try c.decode(String.self, forKey: .fileExtension),
      state: try c.decode(DownloadState.self, forKey: .state),
      updatedAt: try c.decode(Date.self, forKey: .updatedAt),
      automatic: try c.decodeIfPresent(Bool.self, forKey: .automatic) ?? false)
  }
}

/// What the index file holds.
struct DownloadIndex: Codable, Equatable {
  var version = 1
  var entries: [DownloadEntry] = []
}

public enum DownloadError: Error, Equatable, LocalizedError {
  case unsafeEpisodeId(String)
  case badHash(String)
  case badExtension(String)

  public var errorDescription: String? {
    switch self {
    case .unsafeEpisodeId(let id): return "\"\(id)\" is not a usable episode id."
    case .badHash(let hash): return "\"\(hash)\" is not a SHA-256 hash."
    case .badExtension(let ext): return "\"\(ext)\" is not a usable file extension."
    }
  }
}
