// LOFI-FORK: one key per feed address, the same one the app's TypeScript makes (see FORK.md).
import Foundation

/// A port of `feedKey` in applePodcasts.ts. The Mac names a show by its feed address and the
/// phone by its own id; the two meet through this key.
public enum FeedKey {
  private static let scheme = try? NSRegularExpression(
    pattern: #"^(?:[a-z][a-z0-9+.-]*:)?//([^/?]*)(.*)$"#, options: [.caseInsensitive])
  private static let trailing = try? NSRegularExpression(pattern: #"/+(?=\?|\z)"#)

  /// No scheme, no `www.`, the host in lower case, no fragment and no closing slash. The path and
  /// query keep their case.
  public static func key(_ address: String) -> String {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
    let whole = NSRange(text.startIndex..., in: text)
    var host: String
    var rest: String
    if let match = scheme?.firstMatch(in: text, range: whole),
      let hostRange = Range(match.range(at: 1), in: text),
      let restRange = Range(match.range(at: 2), in: text)
    {
      host = String(text[hostRange])
      rest = String(text[restRange])
    } else {
      host = String(text.prefix { $0 != "/" && $0 != "?" })
      rest = String(text.dropFirst(host.count))
    }
    host = host.lowercased()
    if host.hasPrefix("www.") { host.removeFirst(4) }
    // Only the first run of slashes that ends the path (or comes before the query) goes.
    let range = NSRange(rest.startIndex..., in: rest)
    if let match = trailing?.firstMatch(in: rest, range: range), let found = Range(match.range, in: rest) {
      rest.removeSubrange(found)
    }
    return host + rest
  }
}
