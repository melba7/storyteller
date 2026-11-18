// LOFI-FORK: whether a line still reads as part of an ad (see FORK.md).
//
// The idea of carrying an ad's end on while the next lines still read as the ad (its sponsor,
// a web address, a promo code) comes from MinusPod (MIT, github.com/ttlequals0/MinusPod).
import Foundation

public enum AdSignals {
  static func regexes(_ patterns: [String]) -> [NSRegularExpression] {
    patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
  }

  private static let hard = regexes([
    // A web address: "betterhelp.com/show", "example dot com".
    #"\b[a-z0-9][a-z0-9-]*\.(com|net|org|io|co|fm|tv|me|ly|app|dev|shop|store)\b"#,
    #"\bdot (com|net|org|io|co)\b"#,
    // A promo code or an offer.
    #"\b(use|enter|with|promo|offer|discount|coupon|referral) code\b"#,
    #"\b(percent|%) off\b"#,
    #"\bfree trial\b"#,
    #"\bbrought to you by\b"#,
  ])

  /// Words an ad's closing lines use. Alone they prove nothing ("go to the store"), so they only
  /// carry a line that also names the advertiser.
  private static let soft = regexes([
    #"\bthanks( again)? to\b"#, #"\bthank you to\b"#, #"\bgo to\b"#, #"\bhead to\b"#,
    #"\bvisit\b"#, #"\bcheck out\b"#, #"\bsign up\b"#, #"\blearn more\b"#,
    #"\bagain,? that['’]s\b"#,
  ])

  /// Words the hosts use when the show is back.
  private static let returns = regexes([
    #"\bwelcome back\b"#, #"\b(we['’]re|we are) back\b"#,
    #"\bback to the (show|episode|conversation|interview)\b"#, #"\blet['’]s get back\b"#,
    #"\bnow,? back to\b"#, #"\bwhere were we\b"#, #"\bwelcome to\b"#, #"\bi['’]m your host\b"#,
    #"\bon today['’]s (show|episode)\b"#, #"\bin this episode\b"#, #"\bmy guest today\b"#,
    #"\bjoining me (today|now)\b"#,
  ])

  /// Words the hosts use to bridge two ads of one break ("we'll be right back after one more
  /// word from our sponsor").
  private static let breaks = regexes([
    #"\bright back\b"#, #"\bafter (the|this) break\b"#, #"\bquick break\b"#, #"\bone more\b"#,
    #"\ba word from\b"#, #"\bsupport for\b"#, #"\bsponsors?\b"#, #"\balso brought\b"#,
  ])

  static func matches(_ list: [NSRegularExpression], _ text: String) -> Bool {
    let whole = NSRange(text.startIndex..., in: text)
    return list.contains { $0.firstMatch(in: text, options: [], range: whole) != nil }
  }

  /// Names that say nothing about who the sponsor is.
  private static let emptyNames: Set<String> = ["", "none", "unknown", "n/a", "the show", "sponsor"]

  /// Whether a name is worth looking for in the lines after an ad.
  static func usableName(_ advertiser: String) -> Bool {
    let name = advertiser.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return name.count >= 3 && !emptyNames.contains(name)
  }

  /// Whether the line says the advertiser's name (see `mentions`).
  public static func namesAdvertiser(_ text: String, advertiser: String) -> Bool {
    mentions(text, name: advertiser)
  }

  /// A web address, a promo code or an offer, or "brought to you by": proof that the line sells.
  public static func hardSignal(_ text: String) -> Bool { matches(hard, text) }

  /// A phrase that closes an ad, but that plain talk uses as well.
  public static func softCue(_ text: String) -> Bool { matches(soft, text) }

  /// A phrase that says the show is back (or begins): the ad is over by this line.
  public static func returnCue(_ text: String) -> Bool { matches(returns, text) }

  /// A phrase that bridges two ads of one break.
  public static func breakCue(_ text: String) -> Bool { matches(breaks, text) }

  /// Whether the line mentions the advertiser, a web address, a promo code or an offer.
  public static func readsLikeAd(_ text: String, advertiser: String) -> Bool {
    namesAdvertiser(text, advertiser: advertiser) || hardSignal(text)
  }

  /// The longest line that only names the advertiser and still belongs to the ad.
  static let shortLine = 8

  /// Whether a line after an ad's last line is carried into it: it has no return cue and holds
  /// a hard signal, or names the advertiser and has a soft cue or is at most `shortLine` words.
  static func carriesOn(_ text: String, advertiser: String) -> Bool {
    if returnCue(text) { return false }
    if hardSignal(text) { return true }
    guard namesAdvertiser(text, advertiser: advertiser) else { return false }
    return softCue(text) || text.split(whereSeparator: \.isWhitespace).count <= shortLine
  }
}
