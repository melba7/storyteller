// LOFI-FORK: the podcast transcripts' rules as plain values (see FORK.md).
import Foundation

/// How timed words become lines.
public enum LineRule {
  /// A silence this long ends a line.
  public static let pause = 0.8
  /// A line is cut after this many words.
  public static let maxWords = 25

  private static let closers = CharacterSet(charactersIn: "\"')]}”’»")

  /// Whether the word ends a sentence: its last character, past any closing quote or
  /// bracket, is `.`, `!`, `?` or `…`.
  public static func endsSentence(_ text: String) -> Bool {
    var scalars = Substring(text).unicodeScalars
    while let last = scalars.last, closers.contains(last) { scalars.removeLast() }
    guard let last = scalars.last else { return false }
    return last == "." || last == "!" || last == "?" || last == "…"
  }

  /// Lines of words in order. A line ends after a sentence's end, before a pause of
  /// `pause` seconds or more, and after `maxWords` words.
  public static func lines(
    from words: [TranscriptWord], pause: Double = pause, maxWords: Int = maxWords
  ) -> [TranscriptLine] {
    var lines: [TranscriptLine] = []
    var group: [TranscriptWord] = []

    func flush() {
      guard let first = group.first, let last = group.last else { return }
      lines.append(
        TranscriptLine(start: first.start, end: last.end, text: group.map(\.text).joined(separator: " ")))
      group = []
    }

    for word in words {
      if let last = group.last, word.start - last.end >= pause { flush() }
      group.append(word)
      if endsSentence(word.text) || group.count >= max(1, maxWords) { flush() }
    }
    flush()
    return lines
  }
}

/// One piece of audio to transcribe.
public struct PiecePlan: Sendable, Equatable {
  /// The audio to read, in seconds. It starts a little before what is already done.
  public var readFrom: Double
  public var readTo: Double
  /// Words that start before this are already saved and are dropped.
  public var keepFrom: Double
}

/// Cutting the audio into pieces, the overlap between them, and progress.
public enum Pieces {
  /// About five minutes of audio at a time, once the first pieces are done.
  public static let seconds = 300.0
  /// The first pieces are shorter, so the first lines of the transcript (and the first ads)
  /// are there within seconds of starting: 60 seconds, then 120, then `seconds` each.
  public static let firstPieces = [60.0, 120.0]

  /// The length of the piece that starts after `reached` seconds are done. It depends only on
  /// `reached`, so a restart in the middle cuts the same pieces as one run.
  public static func length(after reached: Double) -> Double {
    var edge = 0.0
    for length in firstPieces {
      edge += length
      if reached < edge - 0.01 { return length }
    }
    return seconds
  }
  /// Each piece, and a restart, begins this far before the saved time, so a word cut in two
  /// at the edge is heard whole.
  public static let overlap = 2.0

  /// Whether `reached` is the end of the audio.
  public static func isDone(reached: Double, duration: Double) -> Bool {
    reached >= duration - 0.01
  }

  /// The next piece after `reached` seconds are done, or nil when the audio is done. Without
  /// `pieceSeconds` the piece has the length `length(after:)` gives.
  public static func next(
    reached: Double, duration: Double, pieceSeconds: Double? = nil, overlap: Double = overlap
  ) -> PiecePlan? {
    let pieceSeconds = pieceSeconds ?? length(after: max(0, reached))
    guard duration > 0, pieceSeconds > 0, !isDone(reached: reached, duration: duration) else {
      return nil
    }
    let done = max(0, reached)
    return PiecePlan(
      readFrom: max(0, done - max(0, overlap)), readTo: min(duration, done + pieceSeconds),
      keepFrom: done)
  }

  /// The saved words plus the new piece's words that start at or after `keepFrom`: the
  /// overlap's words are heard twice and kept once.
  public static func merge(
    saved: [TranscriptWord], new: [TranscriptWord], keepFrom: Double
  ) -> [TranscriptWord] {
    saved + new.filter { $0.start >= keepFrom }.sorted { $0.start < $1.start }
  }

  /// How much is done, 0 to 100.
  public static func percent(reached: Double, duration: Double) -> Int {
    guard duration > 0, reached > 0 else { return 0 }
    return min(100, max(0, Int((reached / duration * 100).rounded(.down))))
  }
}

/// Where a restart carries on from.
public enum Resume {
  /// The saved words and time to carry on from: the partial file's when it is of this
  /// recogniser, language and file and its numbers make sense, else a fresh start.
  public static func state(
    partial: PartialTranscript?, identity: TranscriptIdentity, duration: Double
  ) -> (words: [TranscriptWord], reached: Double) {
    guard let partial, partial.version == PartialTranscript.currentVersion,
      partial.identity == identity, partial.reached.isFinite, partial.reached > 0,
      partial.reached <= duration + 1,
      partial.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start <= partial.reached })
    else { return ([], 0) }
    return (partial.words, partial.reached)
  }
}

/// The language to transcribe in.
public enum LocalePick {
  /// The feed's language (an RSS `language` such as "en-us" or "de") written as a locale
  /// identifier ("en-US", "de"), or the phone's language when the feed has none.
  public static func identifier(feedLanguage: String?, phone: String) -> String {
    let feed = (feedLanguage ?? "").trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "_", with: "-")
    let parts = feed.split(separator: "-").map(String.init)
    guard let language = parts.first, (2...3).contains(language.count),
      language.allSatisfy({ $0.isASCII && $0.isLetter })
    else { return phone }
    var result = [language.lowercased()]
    for part in parts.dropFirst().prefix(2) where part.allSatisfy({ $0.isASCII && $0.isLetter }) {
      result.append(part.count == 2 ? part.uppercased() : part.capitalized)
    }
    return result.joined(separator: "-")
  }
}
