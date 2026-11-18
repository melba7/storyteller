// LOFI-FORK: chapters that name a sponsor are ads, when the words agree (see FORK.md).
//
// Some producers mark their ad breaks as chapters ("Sponsor: Squarespace"). Such a chapter gives
// an ad's edges exactly, but a host that inserts ads does not move its chapters, so a chapter can
// lie late by the length of the ads before it (RSS.com says so in its help). So a chapter is an
// ad only when the words inside it sell: a web address, a promo code, "brought to you by" or the
// name in the title. The ad starts at the first line that sells or opens a sponsor read, and
// nothing here makes a skip longer: an ad the model found is only cut short by a chapter, never
// stretched. Foundation only.
import Foundation
import PodcastTranscripts

public enum ChapterAds {
  /// A chapter as this needs it. `PodcastChapters` has the real type; the phone copies its
  /// start, end and title, so this module stays free of that one.
  public struct Mark: Sendable, Equatable {
    public var start: Double
    /// Where the source says the chapter ends. Otherwise it ends where the next one starts.
    public var end: Double?
    public var title: String

    public init(start: Double, end: Double? = nil, title: String) {
      self.start = start
      self.end = end
      self.title = title
    }
  }

  /// A title whose first word is one of these ...
  private static let adWords: Set<String> = ["ad", "ads", "break"]
  /// ... or starts with one of these ("sponsors", "advertisement", "commercial break") ...
  private static let firstWordStarts = ["sponsor", "advert", "commercial"]
  /// ... or has one of these anywhere, is a chapter that may be an ad.
  private static let phrases = ["sponsored by", "brought to you by"]

  /// Whether the title is one an ad break would have. "Adventures in Peru" is not.
  public static func isAdTitle(_ title: String) -> Bool {
    let lower = title.lowercased()
    if phrases.contains(where: { lower.contains($0) }) { return true }
    let first = lower.drop(while: { !$0.isLetter && !$0.isNumber })
      .prefix(while: { $0.isLetter || $0.isNumber })
    return adWords.contains(String(first)) || firstWordStarts.contains { first.hasPrefix($0) }
  }

