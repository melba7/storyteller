// LOFI-FORK: whether a line still reads as part of an ad (see FORK.md).
//
// The idea of carrying an ad's end on while the next lines still read as the ad (its sponsor,
// a web address, a promo code) comes from MinusPod (MIT, github.com/ttlequals0/MinusPod).
import Foundation

public enum AdSignals {
  private static let patterns: [NSRegularExpression] = [
    // A web address: "betterhelp.com/show", "example dot com".
    #"\b[a-z0-9][a-z0-9-]*\.(com|net|org|io|co|fm|tv|me|ly|app|dev|shop|store)\b"#,
    #"\bdot (com|net|org|io|co)\b"#,
    // A promo code or an offer.
    #"\b(use|enter|with|promo|offer|discount|coupon|referral) code\b"#,
    #"\b(percent|%) off\b"#,
    #"\bfree trial\b"#,
    #"\bbrought to you by\b"#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

  /// Names that say nothing about who the sponsor is.
  private static let emptyNames: Set<String> = ["", "none", "unknown", "n/a", "the show", "sponsor"]

  /// Whether a name is worth looking for in the lines after an ad.
  static func usableName(_ advertiser: String) -> Bool {
    let name = advertiser.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return name.count >= 3 && !emptyNames.contains(name)
  }

  /// Whether the line mentions the advertiser, a web address, a promo code or an offer.
  public static func readsLikeAd(_ text: String, advertiser: String) -> Bool {
    if usableName(advertiser),
      text.range(
        of: advertiser.trimmingCharacters(in: .whitespacesAndNewlines),
        options: [.caseInsensitive, .diacriticInsensitive]) != nil
    {
      return true
    }
    let whole = NSRange(text.startIndex..., in: text)
    return patterns.contains { $0.firstMatch(in: text, options: [], range: whole) != nil }
  }
}
