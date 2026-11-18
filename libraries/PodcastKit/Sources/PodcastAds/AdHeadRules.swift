// LOFI-FORK: text rules that mark sure ads in the first minutes of an episode (see FORK.md).
//
// These run in milliseconds on the lines of a stream's head, before the model is asked, so a
// clear sponsor read can be skipped at once. The signals are the ones the ad finder already
// uses: a sponsor lead-in followed by a call to action (a web address, a promo code, an offer),
// MinusPod's idea of carrying an ad on while the lines still read as it (AdSignals), and, from
// the Perennial-Curiosity pipeline's rules, a sponsor named in the episode's own notes (MIT
// MinusPod, github.com/ttlequals0/MinusPod; see FORK.md). A rule fires only on words that point
// to an ad, so a cold open that names a brand in passing is left alone. Foundation only.
import Foundation

public enum AdHeadRules {
  /// How many lines after a lead-in a call to action may come and still belong to the ad, and
  /// how many seconds may lie between the lead-in line's end and that line's start. A longer
  /// stretch is talk that a lead-in only announced ("more on them later"), which the model
  /// judges instead.
  public static let reach = 4
  public static let reachSeconds = 25.0
  /// Once the call to action is reached, an ad goes on while a signal comes at most this many
  /// lines apart (1: only the very next line), and the next signal line must start within
  /// `gapSeconds` of the last one's end. A line with a return cue ends the ad before it.
  public static let gap = 1
  public static let gapSeconds = 12.0
  /// How many lines around a sponsor named in the notes a call to action may be. Also how many
  /// lines apart two signals may be when a span has neither a lead-in nor such a sponsor.
  public static let near = 2

  /// The seconds of audio after which each step of a stream's head scan ends (the phone's steps).
  public static let steps: [Double] = [15, 30, 60, 90, 120, 150, 180]
  /// The steps after which the on-device model is asked.
  public static let modelSteps: Set<Double> = [30, 60, 120, 180]
  /// At this step (and any before it) only the model's sure answers count; an unsure one waits for
  /// the next model step, when the model has heard more of the ad.
  public static let sureOnlyStep = 30.0

  /// The model's answer at `step`, as far as it counts.
  public static func counted(_ answer: [AdRange], atStep step: Double) -> [AdRange] {
    step <= sureOnlyStep ? answer.filter { $0.confidence == .sure } : answer
  }

  /// The steps for a head of `seconds`: the phone's steps up to it, and the end itself when it
  /// falls between two (a head of 100 seconds ends with a step of 100). Never past the last step.
  public static func steps(upTo seconds: Double) -> [Double] {
    var result = steps.filter { $0 <= seconds }
    if let last = result.last, seconds - last > 1, seconds < (steps.last ?? 0) { result.append(seconds) }
    if result.isEmpty { result = [seconds] }
    return result
  }

  private static func regexes(_ patterns: [String], caseInsensitive: Bool = true) -> [NSRegularExpression] {
    patterns.compactMap { try? NSRegularExpression(pattern: $0, options: caseInsensitive ? [.caseInsensitive] : []) }
  }