  /// The sponsor a title names: what follows "sponsored by", "brought to you by" or the first
  /// colon, bar or dash ("Sponsor: Squarespace"). Empty when the title names none.
  static func advertiser(inTitle title: String) -> String {
    var rest: Substring?
    for phrase in phrases {
      if let found = title.range(of: phrase, options: .caseInsensitive) {
        rest = title[found.upperBound...]
        break
      }
    }
    if rest == nil {
      let body = title.replacingOccurrences(of: " - ", with: ":")
        .drop(while: { !$0.isLetter && !$0.isNumber })
      if let at = body.firstIndex(where: { ":|–—".contains($0) }) {
        rest = body[body.index(after: at)...]
      }
    }
    return (rest.map(String.init) ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }

  /// The names in an advertiser ("Quokka and Acme"), one by one.
  static func names(in advertiser: String) -> [String] {
    advertiser.replacingOccurrences(of: " and ", with: ",")
      .split(whereSeparator: { ",&+/;".contains($0) })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// The ads the chapters give, from each chapter's start to where the next one starts (or its
  /// own end when that is sooner). A chapter needs to be 10 to 300 seconds long, wholly inside
  /// the transcript, and to have words that sell: a hard signal (`AdSignals`) or the name in its
  /// title. The end goes no later than the chapter's, and earlier when the show is back in its
  /// last lines. The last chapter ends with `episodeDuration`; without it, it is no ad.
  public static func find(
    marks: [Mark], transcript: Transcript, episodeDuration: Double? = nil
  ) -> [FoundAd] {
    let ordered = marks.filter { $0.start.isFinite && $0.start >= 0 }.sorted { $0.start < $1.start }
    var ads: [FoundAd] = []
    for (index, mark) in ordered.enumerated() where isAdTitle(mark.title) {
      let next = index + 1 < ordered.count ? ordered[index + 1].start : episodeDuration
      guard let limit = [next, mark.end].compactMap({ $0 }).filter({ $0.isFinite && $0 > mark.start })
        .min(),
        limit - mark.start >= AdRules.minLength, limit - mark.start <= AdRules.maxLength,
        limit <= transcript.duration + 1
      else { continue }
      let sponsor = advertiser(inTitle: mark.title)
      let sponsorNames = names(in: sponsor)
      let inside = transcript.lines.filter { $0.start >= mark.start - 0.01 && $0.start < limit }
      guard inside.contains(where: { sells($0.text, sponsorNames) }) else { continue }
      var end = limit
      if let back = showIsBack(in: inside, names: sponsorNames) { end = inside[back - 1].end }
      // Inserted ads may have pushed the real read later than its chapter: the ad starts at the
      // first line that sells or opens a sponsor read, not at the chapter's start.
      let first = inside.first {
        sells($0.text, sponsorNames) || AdSignals.matches(AdSignals.leadIns, $0.text)
      }
      let landed = AdLanding.edges(
        start: max(mark.start, first?.start ?? mark.start), end: end, words: transcript.words)
      // Landing may only shorten: not before the chapter's start, not after its end.
      let start = max(mark.start, landed.start)
      let stop = min(limit, landed.end)
      guard stop - start >= AdRules.minLength else { continue }
      let opening = transcript.words.filter { $0.start >= start - 0.01 && $0.start < stop }
        .prefix(AdRules.firstWords).map(\.text).joined(separator: " ")
      ads.append(
        FoundAd(
          start: start, end: stop, kind: .ad, advertiser: sponsor, confidence: .sure,
          firstWords: opening))
    }
    return ads
  }

  private static func sells(_ text: String, _ names: [String]) -> Bool {
    AdSignals.hardSignal(text)
      || names.contains { AdSignals.namesAdvertiser(text, advertiser: $0) }
  }

  /// The index of the first of the last three lines (never the first of all) that says the show
  /// is back, when no line from there on sells. The ad then ends with the line before it, as the
  /// clean-up ends a model's ad. Nil when there is no such line.
  private static func showIsBack(in lines: [TranscriptLine], names: [String]) -> Int? {
    guard lines.count > 1 else { return nil }
    return (max(1, lines.count - 3)..<lines.count).first { at in
      AdSignals.returnCue(lines[at].text) && !lines[at...].contains { sells($0.text, names) }
    }
  }

  /// The chapters' ads joined to the others. An ad that a chapter's ad overlaps is cut to the end
  /// of the last chapter ad it overlaps when that is sooner (and the cut leaves at least 10
  /// seconds); its start, and its end when the chapter's is later, stay as they are. A chapter
  /// ad that overlaps no other ad is added. The result is in order of start.
  public static func merge(_ chapterAds: [FoundAd], into ads: [FoundAd]) -> [FoundAd] {
    var covered = Set<Int>()
    var result = ads.map { ad -> FoundAd in
      let over = chapterAds.indices.filter {
        chapterAds[$0].start < ad.end && ad.start < chapterAds[$0].end
      }
      covered.formUnion(over)
      var cut = ad
      if let end = over.map({ chapterAds[$0].end }).max(), end < ad.end,
        end - ad.start >= AdRules.minLength
      {
        cut.end = end
      }
      return cut
    }
    result += chapterAds.indices.filter { !covered.contains($0) }.map { chapterAds[$0] }
    return result.sorted { $0.start < $1.start }
  }

  /// `find` and `merge` in one call: the ads with what the chapters add and cut.
  public static func apply(
    _ marks: [Mark], to ads: [FoundAd], transcript: Transcript, episodeDuration: Double?
  ) -> [FoundAd] {
    merge(find(marks: marks, transcript: transcript, episodeDuration: episodeDuration), into: ads)
  }
}
