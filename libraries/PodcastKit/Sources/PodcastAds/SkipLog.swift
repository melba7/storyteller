// LOFI-FORK: the skip log, one line for each ad skip and how it ended (see FORK.md).
//
// The log is for Mo: it shows why a skip was wrong, with the words around each edge. It stays on
// the phone as `skip-log.jsonl` and leaves it only when the listener taps "Send skip log". The
// words come from the transcript, so the file is never committed. These are the plain values and
// the file's text; `SkipWatch` decides how each skip ended. Foundation only.
import Foundation
import PodcastTranscripts

/// Where a skipped ad came from.
public enum SkipSource: String, Codable, Sendable, Equatable {
  case rules, model, memory, chapter, diff
}

/// How a skip ended.
public enum SkipOutcome: Equatable, Sendable {
  /// The listener did nothing about it for 20 seconds.
  case kept
  /// The listener tapped Undo.
  case undone
  /// The listener went back into the skipped ad, and the ad now ends where they went back to.
  case trimmed(seconds: Double)
  /// The listener went back to before the landing in a way that is not a trim.
  case seekBack(seconds: Double)
  /// Three forward jumps by the listener in a minute where no ad was known.
  case maybeMissed

  var name: String {
    switch self {
    case .kept: return "kept"
    case .undone: return "undone"
    case .trimmed: return "trimmed"
    case .seekBack: return "seekBack"
    case .maybeMissed: return "maybeMissed"
    }
  }

  var seconds: Double? {
    switch self {
    case .trimmed(let seconds), .seekBack(let seconds): return seconds
    default: return nil
    }
  }

  init?(name: String, seconds: Double?) {
    switch (name, seconds) {
    case ("kept", _): self = .kept
    case ("undone", _): self = .undone
    case ("trimmed", let seconds?): self = .trimmed(seconds: seconds)
    case ("seekBack", let seconds?): self = .seekBack(seconds: seconds)
    case ("maybeMissed", _): self = .maybeMissed
    default: return nil
    }
  }
}

/// What the player knows when it skips: when, which episode and show, where the ad came from and
/// how long after the tap on Play the skip was made (nil when that is not measured).
public struct SkipContext: Sendable, Equatable {
  /// Seconds since 1970.
  public var time: Double
  public var episode: String
  public var show: String?
  public var source: SkipSource?
  public var tapToSkip: Double?

  public init(
    time: Double, episode: String, show: String? = nil, source: SkipSource? = nil,
    tapToSkip: Double? = nil
  ) {
    self.time = time
    self.episode = episode
    self.show = show
    self.source = source
    self.tapToSkip = tapToSkip
  }
}

/// The words just before and just after an edge, as the transcript spells them.
public struct EdgeWords: Codable, Sendable, Equatable {
  public var before: String
  public var after: String

  public init(before: String, after: String) {
    self.before = before
    self.after = after
  }
}

/// One line of the log.
public struct SkipLogEntry: Codable, Sendable, Equatable {
  /// Seconds since 1970 when the skip was made.
  public var time: Double
  public var show: String?
  public var episode: String
  /// The skipped stretch in seconds of audio. For a `maybeMissed` line, from where the first
  /// jump left to where the last one landed.
  public var start: Double
  public var end: Double
  /// Nil for a `maybeMissed` line, which has no ad.
  public var kind: AdKind?
  public var confidence: AdConfidence?
  public var source: SkipSource?
  public var tapToSkip: Double?
  /// `kept`, `undone`, `trimmed`, `seekBack` or `maybeMissed`.
  public var outcome: String
  /// For `trimmed` and `seekBack`: how many seconds.
  public var outcomeSeconds: Double?
  public var startWords: EdgeWords?
  public var endWords: EdgeWords?

  public init(
    context: SkipContext, start: Double, end: Double, kind: AdKind?, confidence: AdConfidence?,
    outcome: SkipOutcome
  ) {
    time = context.time
    show = context.show
    episode = context.episode
    self.start = start
    self.end = end
    self.kind = kind
    self.confidence = confidence
    source = context.source
    tapToSkip = context.tapToSkip
    self.outcome = outcome.name
    outcomeSeconds = outcome.seconds
  }

  /// How the skip ended; nil for a line this version does not know.
  public var result: SkipOutcome? { SkipOutcome(name: outcome, seconds: outcomeSeconds) }

  public mutating func setResult(_ result: SkipOutcome) {
    outcome = result.name
    outcomeSeconds = result.seconds
  }

  /// Adds the words around both edges from the episode's transcript. With no words (the
  /// transcript does not exist yet) the line has none, instead of two empty pairs.
  public mutating func addWords(from words: [TranscriptWord]) {
    guard !words.isEmpty else { return }
    startWords = SkipLog.edgeWords(at: start, in: words)
    endWords = SkipLog.edgeWords(at: end, in: words)
  }
}

/// The log file's text: one JSON object to a line, never more than `maxLines` lines. The oldest
/// lines go first.
public struct SkipLog: Sendable, Equatable {
  public static let maxLines = 500
  /// How many words are kept on each side of an edge.
  public static let edgeWordCount = 12
  /// A word that starts this close before the edge still counts as after it.
  private static let tolerance = 0.05

  public private(set) var lines: [String]

  /// The log as it is saved (empty for no file). Blank lines are dropped, and a file of more than
  /// `maxLines` lines keeps the newest. The ad finder's diary lines (`AdDiary`), which the copy
  /// that is sent has after the skip lines, are not skips and are left out.
  public init(text: String = "") {
    lines = Array(
      text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        .filter { !AdDiary.isDiaryLine($0) }.suffix(Self.maxLines))
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  public mutating func append(_ entry: SkipLogEntry) {
    guard let data = try? Self.encoder.encode(entry), let line = String(data: data, encoding: .utf8)
    else { return }
    lines.append(line)
    if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
  }

  /// The text to save: each line ends with a newline. Empty for an empty log.
  public var text: String { lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }

  /// The lines that read as entries. A line that does not is kept in the file but skipped here.
  public var entries: [SkipLogEntry] {
    let decoder = JSONDecoder()
    return lines.compactMap { try? decoder.decode(SkipLogEntry.self, from: Data($0.utf8)) }
  }

  /// The words just before and just after `time`, at most `count` of each. The words are in
  /// order. A word that starts at the edge is after it.
  public static func edgeWords(
    at time: Double, in words: [TranscriptWord], count: Int = edgeWordCount
  ) -> EdgeWords {
    var low = 0
    var high = words.count
    while low < high {
      let mid = (low + high) / 2
      if words[mid].start < time - tolerance { low = mid + 1 } else { high = mid }
    }
    func join(_ slice: ArraySlice<TranscriptWord>) -> String {
      slice.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    return EdgeWords(
      before: join(words[max(0, low - count)..<low]),
      after: join(words[low..<min(words.count, low + count)]))
  }
}
