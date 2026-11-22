// LOFI-FORK: text rules that find the show's own promotions in transcript lines (see FORK.md).
//
// A promo is the show, its network or its publisher selling something of its own that is not this
// episode: a live tour or tickets, a paid subscription or membership, another show or its
// trailer, a book or an app. The sponsor rules (AdHeadRules) miss these because no outside brand
// pays for them. These rules run without a model: a line with a promo cue only counts when
// proof is a line or two away: a web address, a code or an offer, or a second cue that is a
// different phrase (cues from two different groups make the promo sure). The same phrase said
// twice ("the live show", "the live show") proves nothing, and neither does a soft call such as
// "go to" or "visit", so plain talk ("we were on tour, I had to go to the hospital") is left
// alone. The word lists are a first version, to be tuned against episodes that people have
// marked. Foundation only.
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

  /// One cue phrase. A strong cue asks the listener to do something or sells outright ("get your
  /// tickets", "become a member"); a weak one is also how people talk about their week ("the
  /// live show", "our tour", "early access").
  private struct Cue {
    var pattern: NSRegularExpression
    var strong: Bool
  }

  private static func cues(strong: [String], weak: [String]) -> [Cue] {
    regexes(strong).map { Cue(pattern: $0, strong: true) }
      + regexes(weak).map { Cue(pattern: $0, strong: false) }
  }

  /// The promo cues, one list for each group (live events, subscriptions, other shows, products).
  private static let cueGroups: [[Cue]] = [
    cues(
      strong: [
        #"\b(get|grab|buy|book) (your |those )?tickets\b"#,
        #"\btickets (are |go )?(on sale|available)\b"#, #"\btickets at\b"#,
        #"\bjoin us (live|in person|on stage)\b"#, #"\bcome see (us|the show)\b"#,
        #"\bsee (us|the show) live\b"#,
      ],
      weak: [
        #"\blive (show|shows|taping|event|events|tour|on stage)\b"#, #"\bour (live )?tour\b"#,
        #"\bwe(['’]re| are) (going|heading) on tour\b"#,
      ]),
    cues(
      strong: [
        #"\b(become|becoming) a (subscriber|member|supporter|patron)\b"#,
        #"\bsubscribe to (the|our) [\w' ]{0,30}?\b(times|post|journal|atlantic|new yorker|economist|magazine|plus|premium)\b"#,
        #"\bsupport (our|this) (journalism|reporting|work)\b"#, #"\bsubscribe (today|now) at\b"#,
      ],
      weak: [
        #"\bour (subscribers|members) (get|can|have|also)\b"#,
        #"\b(ad[- ]free|bonus episodes?|early access)\b"#,
      ]),
    cues(
      strong: [
        #"\b(listen|follow|search for|find) [^.?!]{0,60}wherever you (get|listen to) (your )?podcasts\b"#,
        #"\bcheck out (our|the) (new |other |latest )?(podcast|series)\b"#,
        #"\bcheck out (our (new |other |latest )?|the (new |other |latest ))show\b"#,
        #"\bhere['’]s (a|the) (preview|trailer)\b"#,
      ],
      weak: [
        #"\b(new|another) (podcast|show|series) from\b"#,
        #"\bfrom the (makers|creators|team|people) (of|behind)\b"#,
        #"\bnew episodes (every|each|drop|are out|out)\b"#,
      ]),
    cues(
      strong: [
        #"\b(download|get) our [\w' ]{1,30}? app\b"#,
        #"\bsign up (for|at)\b[^.?!]{0,40}\bnewsletter\b"#,
        #"\b(my|our) (new )?book\b[^.?!]{0,60}\b(available|out now|wherever books|in stores|on sale)\b"#,
      ],
      weak: [#"\bpre-?order\b"#]),
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

  /// What a line holds: the groups with a cue on it (one bit for each group), which cue phrases
  /// (one number for each pattern, counted through the groups) and whether one of them is strong.
  private struct Heard {
    var groups = 0
    var phrases: Set<Int> = []
    var strong = false

    mutating func add(_ other: Heard) {
      groups |= other.groups
      phrases.formUnion(other.phrases)
      strong = strong || other.strong
    }

    /// Cues from two groups, or two different phrases of which one is strong, prove a promo. One
    /// phrase said twice, or two weak ones, are how people talk.
    var proves: Bool { groups.nonzeroBitCount > 1 || (phrases.count > 1 && strong) }
  }

  /// Two patterns that match the same words ("come see us" and "see us live" in "come see us
  /// live") are one phrase: a later match that overlaps a counted one adds no phrase.
  private static func heard(_ text: String) -> Heard {
    let whole = NSRange(text.startIndex..., in: text)
    var found = Heard()
    var counted: [NSRange] = []
    var number = 0
    for (group, list) in cueGroups.enumerated() {
      for cue in list {
        if let match = cue.pattern.firstMatch(in: text, options: [], range: whole)?.range {
          found.groups |= 1 << group
          found.strong = found.strong || cue.strong
          if !counted.contains(where: { NSIntersectionRange($0, match).length > 0 }) {
            found.phrases.insert(number)
            counted.append(match)
          }
        }
        number += 1
      }
    }
    return found
  }

  /// A web address, a code or an offer: the proof a promo needs. Soft calls such as "go to" or
  /// "visit" are plain talk and prove nothing.
  private static func isCall(_ text: String) -> Bool {
    AdSignals.hardSignal(text) || matches(webAddresses, text)
  }

  /// The promos in these lines, as the ranges a detector would answer. Every range has kind
  /// `.promo`. A line with a return cue holds no signal and ends a promo before it.
  public static func find(lines: [NumberedLine]) -> [AdRange] {
    let returns = lines.map { AdSignals.returnCue($0.text) }
    let cues = lines.indices.map { returns[$0] ? Heard() : heard(lines[$0].text) }
    let callAt = lines.indices.map { !returns[$0] && isCall(lines[$0].text) }
    let isSignal: (Int) -> Bool = { cues[$0].groups != 0 || callAt[$0] }

    var spans: [(first: Int, last: Int)] = []
    for at in lines.indices where cues[at].groups != 0 {
      var first = at
      var last = at
      var found = callAt[at]
      var around = cues[at]
      var before = at - 1
      while before >= max(0, at - near), !returns[before] {
        if isSignal(before) {
          first = before
          around.add(cues[before])
          found = found || callAt[before]
        }
        before -= 1
      }
      var after = at + 1
      while after <= min(lines.count - 1, at + near), !returns[after] {
        if isSignal(after) {
          last = after
          around.add(cues[after])
          found = found || callAt[after]
        }
        after += 1
      }
      if found || around.proves {
        spans.append((first, carried(from: last, in: lines, returns: returns, isSignal: isSignal)))
      }
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
        || range.reduce(0) { $0 | cues[$1].groups }.nonzeroBitCount > 1
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
