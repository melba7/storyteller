// LOFI-FORK: text rules that find the show's own promotions in transcript lines (see FORK.md).
//
// A promo is the show, its network or its publisher selling something of its own that is not this
// episode: a live tour or tickets, a paid subscription or membership, another show or its
// trailer, a book or an app. The sponsor rules (AdHeadRules) miss these because no outside brand
// pays for them. These rules run without a model: a line with a promo cue only counts when
// proof is a line or two away: a web address, a code or an offer, or a second cue line (cues
// from two different groups make the promo sure). A soft call such as "go to" or "visit" is no proof, so plain talk ("we were on tour,
// I had to go to the hospital") is left alone. The word lists are a first
// version, to be tuned against episodes that people have marked. Foundation only.
import Foundation

public enum AdPromoRules {
  /// How many lines apart two signals of one promo may be (before or after a cue line).
  public static let near = 2
  /// Once a promo is found it goes on while the next signal line comes at most this many lines
  /// further (1: only the very next line).
  public static let gap = 1
  /// The next signal line must also start within this many seconds of the last counted line's end.
  public static let gapSeconds = 12.0

  private static func regexes(_ patterns: [String]) -> [NSRegularExpression] {
    patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
  }

  /// The promo cues, one list for each group (live events, subscriptions, other shows, products).
  private static let cueGroups: [[NSRegularExpression]] = [
    regexes([
      #"\b(get|grab|buy|book) (your |those )?tickets\b"#, #"\btickets (are |go )?(on sale|available)\b"#,
      #"\btickets at\b"#, #"\blive (show|shows|taping|event|events|tour|on stage)\b"#,
      #"\bour (live )?tour\b"#, #"\bwe(['’]re| are) (going|heading) on tour\b"#, #"\bjoin us (live|in person|on stage)\b"#,
      #"\bcome see (us|the show)\b"#, #"\bsee (us|the show) live\b"#,
    ]),
    regexes([
      #"\b(become|becoming) a (subscriber|member|supporter|patron)\b"#,
      #"\bsubscribe to (the|our) [\w' ]{0,30}?\b(times|post|journal|atlantic|new yorker|economist|magazine|plus|premium)\b"#,
      #"\bour (subscribers|members) (get|can|have|also)\b"#, #"\b(ad[- ]free|bonus episodes?|early access)\b"#,
      #"\bsupport (our|this) (journalism|reporting|work)\b"#, #"\bsubscribe (today|now) at\b"#,
    ]),
    regexes([
      #"\b(new|another) (podcast|show|series) from\b"#, #"\bfrom the (makers|creators|team|people) (of|behind)\b"#,
      #"\b(listen|follow|search for|find) [^.?!]{0,60}wherever you (get|listen to) (your )?podcasts\b"#,
      #"\bcheck out (our|the) (new |other |latest )?(podcast|series)\b"#, #"\bcheck out (our (new |other |latest )?|the (new |other |latest ))show\b"#,
      #"\bhere['’]s (a|the) (preview|trailer)\b"#, #"\bnew episodes (every|each|drop|are out|out)\b"#,
    ]),
    regexes([
      #"\b(download|get) our [\w' ]{1,30}? app\b"#, #"\bsign up (for|at)\b[^.?!]{0,40}\bnewsletter\b"#,
      #"\bpre-?order\b"#,
      #"\b(my|our) (new )?book\b[^.?!]{0,60}\b(available|out now|wherever books|in stores|on sale)\b"#,
    ]),
  ]

  /// A web address, the same two patterns AdHeadRules counts.
  private static let webAddresses = regexes([
    #"\b[a-z0-9][a-z0-9-]*\.(com|net|org|io|co|fm|tv|me|ly|app|dev|shop|store)\b"#,
    #"\bdot (com|net|org|io|co)\b"#,
  ])

  private static func matches(_ list: [NSRegularExpression], _ text: String) -> Bool {
    let whole = NSRange(text.startIndex..., in: text)
    return list.contains { $0.firstMatch(in: text, options: [], range: whole) != nil }
  }

  /// The groups with a cue on the line, one bit for each group.
  private static func cueMask(_ text: String) -> Int {
    cueGroups.enumerated().reduce(0) { $0 | (matches($1.element, text) ? 1 << $1.offset : 0) }
  }

  /// A web address, a code or an offer: the proof a promo needs. Soft calls such as "go to" or
  /// "visit" are plain talk and prove nothing.
  private static func isCall(_ text: String) -> Bool {
    AdSignals.hardSignal(text) || matches(webAddresses, text)
  }

  private static func bits(_ mask: Int) -> Int { mask.nonzeroBitCount }

  /// The promos in these lines, as the ranges a detector would answer. Every range has kind
  /// `.promo`. A line with a return cue holds no signal and ends a promo before it.
  public static func find(lines: [NumberedLine]) -> [AdRange] {
    let returns = lines.map { AdSignals.returnCue($0.text) }
    let masks = lines.indices.map { returns[$0] ? 0 : cueMask(lines[$0].text) }
    let callAt = lines.indices.map { !returns[$0] && isCall(lines[$0].text) }
    let isSignal: (Int) -> Bool = { masks[$0] != 0 || callAt[$0] }

    var spans: [(first: Int, last: Int)] = []
    for at in lines.indices where masks[at] != 0 {
      var first = at
      var last = at
      var found = callAt[at] || bits(masks[at]) > 1
      var seen = masks[at]
      var cueLines = 1
      var before = at - 1
      while before >= max(0, at - near), !returns[before] {
        if isSignal(before) { first = before; seen |= masks[before]; cueLines += masks[before] != 0 ? 1 : 0; found = found || callAt[before] }
        before -= 1
      }
      var after = at + 1
      while after <= min(lines.count - 1, at + near), !returns[after] {
        if isSignal(after) { last = after; seen |= masks[after]; cueLines += masks[after] != 0 ? 1 : 0; found = found || callAt[after] }
        after += 1
      }
      if found || bits(seen) > 1 || cueLines > 1 { spans.append((first, carried(from: last, in: lines, returns: returns, isSignal: isSignal))) }
    }

    var joined: [(first: Int, last: Int)] = []
    for span in spans.sorted(by: { $0.first < $1.first }) {
      if let previous = joined.last, span.first <= previous.last + 1 {
        joined[joined.count - 1] = (previous.first, max(previous.last, span.last))
      } else {
        joined.append(span)
      }
    }
    return joined.map { span in
      let range = span.first...span.last
      let sure = range.contains { matches(webAddresses, lines[$0].text) }
        || bits(range.reduce(0) { $0 | masks[$1] }) > 1
      return AdRange(
        startLine: lines[span.first].number, endLine: lines[span.last].number, advertiser: "",
        kind: .promo, confidence: sure ? .sure : .unsure)
    }
  }

  /// The index of the last line that still reads as the promo: lines go on being counted while a
  /// cue or call comes within `gap` lines of the last one and starts within `gapSeconds` of its
  /// end. A line with a return cue is never counted, and nothing after it.
  private static func carried(
    from start: Int, in lines: [NumberedLine], returns: [Bool], isSignal: (Int) -> Bool
  ) -> Int {
    var last = start
    var next = start + 1
    while next < lines.count, next - last <= gap {
      if returns[next] { break }
      if isSignal(next), lines[next].start - lines[last].end <= gapSeconds { last = next }
      next += 1
    }
    return last
  }
}
