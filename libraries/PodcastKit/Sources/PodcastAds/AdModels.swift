// LOFI-FORK: the podcast ad finder's plain values (see FORK.md). Foundation only.
import Foundation

/// What a stretch of speech is.
public enum AdKind: String, Codable, Sendable, Equatable {
  /// A sponsor read, a produced ad, or a promo for another show.
  case ad
  /// The hosts promoting their own things (Patreon, merch, their other shows).
  case ownPlug
}

/// How sure the detector is. Sure and unsure ads are skipped (the listener can undo a skip) and
/// guesses are dropped by the clean-up.
public enum AdConfidence: String, Codable, Sendable, Equatable, Comparable {
  case guess
  case unsure
  case sure

  private var rank: Int {
    switch self {
    case .guess: return 0
    case .unsure: return 1
    case .sure: return 2
    }
  }

  public static func < (a: AdConfidence, b: AdConfidence) -> Bool { a.rank < b.rank }
}

/// A transcript line with its number (counted from 1 over the whole transcript), so a
/// detector can name lines and never has to copy a time.
public struct NumberedLine: Sendable, Equatable {
  public var number: Int
  public var start: Double
  public var end: Double
  public var text: String

  public init(number: Int, start: Double, end: Double, text: String) {
    self.number = number
    self.start = start
    self.end = end
    self.text = text
  }

  /// The line as the detector reads it: "[12] text".
  public var prompt: String { "[\(number)] \(text)" }
}

/// A run of numbered lines that fits one request to a detector.
public struct TranscriptPiece: Sendable, Equatable {
  public var lines: [NumberedLine]

  public init(lines: [NumberedLine]) { self.lines = lines }

  public var firstNumber: Int { lines.first?.number ?? 0 }
  public var lastNumber: Int { lines.last?.number ?? 0 }
  public var start: Double { lines.first?.start ?? 0 }
  public var end: Double { lines.last?.end ?? 0 }

  /// The lines, one to a row, as sent to the detector.
  public var prompt: String { lines.map(\.prompt).joined(separator: "\n") }
}

/// What a detector says about a piece: a run of lines (both ends included) that is an ad.
public struct AdRange: Codable, Sendable, Equatable {
  public var startLine: Int
  public var endLine: Int
  public var advertiser: String
  public var kind: AdKind
  public var confidence: AdConfidence

  public init(
    startLine: Int, endLine: Int, advertiser: String, kind: AdKind, confidence: AdConfidence
  ) {
    self.startLine = startLine
    self.endLine = endLine
    self.advertiser = advertiser
    self.kind = kind
    self.confidence = confidence
  }
}

/// One ad in an episode after the clean-up, in seconds of audio.
public struct FoundAd: Codable, Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var kind: AdKind
  public var advertiser: String
  public var confidence: AdConfidence
  /// The first words of the ad, to recognise it in a list.
  public var firstWords: String

  public init(
    start: Double, end: Double, kind: AdKind, advertiser: String, confidence: AdConfidence,
    firstWords: String
  ) {
    self.start = start
    self.end = end
    self.kind = kind
    self.advertiser = advertiser
    self.confidence = confidence
    self.firstWords = firstWords
  }

  public var duration: Double { end - start }
}

/// Why this phone or Mac cannot find ads (yet).
public enum AdUnavailable: Sendable, Equatable {
  case appleIntelligenceOff
  case modelDownloading
  case deviceNotEligible
  /// The system is older than iOS 26 or macOS 26.
  case systemTooOld
  case other(String)

  /// The words shown to the listener.
  public var reason: String {
    switch self {
    case .appleIntelligenceOff: return "Apple Intelligence is off"
    case .modelDownloading: return "The model is downloading"
    case .deviceNotEligible: return "This iPhone can't run Apple Intelligence"
    case .systemTooOld: return "Needs iOS 26"
    case .other(let text): return text
    }
  }

  /// Whether waiting is enough (the model is downloading), as opposed to the listener having
  /// to change something or the device never being able to.
  public var passesByItself: Bool { self == .modelDownloading }
}

/// What a detector throws when it cannot answer for a piece.
public enum AdDetectorError: Error, Equatable, Sendable {
  /// The piece does not fit the model's window: the caller splits it in two and asks again.
  case tooLong
  case unavailable(AdUnavailable)
  case failed(String)
  /// The model refused the lines (Apple's guardrails). This is the one failure that counts as
  /// "no ads" for the piece: asking again would be refused again. The runner counts it and
  /// reports it (`AdsFile.refusedPieces`).
  case refused
}

/// Finds ads in a piece of transcript. The one for the phone is in PodcastAdsOnDevice; the
/// tests use a fake. Later detectors (a bigger model) differ only in their token budget.
public protocol AdDetector: Sendable {
  /// Short and safe in a file name: results are saved as `<sha256>.ads.<name>.json`.
  var name: String { get }
  /// Changes when the prompt, the model or what this file does with answers changes.
  var version: String { get }
  /// The transcript tokens one request may carry.
  var tokenBudget: Int { get }
  func findAds(in piece: TranscriptPiece) async throws -> [AdRange]
}
