// LOFI-FORK: the podcast player's silence trimming (see FORK.md). Plain values, no
// AVFoundation, so it tests on Linux. The app reads a downloaded file once into a list of how
// loud each 50 ms was; these rules turn that into silent gaps, the gaps into jumps for the
// chosen strength, and say what the player does when playback reaches one.
import Foundation

/// How much of the quiet between words is cut. A stronger choice cuts shorter gaps and leaves
/// less of each.
public enum TrimStrength: String, CaseIterable, Sendable, Equatable {
  case off, mild, medium, strong

  /// A stored or typed value; anything that is not a strength is off.
  public init(stored value: Any?) {
    self = (value as? String).flatMap(TrimStrength.init(rawValue:)) ?? .off
  }

  /// Only gaps longer than this many seconds are trimmed.
  public var minimumGap: Double {
    switch self {
    case .off: return .infinity
    case .mild: return 1.0
    case .medium: return 0.6
    case .strong: return 0.4
    }
  }

  /// Seconds of each trimmed gap that still play, so speech does not run together.
  public var kept: Double {
    switch self {
    case .off: return 0
    case .mild: return 0.4
    case .medium: return 0.25
    case .strong: return 0.15
    }
  }

  /// The strength the player uses: a show's own choice wins over the listener's.
  public static func effective(show: TrimStrength?, listener: TrimStrength) -> TrimStrength {
    show ?? listener
  }
}

/// A stretch of the episode with no speech in it, in seconds.
public struct SilentGap: Codable, Sendable, Equatable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }

  public var length: Double { end - start }
}

/// Finding the silent gaps from how loud each frame was.
public enum SilenceFinder {
  /// The length of one loudness frame, in seconds.
  public static let frameSeconds = 0.05
  /// Shorter gaps are never saved: no strength trims them.
  public static let shortestGap = 0.3
  /// Under this loudness (root mean square, 0 to 1) there is no speech to measure against.
  static let noSpeech: Float = 0.002
  /// A frame is silent when it is under this share of the episode's speech level (about -22 dB).
  static let relativeThreshold: Float = 0.08

  /// The loudness the episode's speech has: a loud-ish percentile, so the occasional peak
  /// does not set it and the quiet parts do not drag it down.
  public static func speechLevel(_ loudness: [Float]) -> Float {
    let sorted = loudness.filter { $0.isFinite }.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
  }

  /// The silent gaps of at least `shortestGap`, in order. A gap that runs to the end of the
  /// episode is left out, so the episode never ends by a jump. Nothing when the episode has no
  /// speech to measure against.
  public static func gaps(loudness: [Float]) -> [SilentGap] {
    let level = speechLevel(loudness)
    guard level >= noSpeech else { return [] }
    let threshold = level * relativeThreshold
    var gaps: [SilentGap] = []
    var runStart: Int?
    for (index, value) in loudness.enumerated() {
      let quiet = value.isFinite && value < threshold
      if quiet, runStart == nil { runStart = index }
      if !quiet, let first = runStart {
        append(first, index, to: &gaps)
        runStart = nil
      }
    }
    return gaps
  }

  private static func append(_ first: Int, _ end: Int, to gaps: inout [SilentGap]) {
    let gap = SilentGap(start: Double(first) * frameSeconds, end: Double(end) * frameSeconds)
    if gap.length >= shortestGap - 1e-9 { gaps.append(gap) }
  }
}

/// `<sha256>.silence.json`: a file's silent gaps, made once.
public struct SilenceFile: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var version: Int
  public var sha256: String
  /// Seconds of audio that were read.
  public var duration: Double
  public var gaps: [SilentGap]

  public init(sha256: String, duration: Double, gaps: [SilentGap]) {
    self.version = Self.currentVersion
    self.sha256 = sha256
    self.duration = duration
    self.gaps = gaps
  }
}

/// Where one episode's silence file lives: in its download folder next to the audio, so
/// deleting the download deletes it.
public struct SilenceStore: Sendable {
  public let folder: URL
  public let sha256: String

  public init(folder: URL, sha256: String) {
    self.folder = folder
    self.sha256 = sha256
  }

  public var url: URL { folder.appendingPathComponent("\(sha256).silence.json") }

  public func save(_ file: SilenceFile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(file).write(to: url, options: .atomic)
  }

  /// The saved file, or nil when there is none, it cannot be read, or it is of another file.
  public func load() -> SilenceFile? {
    guard let data = try? Data(contentsOf: url),
      let file = try? JSONDecoder().decode(SilenceFile.self, from: data),
      file.version == SilenceFile.currentVersion, file.sha256 == sha256
    else { return nil }
    return file
  }
}

/// One jump: when playback reaches `start`, go to `target`. `saved` seconds are left out.
public struct Trim: Sendable, Equatable {
  public var start: Double
  public var target: Double

  public var saved: Double { target - start }
}

/// The jumps a strength makes in an episode, and when to make one.
public struct TrimSkipper: Sendable {
  /// The least that is worth a jump.
  static let worthwhile = 0.1

  public private(set) var trims: [Trim]
  private var enteredBySeek: Set<Double> = []

  /// - Parameters:
  ///   - gaps: the episode's silent gaps.
  ///   - avoiding: stretches (the episode's ads) that are never trimmed, so an ad skip wins.
  public init(gaps: [SilentGap], strength: TrimStrength, avoiding: [ClosedRange<Double>] = []) {
    guard strength != .off else {
      trims = []
      return
    }
    let half = strength.kept / 2
    trims = gaps.filter { gap in
      gap.length > strength.minimumGap
        && !avoiding.contains { $0.lowerBound < gap.end + 0.5 && gap.start - 0.5 < $0.upperBound }
    }.map { Trim(start: $0.start + half, target: $0.end - half) }
      .filter { $0.saved >= Self.worthwhile }
      .sorted { $0.start < $1.start }
  }

  /// Where to set markers for the jumps that start after `position`, within `window` seconds.
  public func boundaryTimes(after position: Double, window: Double) -> [Double] {
    trims.map(\.start).filter { $0 > position && $0 <= position + window }
  }

  /// The playhead was moved by the listener (or the app). A gap it lands in is not trimmed.
  public mutating func seeked(to position: Double) {
    enteredBySeek = Set(trims.filter { $0.start <= position && position < $0.target }.map(\.start))
  }

  /// How far past a marker playback may be when the player is told about it and still count as
  /// having reached it.
  public static func reachWindow(rate: Double) -> Double {
    1.0 + (rate.isFinite && rate > 1 ? rate : 1)
  }

  /// Playback crossed a marker and is now at `position`. The jump to make, or nil when the
  /// playhead is not at the start of a gap (the listener got into it by a seek, or the jump
  /// would go nowhere any more).
  public func reached(position: Double, rate: Double) -> Trim? {
    guard position.isFinite else { return nil }
    let window = Self.reachWindow(rate: rate)
    return trims.last {
      position >= $0.start - 0.5 && position <= $0.start + window
        && position < $0.target - 0.05 && !enteredBySeek.contains($0.start)
    }
  }
}

/// The counter of time saved by trimming, kept as one plain number a stats screen can read.
public struct TrimSavings: Sendable, Equatable {
  public private(set) var seconds: Double

  public init(seconds: Double = 0) {
    self.seconds = seconds.isFinite && seconds > 0 ? seconds : 0
  }

  public mutating func add(_ saved: Double) {
    guard saved.isFinite, saved > 0 else { return }
    seconds += saved
  }
}
