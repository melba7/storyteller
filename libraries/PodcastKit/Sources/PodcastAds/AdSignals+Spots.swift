// LOFI-FORK: the close of a produced ad spot (see FORK.md).
//
// A produced spot, the kind a network inserts, has no host lead-in ("this episode is brought to
// you by"), but it ends the way every spot does: a legal line, a store line, an app to download.
import Foundation

extension AdSignals {
  /// The legal lines that end a spot. A line that ends with one is the spot's closer.
  private static let terms = regexes([
    #"\bterms( and conditions)? apply\b"#, #"\brestrictions apply\b"#,
    #"\bsee (site|store|website) for details\b"#, #"\bmember fdic\b"#,
    #"\b(must be|for ages) (18|21)\b"#, #"\bgamble responsibly\b"#,
  ])

  /// The store lines of a spot.
  private static let stores = regexes([
    #"\b(for a )?limited time\b"#, #"\bdownload the .{1,30} app\b"#,
    #"\bavailable (now|today) (at|on|in|wherever)\b"#,
    #"\bwherever you (get|listen to) (your )?podcasts\b"#, #"\bstreaming now\b"#,
    #"\bin theaters\b"#, #"\b1[- ]8(00|88|77|66)\b"#,
  ])

  /// The most words that may follow a terms cue for the line to still end with it ("must be 21
  /// or older").
  private static let wordsAfterTerms = 3

  /// A phrase that a produced spot says and plain talk rarely does. Alone it is weak ("wherever
  /// you get your podcasts" is also said by hosts about their own show), so it only counts as
  /// one signal, never as enough.
  public static func spotCue(_ text: String) -> Bool { matches(terms, text) || matches(stores, text) }

  /// Whether the line ends with a legal line of a spot: the spot is over, and the line after it
  /// belongs to the ad only when it holds a hard signal.
  static func endsWithTermsCue(_ text: String) -> Bool {
    let whole = NSRange(text.startIndex..., in: text)
    return terms.contains { regex in
      regex.matches(in: text, options: [], range: whole).contains { match in
        guard let range = Range(match.range, in: text) else { return false }
        let after = text[range.upperBound...].split { !$0.isLetter && !$0.isNumber }
        return after.count <= wordsAfterTerms
      }
    }
  }
}
