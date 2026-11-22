// LOFI-FORK: reads the files of the Mac's teaching run the way the Mac writes them (see FORK.md).
//
// The Mac names a show by its feed address (`"feed"`); the app names it by its own id. The scorecard
// and the phone both read the same files, and differ only in how a feed address becomes a show id.
// Foundation only.
import Foundation

public enum MacFiles {
  /// The show id for a feed address, or nil when the reader does not know that show.
  public typealias ShowOf = @Sendable (String) -> String?

  /// The scorecard's way: the feed address is the show id.
  public static let feedAsShow: ShowOf = { $0 }

  /// The phone's way: `shows` maps a feed key (`FeedKey.key`) to the app's show id.
  public static func table(_ shows: [String: String]) -> ShowOf {
    { shows[FeedKey.key($0)] }
  }

  /// Reads one value of a list and keeps nil when it is of the wrong shape.
  private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
  }

  /// A show of the habits file, as the Mac writes it (with `feed`) or as the phone saves it
  /// (with `id`). Any field of the wrong type is nil.
  private struct HabitsEntry: Decodable {
    var feed: String?
    var id: String?
    var episodes: Int?
    var opensWithAd: Int?
    var openingEnds: Double?

    private enum Keys: String, CodingKey { case feed, id, episodes, opensWithAd, openingEnds }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      feed = try? box.decode(String.self, forKey: .feed)
      id = try? box.decode(String.self, forKey: .id)
      episodes = try? box.decode(Int.self, forKey: .episodes)
      opensWithAd = try? box.decode(Int.self, forKey: .opensWithAd)
      openingEnds = try? box.decode(Double.self, forKey: .openingEnds)
    }
  }

  private struct HabitsFile: Decodable {
    var version: Int?
    var shows: [Lossy<HabitsEntry>]
  }

  /// The shows as `ShowHabits` reads them.
  private struct PhoneHabits: Encodable {
    struct Show: Encodable {
      var id: String
      var episodes: Int
      var opensWithAd: Int
      var openingEnds: Double?
    }
    var version = ShowHabits.currentVersion
    var shows: [Show]
  }

  /// The habits of `show-habits.json` (or the scorecard's `habits.json`), each show named by
  /// `showOf`. A show it does not know, or that has no feed and no id, is left out. Nil when the
  /// data is not a version 1 file with a list of shows. An entry with an `id` and no `feed` is in
  /// the phone's own shape and is kept as it is.
  public static func habits(data: Data, showOf: ShowOf) -> ShowHabits? {
    guard let file = try? JSONDecoder().decode(HabitsFile.self, from: data),
      (file.version ?? ShowHabits.currentVersion) == ShowHabits.currentVersion
    else { return nil }
    let shows = file.shows.compactMap { item -> PhoneHabits.Show? in
      guard let entry = item.value, let episodes = entry.episodes, let opens = entry.opensWithAd
      else { return nil }
      let id: String
      if let feed = entry.feed {
        guard let known = showOf(feed) else { return nil }
        id = known
      } else if let own = entry.id {
        id = own
      } else {
        return nil
      }
      return PhoneHabits.Show(id: id, episodes: episodes, opensWithAd: opens, openingEnds: entry.openingEnds)
    }
    guard let phone = try? JSONEncoder().encode(PhoneHabits(shows: shows)) else { return nil }
    return ShowHabits(data: phone)
  }

  /// The taught ads of `ad-library.json` as remembered ads, each show named by `showOf`. An ad of
  /// one show whose feed `showOf` does not know is left out; an ad of every show is kept, with
  /// no show when its feed is not known. An entry with a `show` and no `feed` is in the phone's
  /// own shape and is kept as it is. Nothing when the data is not a version 1 file.
  public static func library(data: Data, now: Date, showOf: ShowOf) -> KnownAds {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let ads = root["ads"] as? [Any]
    else { return KnownAds() }
    let rewritten = ads.compactMap { item -> [String: Any]? in
      guard var entry = item as? [String: Any] else { return nil }
      guard let feed = entry["feed"] as? String else { return entry }
      if let show = showOf(feed) {
        entry["show"] = show
      } else if (entry["scope"] as? String) == "all" {
        entry["show"] = ""
      } else {
        return nil
      }
      return entry
    }
    let version = root["version"] ?? AdLibraryFile.currentVersion
    guard let phone = try? JSONSerialization.data(withJSONObject: ["version": version, "ads": rewritten])
    else { return KnownAds() }
    return AdLibrary.seeds(from: phone, now: now)
  }
}