  /// A promo code, an offer, or a web address with a path: a web address alone is not enough.
  /// The bare word "code" or "slash" is no sign ("the code is on github.com").
  private static let offers = regexes([
    #"\b(promo|coupon|discount|referral) code\b"#, #"\b(use|enter) (the )?code\b"#,
    #"\b(percent|%) off\b"#, #"\bfree trial\b"#,
    #"\.(com|net|org|io|co|fm|tv|me|ly|app|shop|store)/\w"#,
    #"\.(com|net|org|io|co|fm|tv|me|ly|app|shop|store)\s+slash\s+\w"#,
    #"\bdot (com|net|org|io|co)\s+slash\s+\w"#,
    #"\bcode\s+["“”'‘’][^"“”'‘’]{2,}["“”'‘’]"#,
  ])
  /// "code SLEEPY": the word "code" next to an all-caps word (so this list is case sensitive).
  private static let capitalCodes = regexes([#"\bcode\s+[A-Z][A-Z0-9]{2,}\b"#], caseInsensitive: false)
  /// The hosts' own things.
  private static let ownPlugs = regexes([
    #"\bpatreon\b"#, #"\b(our|the) merch\b"#, #"\bour (newsletter|other (show|podcast))\b"#,
    #"\b(leave|write) (us )?a review\b"#, #"\brate and review\b"#,
    #"\bsubscribe to (our|the) (show|podcast|channel)\b"#,
  ])
  private static let named = regexes([
    #"(?:brought to you by|sponsored by|support for this \w+ comes from|today's sponsor is)\s+([A-Z][\w'&-]*(?:\s+[A-Z][\w'&-]*){0,2})"#
  ])

  /// A web address, the same two patterns AdSignals counts.
  private static let webAddresses = regexes([
    #"\b[a-z0-9][a-z0-9-]*\.(com|net|org|io|co|fm|tv|me|ly|app|dev|shop|store)\b"#,
    #"\bdot (com|net|org|io|co)\b"#,
  ])
  private static func matches(_ list: [NSRegularExpression], _ text: String) -> Bool {
    let whole = NSRange(text.startIndex..., in: text)
    return list.contains { $0.firstMatch(in: text, options: [], range: whole) != nil }
  }

  private static func isLeadIn(_ text: String) -> Bool { matches(AdSignals.leadIns, text) }

  /// A web address, a promo code or an offer, not counting the lead-in's own words.
  private static func isCallToAction(_ text: String) -> Bool {
    var rest = text
    for lead in AdSignals.leadIns {
      rest = lead.stringByReplacingMatches(
        in: rest, options: [], range: NSRange(rest.startIndex..., in: rest), withTemplate: " ")
    }
    return AdSignals.readsLikeAd(rest, advertiser: "")
  }

  /// A call to action that is also an offer: enough to mark a line without a lead-in.
  private static func isOffer(_ text: String) -> Bool {
    isCallToAction(text) && (matches(offers, text) || matches(capitalCodes, text))
  }

  /// An offer line that can stand alone as an ad: it also holds a web address, or another
  /// call to action or a spot cue comes at most `near` lines from it. One offer line in plain
  /// talk ("that is twenty percent off the usual price") is not enough.
  private static func hasTwoSignals(_ at: Int, _ lines: [NumberedLine]) -> Bool {
    matches(webAddresses, lines[at].text)
      || callNearby(at, lines, includingSelf: false, spotCues: true)
  }

  private static func mentions(_ text: String, any names: [SponsorName]) -> Bool {
    names.contains { AdSignals.mentions(text, name: $0.text, wholeWord: $0.fromLink) }
  }

  /// Whether the line names a sponsor in a way that points to an ad. A name that is only a guess
  /// from a link counts on a line that also holds a web address, a promo code or an offer that is
  /// not the hosts' own plug.
  private static func namesSponsor(_ text: String, _ sponsors: [SponsorName]) -> Bool {
    sponsors.contains { name in
      mentions(text, any: [name])
        && (!name.fromLink || (AdSignals.hardSignal(text) && !matches(ownPlugs, text)))
    }
  }

  /// The ads in the lead-in lines of an episode, as the ranges a detector would answer (the same
  /// clean-up turns them into times). `sponsors` are the names found in the notes. All are sure,
  /// except a span that only holds closing phrases of a produced spot ("download the app",
  /// "terms apply") and no web address or offer: that one is unsure.
  public static func find(lines: [NumberedLine], sponsors: [SponsorName] = []) -> [AdRange] {
    // Indexes into `lines`; `spot` is true while only spot cues made the span.
    var spans: [(first: Int, last: Int, lead: Bool, spot: Bool)] = []
    for (at, line) in lines.enumerated() {
      if isLeadIn(line.text) {
        guard let firstCall = (at..<min(lines.count, at + reach + 1)).first(where: {
          isCallToAction(lines[$0].text) && lines[$0].start - lines[at].end <= reachSeconds
        })
        else { continue }
        spans.append((at, carried(from: firstCall, in: lines), true, false))
      } else if (isOffer(line.text) && hasTwoSignals(at, lines))
        || (namesSponsor(line.text, sponsors) && callNearby(at, lines))
      {
        spans.append((at, carried(from: at, in: lines), false, false))
      } else if AdSignals.spotCue(line.text),
        callNearby(at, lines, includingSelf: false, spotCues: true)
      {
        spans.append((at, carried(from: at, in: lines), false, true))
      }
    }
    var joined: [(first: Int, last: Int, lead: Bool, spot: Bool)] = []
    for span in spans.sorted(by: { $0.first < $1.first }) {
      if let last = joined.last, span.first <= last.last + 1 {
        joined[joined.count - 1] = (
          last.first, max(last.last, span.last), last.lead || span.lead, last.spot && span.spot
        )
      } else {
        joined.append(span)
      }
    }
    return joined.map { span in
      let text = lines[span.first...span.last].map(\.text).joined(separator: " ")
      // Only a firm name excuses the hosts' own plugs; a guess from a link never does.
      let firm = sponsors.filter { !$0.fromLink }
      let plug = !span.lead && !mentions(text, any: firm) && matches(ownPlugs, text)
      let proved = !span.spot || lines[span.first...span.last].contains { isCallToAction($0.text) }
      return AdRange(
        startLine: lines[span.first].number, endLine: lines[span.last].number,
        advertiser: plug ? "" : advertiser(in: text, sponsors: sponsors),
        kind: plug ? .ownPlug : .ad, confidence: proved ? .sure : .unsure)
    }
  }

  /// Whether a line within `near` lines of `at` is a call to action (or, with `spotCues`, a
  /// closing phrase of a produced spot).
  private static func callNearby(
    _ at: Int, _ lines: [NumberedLine], includingSelf: Bool = true, spotCues: Bool = false
  ) -> Bool {
    (max(0, at - near)...min(lines.count - 1, at + near)).contains {
      ($0 != at || includingSelf)
        && (isCallToAction(lines[$0].text) || (spotCues && AdSignals.spotCue(lines[$0].text)))
    }
  }

  /// The index of the last line that still reads as the ad: lines go on being counted while a
  /// signal comes within `gap` lines of the last one and starts within `gapSeconds` of its end. A
  /// line with a return cue is never counted, and nothing after it.
  private static func carried(from start: Int, in lines: [NumberedLine]) -> Int {
    var last = start
    var next = start + 1
    while next < lines.count, next - last <= gap {
      if AdSignals.returnCue(lines[next].text) { break }
      if isCallToAction(lines[next].text), lines[next].start - lines[last].end <= gapSeconds {
        last = next
      }
      next += 1
    }
    return last
  }

  private static func advertiser(in text: String, sponsors: [SponsorName]) -> String {
    if let name = sponsors.first(where: { mentions(text, any: [$0]) }) { return name.text }
    let whole = NSRange(text.startIndex..., in: text)
    for pattern in named {
      if let match = pattern.firstMatch(in: text, options: [], range: whole),
        let range = Range(match.range(at: 1), in: text)
      {
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:'-"))
      }
    }
    return ""
  }

  /// Ads from several sources (the rules, the model, a file kept earlier) as one list: ads that
  /// overlap or touch become one, the surer confidence and the longer one's kind and name stand.
  /// `touching` is how far apart two ads may be and still join (negative: only ads that overlap
  /// by more than that).
  public static func merge(_ ads: [FoundAd], touching: Double = 0.5) -> [FoundAd] {
    var result: [FoundAd] = []
    for ad in ads.sorted(by: { $0.start < $1.start }) {
      guard var last = result.popLast() else {
        result.append(ad)
        continue
      }
      if ad.start <= last.end + touching {
        let longer = ad.duration > last.duration ? ad : last
        last.kind = longer.kind
        last.advertiser = longer.advertiser.isEmpty ? (last.advertiser.isEmpty ? ad.advertiser : last.advertiser) : longer.advertiser
        last.confidence = max(last.confidence, ad.confidence)
        last.end = max(last.end, ad.end)
        result.append(last)
      } else {
        result.append(last)
        result.append(ad)
      }
    }
    return result
  }

  // MARK: Sponsors in the notes

  private static let notePatterns = regexes([
    #"(?:sponsored by|brought to you by|supported by)\s+([^.\n]+)"#,
    #"sponsors?\s*:\s*([^\n]+)"#,
  ])

  /// The sponsor names an episode's notes give: after "sponsored by", "brought to you by" or
  /// "Sponsors:", split at commas and "and" (tags and web addresses are left out), and then the
  /// site of each link with a path or a promo code ("betterhelp.com/show" gives "betterhelp"),
  /// except the show's own site (`showLink`), social sites, podcast apps and the hosts' own plugs.
  public static func sponsors(inNotes notes: String, showLink: URL? = nil) -> [SponsorName] {
    let plain = notes.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
    var names: [SponsorName] = []
    let whole = NSRange(plain.startIndex..., in: plain)
    for pattern in notePatterns {
      for match in pattern.matches(in: plain, options: [], range: whole) {
        guard let range = Range(match.range(at: 1), in: plain) else { continue }
        let parts = plain[range].replacingOccurrences(of: " and ", with: ",")
          .replacingOccurrences(of: " & ", with: ",").split(separator: ",")
        for part in parts {
          let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
          guard AdSignals.usableName(name), name.split(separator: " ").count <= 4,
            !name.contains("/"), !name.contains("@"), !names.contains(where: { $0.text == name })
          else { continue }
          names.append(SponsorName(name))
        }
      }
    }
    for name in SponsorNames.fromLinks(in: plain, showLink: showLink)
    where !names.contains(where: { squashed($0.text) == squashed(name.text) }) {
      names.append(name)
    }
    return names
  }

  /// A name in lower case with only its letters and digits, to tell that "Better Help" and
  /// "betterhelp" are one name.
  private static func squashed(_ name: String) -> String {
    name.lowercased().filter { $0.isLetter || $0.isNumber }
  }
}
