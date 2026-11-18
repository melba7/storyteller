// LOFI-FORK: cuts an ad inside its first or last line (see FORK.md).
//
// A line holds up to 25 words, so the last line of an ad can end with the hosts coming back
// ("... acme dot com slash show and we're back with Dana"), and the first can begin with talk
// before the sponsor lead-in. The whole line is the model's answer, so the cut is only made when
// the words themselves say where the ad stops or starts, and it can only make the ad shorter.
import Foundation
import PodcastTranscripts

enum AdEdgeCut {
  /// At least this many words must come before a return cue for the ad to end inside the line.
  static let wordsBeforeReturn = 3
  /// At least this many words must come before a lead-in for a sure ad to begin at the lead-in.
  static let wordsBeforeLeadIn = 8

  /// The time an ad ends at when its last line holds a return cue ("we're back", "welcome
  /// back"): the start of the cue's first word, when at least `wordsBeforeReturn` words come
  /// before it and no web address or mention of the advertiser comes from it on. Nil when the
  /// whole line stays.
  static func end(of line: TranscriptLine, advertiser: String, words: [TranscriptWord]) -> Double? {
    guard let cue = AdSignals.returnCueRange(in: line.text), cue.lowerBound >= wordsBeforeReturn
    else { return nil }
    let spoken = line.text.split(whereSeparator: \.isWhitespace)
    let after = spoken[cue.lowerBound...].joined(separator: " ")
    guard !AdSignals.hardSignal(after), !AdSignals.namesAdvertiser(after, advertiser: advertiser)
    else { return nil }
    return time(ofWord: cue.lowerBound, in: line, spoken: spoken.count, words: words)
  }

  /// The time a sure ad begins at when its first line holds a sponsor lead-in ("this episode is
  /// brought to you by"): the start of the lead-in's first word, when at least
  /// `wordsBeforeLeadIn` words come before it and none of them says anything an ad says
  /// (`AdEvidence`). Nil when the whole line stays.
  static func start(of line: TranscriptLine, advertiser: String, words: [TranscriptWord]) -> Double? {
    guard let lead = AdSignals.leadInRange(in: line.text), lead.lowerBound >= wordsBeforeLeadIn
    else { return nil }
    let spoken = line.text.split(whereSeparator: \.isWhitespace)
    let before = spoken[..<lead.lowerBound].joined(separator: " ")
    guard !AdEvidence.isEvidence(before, advertiser: advertiser) else { return nil }
    return time(ofWord: lead.lowerBound, in: line, spoken: spoken.count, words: words)
  }

  /// The start of the line's word number `index`. The words of the line are the transcript's
  /// words that start inside it; when their number is not the number of words in the text (the
  /// line was made by something else) nothing is cut.
  private static func time(
    ofWord index: Int, in line: TranscriptLine, spoken: Int, words: [TranscriptWord]
  ) -> Double? {
    let inside = words.filter { $0.start >= line.start - 0.01 && $0.start < line.end }
    return inside.count == spoken ? inside[index].start : nil
  }
}
