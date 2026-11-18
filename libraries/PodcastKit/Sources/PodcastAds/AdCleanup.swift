// LOFI-FORK: turns a detector's answers into the ads to show and skip (see FORK.md).
//
// The merge of ads with little speech between them (12 seconds, at most 5 minutes) and the
// carried-on end follow MinusPod (MIT, github.com/ttlequals0/MinusPod); see FORK.md.
import Foundation
import PodcastTranscripts

/// The numbers the clean-up uses.
public enum AdRules {
  /// Two ads of one kind with less speech than this between them are one ad break.
  public static let mergeSpeech = 12.0
  /// A merged break is never longer than this.
  public static let mergeCap = 300.0
  /// Anything shorter is dropped.
  public static let minLength = 10.0
  /// Anything longer is dropped: it is more likely a mistake than an ad.
  public static let maxLength = 300.0
  /// How many lines after an ad may still be carried into it.
  public static let carryLines = 2
  /// A carried line must start within this many seconds of the end of the model's last line.
  public static let carrySeconds = 15.0
  /// A skip lands this long before the first word of the show (and starts this long before the
  /// first word of the ad).
  public static let landBefore = 0.25
  /// An ad whose first word starts within this many seconds of the episode's start begins at zero.
  public static let topOfEpisode = 6.0
  /// A gap between two words counts as a pause from this long.
  public static let pause = 0.3
  /// How many words of the ad's start are kept to recognise it.
  public static let firstWords = 14
}

public enum AdCleanup {
  /// The ads in an episode from all the detector's answers for its pieces. Steps: guesses and
  /// answers that name no real lines are dropped; each end is carried on while the next lines
  /// still read as the ad; line numbers become times; overlapping answers (an ad across a cut)
  /// are joined into one, and so are ads of one kind with little speech between them; edges
  /// land a quarter second before the next word (`AdLanding`); what is too short or too long is
  /// dropped.
  public static func run(ranges: [AdRange], transcript: Transcript) -> [FoundAd] {
    let lines = transcript.lines
    guard !lines.isEmpty else { return [] }

    var spans: [Span] = []
    for range in ranges where range.confidence != .guess {
      let first = min(range.startLine, range.endLine)
      let last = max(range.startLine, range.endLine)
      guard first >= 1, last <= lines.count else { continue }
      // An ad that ends with the show coming back is cut short and nothing is carried; an ad the
      // model is unsure of is never carried.
      var end = trimmedEnd(first: first, last: last, advertiser: range.advertiser, lines: lines)
      if end == last, range.confidence == .sure {
        end = carriedEnd(of: last, advertiser: range.advertiser, lines: lines)
      }
      spans.append(
        Span(
          start: lines[first - 1].start, end: lines[end - 1].end, kind: range.kind,
          advertiser: range.advertiser, confidence: range.confidence))
    }

    let words = transcript.words
    var ads: [FoundAd] = []
    for span in merge(spans, words: words) {
      let landed = AdLanding.edges(start: span.start, end: span.end, words: words)
      let start = max(0, landed.start)
      let end = min(transcript.duration > 0 ? transcript.duration : .infinity, landed.end)
      guard end - start >= AdRules.minLength, end - start <= AdRules.maxLength else { continue }
      ads.append(
        FoundAd(
          start: start, end: end, kind: span.kind, advertiser: span.advertiser,
          confidence: span.confidence, firstWords: opening(of: span, words: words)))
    }
    return ads
  }

  private struct Span {
    var start: Double
    var end: Double
    var kind: AdKind
    var advertiser: String
    var confidence: AdConfidence
    var length: Double { end - start }
  }

  /// The last line number of an ad after carrying it on: while the line after it sells (see
  /// `AdSignals.carriesOn`), it belongs to the ad, for at most `carryLines` lines, and only
  /// lines that start within `carrySeconds` of the model's last line.
  static func carriedEnd(of last: Int, advertiser: String, lines: [TranscriptLine]) -> Int {
    var end = last
    while end < lines.count, end - last < AdRules.carryLines,
      lines[end].start - lines[last - 1].end <= AdRules.carrySeconds,
      AdSignals.carriesOn(lines[end].text, advertiser: advertiser)
    {
      end += 1
    }
    return end
  }

  /// The last line number of an ad after trimming it: the model's last three lines (never its
  /// first) are searched for the first line R that says the show is back, with no line from R to
  /// the end that gives a hard signal or names the advertiser. The ad then ends at line R-1.
  static func trimmedEnd(
    first: Int, last: Int, advertiser: String, lines: [TranscriptLine]
  ) -> Int {
    guard max(first + 1, last - 2) <= last else { return last }
    for line in max(first + 1, last - 2)...last where AdSignals.returnCue(lines[line - 1].text) {
      let sells = lines[(line - 1)..<last].contains {
        AdSignals.hardSignal($0.text) || AdSignals.namesAdvertiser($0.text, advertiser: advertiser)
      }
      if !sells { return line - 1 }
    }
    return last
  }

  /// Joins spans that overlap (the same ad seen in two pieces: the surer answer stands), and
  /// spans of one kind with less than `mergeSpeech` seconds of speech between them when the
  /// result stays within `mergeCap` (one break: the less sure answer stands).
  private static func merge(_ spans: [Span], words: [TranscriptWord]) -> [Span] {
    var result: [Span] = []
    for span in spans.sorted(by: { $0.start < $1.start }) {
      guard var last = result.popLast() else {
        result.append(span)
        continue
      }
      if span.start < last.end {
        let longer = span.length > last.length ? span : last
        last.kind = longer.kind
        if !longer.advertiser.isEmpty {
          last.advertiser = longer.advertiser
        } else if last.advertiser.isEmpty {
          last.advertiser = span.advertiser
        }
        last.confidence = max(last.confidence, span.confidence)
        last.end = max(last.end, span.end)
        result.append(last)
      } else if span.kind == last.kind, span.end - last.start <= AdRules.mergeCap,
        speech(from: last.end, to: span.start, words: words) < AdRules.mergeSpeech
      {
        last.end = span.end
        last.confidence = min(last.confidence, span.confidence)
        if last.advertiser.isEmpty { last.advertiser = span.advertiser }
        result.append(last)
      } else {
        result.append(last)
        result.append(span)
      }
    }
    return result
  }

  /// Seconds of speech between two times: the length of the words that lie between them.
  static func speech(from: Double, to: Double, words: [TranscriptWord]) -> Double {
    words.reduce(0) { total, word in
      total + max(0, min(word.end, to) - max(word.start, from))
    }
  }

  private static func opening(of span: Span, words: [TranscriptWord]) -> String {
    words.filter { $0.start >= span.start - 0.01 && $0.start < span.end }
      .prefix(AdRules.firstWords).map(\.text).joined(separator: " ")
  }
}
