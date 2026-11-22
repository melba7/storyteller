// LOFI-FORK: the ads a Mac taught the phone, read as remembered ads (see FORK.md).
//
// A Mac tool marks the ads of many episodes and writes `ad-library.json`. This reads that file into
// a `KnownAds` of seeds, which `KnownAds.find(in:show:seeds:)` uses beside the phone's own memory.
// Text only. Foundation only.
import Foundation

/// The taught ads as the phone gets them, in `ad-library.json`.
public struct AdLibraryFile: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "ad-library.json"

  public struct Entry: Codable, Sendable, Equatable {
    /// The app's id of the show it belongs to; "" when it has none.
    public var show: String
    /// "show": only in that show; "all": in any show.
    public var scope: String
    /// "sponsor", "network_promo", "host_ask" or "intro_credits".
    public var sort: String
    public var who: String
    /// The words as transcribed, punctuation and case as they came.
    public var text: String
    /// Seconds.
    public var length: Double
    /// In how many episodes the Mac met it.
    public var seen: Int
  }

  public var version: Int
  public var ads: [Entry]

  public init(version: Int = currentVersion, ads: [Entry] = []) {
    self.version = version
    self.ads = ads
  }

  private enum CodingKeys: String, CodingKey { case version, ads }

  /// An entry with a wrong type is skipped, not allowed to fail the whole file.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    var list = try container.nestedUnkeyedContainer(forKey: .ads)
    var entries: [Entry] = []
    while !list.isAtEnd {
      if let entry = try? list.decode(Entry.self) {
        entries.append(entry)
      } else {
        _ = try? list.decode(Skipped.self)  // moves past the bad entry
      }
    }
    ads = entries
  }

  /// Reads any value and keeps nothing.
  private struct Skipped: Decodable {
    init(from decoder: Decoder) throws {}
  }
}

public enum AdLibrary {
  /// An ad of a sensible length, in seconds.
  static let lengths = 8.0...300.0

  static func usable(length: Double) -> Bool { length.isFinite && lengths.contains(length) }

  /// The taught ads as remembered ads. Nothing when the data is not this format or version.
  public static func seeds(from data: Data, now: Date) -> KnownAds {
    guard let file = try? JSONDecoder().decode(AdLibraryFile.self, from: data),
      file.version == AdLibraryFile.currentVersion
    else { return KnownAds() }
    var ads: [KnownAd] = []
    var at: [String: Int] = [:]  // where an ad is in `ads`, by text, show and scope
    for entry in file.ads {
      guard let kind = AdKind(sort: entry.sort), usable(length: entry.length),
        entry.scope == "all" || (entry.scope == "show" && !entry.show.isEmpty)
      else { continue }
      let words = entry.text.split(whereSeparator: \.isWhitespace)
        .compactMap { KnownAds.normalise(String($0)) }.prefix(KnownAds.mostWords)
      guard words.count >= KnownAds.fewestWords else { continue }
      let text = words.joined(separator: " ")
      let seen = max(entry.seen, 1)
      let key = [text, entry.show, entry.scope].joined(separator: "\u{1F}")
      if let found = at[key] {
        ads[found].seen = max(ads[found].seen, seen)
        continue
      }
      at[key] = ads.count
      ads.append(
        KnownAd(
          showId: entry.show, advertiser: entry.who, kind: kind, text: text, length: entry.length,
          seen: seen, lastSeen: now, scope: entry.scope))
    }
    return KnownAds(ads: ads)
  }
}

extension AdKind {
  /// The kind for one of the Mac's sort names, nil for any other word.
  public init?(sort: String) {
    switch sort {
    case "sponsor": self = .ad
    case "network_promo": self = .promo
    case "host_ask": self = .ownPlug
    case "intro_credits": self = .credits
    default: return nil
    }
  }
}
