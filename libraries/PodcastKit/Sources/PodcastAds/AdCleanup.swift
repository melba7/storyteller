// LOFI-FORK: turns a detector's answers into the ads to show and skip (see FORK.md).
//
// The merge of ads with little speech between them (at most 5 minutes) and the carried-on end
// follow MinusPod (MIT, github.com/ttlequals0/MinusPod); see FORK.md.
import Foundation
import PodcastTranscripts

/// The numbers the clean-up uses.
public enum AdRules {
  /// Two sure ads of one kind with less speech than this between them are one ad break.
  public static let mergeSpeech = 4.0
  /// They are also one break with less speech than this between them when every line that lies
  /// wholly between them is filler (a web address, an advertiser's name or a break cue).
  public static let mergeFiller = 12.0
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
  /// When the ads cover more than this share of an episode, or one ad is longer than `longAd`
  /// seconds, an ad needs at least two lines of evidence (`AdEvidence`) to stay sure.
  public static let shareLimit = 0.35
  public static let longAd = 180.0
  /// The share is only judged for a transcript of at least this many seconds: a stream's head
  /// (3 minutes at most) can be mostly one ad.
  public static let shareFrom = 240.0
}

public enum AdCleanup {
  /// The ads in an episode from all the detector's answers for its pieces. Steps: guesses and
  /// answers that name no real lines are dropped; a sure answer with nothing in its lines that
  /// says "ad" becomes unsure (`AdEvidence`); the model's last lines are trimmed when the show
  /// is back, and a sure end is carried on while the next lines still read as the ad; line
  /// numbers become times, and an edge line is cut where its words say the show is back or the
  /// lead-in begins (`AdEdgeCut`); overlapping answers (an ad across a cut) are joined into one,
  /// and so are sure ads of one break; when the ads are too much of the episode or one is too
  /// long, those with under two lines of evidence become unsure; edges land a quarter second
  /// before the next word (`AdLanding`);
  /// what is too short or too long is dropped.
  public static func run(ranges: [AdRange], transcript: Transcript) -> [FoundAd] {
    explain(ranges: ranges, transcript: transcript).map(\.ad)
  }

  /// The same ads as `run`, each with how it came about: the model's lines, the lines trimmed
  /// and carried, the answers joined and the lines around each edge.
  public static func explain(ranges: [AdRange], transcript: Transcript) -> [AdTrace] {
    let lines = transcript.lines
    guard !lines.isEmpty else { return [] }

    let words = transcript.words
    var spans: [Span] = []
    for range in ranges where range.confidence != .guess {
      let first = min(range.startLine, range.endLine)
      let last = max(range.startLine, range.endLine)
      guard first >= 1, last <= lines.count else { continue }
      // An ad that ends with the show coming back is cut short and nothing is carried; an ad the
      // model is unsure of is never carried, and a sure one with no evidence is unsure.
      var end = trimmedEnd(first: first, last: last, advertiser: range.advertiser, lines: lines)
      let trimmed = last - end
      var confidence = range.confidence
      if confidence == .sure,
        AdEvidence.count(lines: lines[(first - 1)..<end], advertiser: range.advertiser) == 0
      {
        confidence = .unsure
      }
      if trimmed == 0, confidence == .sure {
        end = carriedEnd(of: last, advertiser: range.advertiser, lines: lines)
      }
      // The ad ends before the show is back and starts at its lead-in, when its edge lines say so.
      var start = lines[first - 1].start
      var stop = lines[end - 1].end
      if let cut = AdEdgeCut.end(of: lines[end - 1], advertiser: range.advertiser, words: words),
        cut > start
      {
        stop = cut
      }
      if confidence == .sure,
        let cut = AdEdgeCut.start(of: lines[first - 1], advertiser: range.advertiser, words: words),
        cut < stop
      {
        start = cut
      }
      spans.append(
        Span(
          start: start, end: stop, kind: range.kind, advertiser: range.advertiser,
          confidence: confidence, first: first, last: last, trimmed: trimmed,
          carried: end - last, answers: 1))
    }

    let duration = transcript.duration > 0 ? transcript.duration : lines[lines.count - 1].end
    let merged = needingProof(
      merge(spans, lines: lines, words: words), lines: lines, duration: duration)
    var traces: [AdTrace] = []
    for span in merged {
      let landed = AdLanding.edges(start: span.start, end: span.end, words: words)
      let start = max(0, landed.start)
      let end = min(transcript.duration > 0 ? transcript.duration : .infinity, landed.end)
      guard end - start >= AdRules.minLength, end - start <= AdRules.maxLength else { continue }
      let ad = FoundAd(
        start: start, end: end, kind: span.kind, advertiser: span.advertiser,
        confidence: span.confidence, firstWords: opening(of: span, words: words))
      func numbered(_ numbers: ClosedRange<Int>) -> [NumberedLine] {
        numbers.map { NumberedLine(number: $0, line: lines[$0 - 1]) }
      }
      traces.append(
        AdTrace(
          ad: ad, firstLine: span.first, lastLine: span.last,
          trimmed: span.trimmed > 0 ? numbered((span.last - span.trimmed + 1)...span.last) : [],
          carried: span.carried > 0 ? numbered((span.last + 1)...(span.last + span.carried)) : [],
          answers: span.answers, aroundStart: EdgeContext(at: start, lines: lines),
          aroundEnd: EdgeContext(at: end, lines: lines)))
    }
    return traces
  }

