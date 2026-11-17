// LOFI-FORK: the podcast transcripts' plain values (see FORK.md). Foundation only.
import Foundation

/// One spoken word with its place in the audio, in seconds.
public struct TranscriptWord: Codable, Sendable, Equatable {
  public var text: String
  public var start: Double
  public var end: Double

  public init(text: String, start: Double, end: Double) {
    self.text = text
    self.start = start
    self.end = end
  }
}

/// A sentence or a breath of speech: what the player shows at once.
public struct TranscriptLine: Codable, Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var text: String

  public init(start: Double, end: Double, text: String) {
    self.start = start
    self.end = end
    self.text = text
  }
}

/// What identifies a transcript: the recogniser that made it and the audio it is of. A
/// transcript or a partial file made by another recogniser, language or file is not used.
public struct TranscriptIdentity: Codable, Sendable, Equatable {
  public var locale: String
  public var recogniser: String
  public var recogniserVersion: String
  public var osVersion: String
  public var sha256: String

  public init(
    locale: String, recogniser: String, recogniserVersion: String, osVersion: String, sha256: String
  ) {
    self.locale = locale
    self.recogniser = recogniser
    self.recogniserVersion = recogniserVersion
    self.osVersion = osVersion
    self.sha256 = sha256
  }
}

/// The finished transcript, saved as `<sha256>.transcript.json` next to the audio.
public struct Transcript: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var version: Int
  public var identity: TranscriptIdentity
  /// Seconds of audio.
  public var duration: Double
  public var lines: [TranscriptLine]
  public var words: [TranscriptWord]

  public init(
    identity: TranscriptIdentity, duration: Double, lines: [TranscriptLine], words: [TranscriptWord]
  ) {
    self.version = Self.currentVersion
    self.identity = identity
    self.duration = duration
    self.lines = lines
    self.words = words
  }
}

/// The words so far and the time reached, saved after each piece as
/// `<sha256>.transcript.partial.json`.
public struct PartialTranscript: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var version: Int
  public var identity: TranscriptIdentity
  public var duration: Double
  /// Seconds of audio that are done.
  public var reached: Double
  public var words: [TranscriptWord]

  public init(
    identity: TranscriptIdentity, duration: Double, reached: Double, words: [TranscriptWord]
  ) {
    self.version = Self.currentVersion
    self.identity = identity
    self.duration = duration
    self.reached = reached
    self.words = words
  }
}

/// Why an episode is not transcribed and will not be, saved as `<sha256>.transcript.skip.json`
/// so it is not tried again every time the app opens.
public struct TranscriptSkip: Codable, Sendable, Equatable {
  public var reason: String
  public var locale: String

  public init(reason: String, locale: String) {
    self.reason = reason
    self.locale = locale
  }
}

/// Where one episode's transcription is.
public enum TranscriptStatus: Sendable, Equatable {
  case waiting
  case transcribing(percent: Int)
  case done
  case notSupported(reason: String)
  case failed(reason: String)
}

/// Said by a recogniser when it cannot go on.
public enum TranscriptError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The language or the phone cannot be transcribed. Not tried again.
  case notSupported(String)
  /// Something went wrong that may not the next time.
  case failed(String)

  public var description: String {
    switch self {
    case .notSupported(let reason), .failed(let reason): return reason
    }
  }
}
