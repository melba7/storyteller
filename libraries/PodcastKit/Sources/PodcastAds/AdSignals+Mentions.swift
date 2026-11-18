// LOFI-FORK: whether a line says a sponsor's name, however the speech recogniser spaced it (see FORK.md).
import Foundation

extension AdSignals {
  /// How many words a name spelled out in pieces ("better help dot com") may be spread over.
  private static let mostPieces = 4

  /// Whether the text says the name. A name is found as it is written (any case, any accents,
  /// even inside a longer word: "Quokka's"), and also when the recogniser has split it into
  /// words or put "dot" next to it: "better help dot com" says "betterhelp". The pieces must
  /// start and end at word edges, with at most one letter left over (a plural), so two plain
  /// words that happen to run together ("the zoo moves") never say "Zoom". A name that is not
  /// usable (see `usableName`) is never said.
  public static func mentions(_ text: String, name: String) -> Bool {
    guard usableName(name) else { return false }
    let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
      return true
    }
    let key = pieces(of: wanted).joined()
    guard key.count >= 4 else { return false }
    let spoken = pieces(of: text).filter { $0 != "dot" }
    for first in spoken.indices {
      var joined = ""
      for piece in spoken[first...].prefix(mostPieces) {
        joined += piece
        if joined.count >= key.count {
          if joined.hasPrefix(key), joined.count - key.count <= 1 { return true }
          break
        }
        if !key.hasPrefix(joined) { break }
      }
    }
    return false
  }

  /// The lower case, accent-free runs of letters and digits in the text.
  private static func pieces(of text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
  }
}