  private struct Span {
    var start: Double
    var end: Double
    var kind: AdKind
    var advertiser: String
    var confidence: AdConfidence
    /// The model's first and last line (of the answer that ends latest), the lines trimmed off
    /// its end or carried after it, and how many answers this span joins.
    var first: Int
    var last: Int
    var trimmed: Int
    var carried: Int
    var answers: Int
    var length: Double { end - start }

    /// Takes over the end of `other`, an answer that ends later.
    mutating func takeEnd(of other: Span) {
      end = other.end
      last = other.last
      trimmed = other.trimmed
      carried = other.carried
    }
  }

  /// The last line number of an ad after carrying it on: while the line after it sells (see
  /// `AdSignals.carriesOn`), it belongs to the ad, for at most `carryLines` lines, and only
  /// lines that start within `carrySeconds` of the model's last line.
  static func carriedEnd(of last: Int, advertiser: String, lines: [TranscriptLine]) -> Int {
    var end = last
    while end < lines.count, end - last < AdRules.carryLines,
      lines[end].start - lines[last - 1].end <= AdRules.carrySeconds,
      AdSignals.carriesOn(lines[end].text, advertiser: advertiser, after: lines[end - 1].text)
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

  /// Joins spans that overlap (the same ad seen in two pieces: the surer answer stands), and sure
  /// spans of one kind that are one break (see `isOneBreak`).
  private static func merge(
    _ spans: [Span], lines: [TranscriptLine], words: [TranscriptWord]
  ) -> [Span] {
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
        if span.end > last.end { last.takeEnd(of: span) }
        last.first = min(last.first, span.first)
        last.answers += span.answers
        result.append(last)
      } else if isOneBreak(last, span, lines: lines, words: words) {
        last.takeEnd(of: span)
        last.answers += span.answers
        if last.advertiser.isEmpty { last.advertiser = span.advertiser }
        result.append(last)
      } else {
        result.append(last)
        result.append(span)
      }
    }
    return result
  }

  /// Whether two ads that do not overlap are one ad break. Both must be sure (an unsure ad never
  /// joins a neighbour it does not overlap) and of one kind, and the break at most `mergeCap`
  /// long. Then either less than `mergeSpeech` seconds of speech lie between them, or less than
  /// `mergeFiller` and every line that lies wholly between them is filler.
  private static func isOneBreak(
    _ first: Span, _ second: Span, lines: [TranscriptLine], words: [TranscriptWord]
  ) -> Bool {
    guard first.confidence == .sure, second.confidence == .sure, first.kind == second.kind,
      second.end - first.start <= AdRules.mergeCap
    else { return false }
    let between = speech(from: first.end, to: second.start, words: words)
    if between < AdRules.mergeSpeech { return true }
    guard between < AdRules.mergeFiller else { return false }
    return lines.filter { $0.start >= first.end - 0.01 && $0.end <= second.start + 0.01 }
      .allSatisfy {
        AdSignals.hardSignal($0.text) || AdSignals.breakCue($0.text)
          || AdSignals.namesAdvertiser($0.text, advertiser: first.advertiser)
          || AdSignals.namesAdvertiser($0.text, advertiser: second.advertiser)
      }
  }

  /// When the ads cover over `shareLimit` of the episode, every sure ad with under two lines of
  /// evidence becomes unsure. A sure ad longer than `longAd` seconds needs the same, whatever
  /// the share of the others.
  private static func needingProof(
    _ spans: [Span], lines: [TranscriptLine], duration: Double
  ) -> [Span] {
    let crowded =
      duration >= AdRules.shareFrom
      && spans.reduce(0) { $0 + $1.length } > AdRules.shareLimit * duration
    return spans.map { span in
      guard span.confidence == .sure, crowded || span.length > AdRules.longAd else { return span }
      let inside = lines.filter { $0.end > span.start + 0.001 && $0.start < span.end }
      guard AdEvidence.count(lines: inside, advertiser: span.advertiser) < 2 else { return span }
      var weak = span
      weak.confidence = .unsure
      return weak
    }
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
