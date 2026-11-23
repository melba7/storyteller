// LOFI-FORK: the phone's memory of what a show's last three episodes said, so a stretch that comes
// back is found (see FORK.md and the round plan, idea 2, the word half). Foundation only; a plain
// value with no clock, no file access and no shared state.
//
// WHAT IT KEEPS. For each show the last three episodes, as the hashes of every run of five words
// (never the words), in the order they were said. A new episode is compared with them: a stretch
// of it whose runs are also in an older episode of the same show, at least 15 seconds and 25 words
// long, is returned as an unsure ad from the finder "repeat-words". The memory only FINDS. The
// caller decides, from `FinderGuard.mode`, whether to ask the listener or to skip.
//
// THE API (the file is Application Support/Podcasts/repeat-words.json; the lock, the folder and
// the atomic write belong to the phone code that wires this in):
//
//   RepeatedWords.fileName                          "repeat-words.json"
//   RepeatedWords()                                 an empty memory
//   RepeatedWords.read(_ data: Data) -> RepeatedWords    damaged, unknown version, too big, over
//                                                   a cap or not what this writes: empty
//   var data: Data                                  the file's bytes, written whole and atomically
//
//   func find(show:episode:lines:duration:now:already:) -> [FoundAd]
//   mutating func remember(show:episode:lines:now:)
//   mutating func deny(show:lines:start:end:now:)
//
// HOW THE PHONE MUST USE IT.
//  1. `lines` are the lines of a FINAL transcript (`Transcript.lines`), `duration` the episode's
//     length in seconds (0 when not known), `show` and `episode` stable names (the feed key and
//     the episode id). A name is cut to 80 characters; an empty one means nothing is stored.
//  2. Run `find` after the older finders have written their ads, and pass what they found as
//     `already`: nothing returned overlaps it, and every piece stays a second away from it, so
//     `AdJoin` (which joins ads that touch) can never fuse a new ad onto an old one.
//  3. Every ad returned is `.ad`, `.unsure`, has no advertiser and `source` "repeat-words". The
//     kind may be changed by the caller (the word model's best class for those lines).
//  4. `remember` AFTER `find`, once per episode. An episode that is already stored is left alone,
//     so asking twice stores it once, and `find` never compares an episode with itself.
//  5. `deny` when the listener says a stretch is not an ad, or undoes a skip made from this
//     finder: it needs the same `lines` and the ad's start and end. The same words are then not
//     offered again for 60 days.
//  6. One instance behind one lock; change it, then write `data` to disk before letting go.
//
// WHAT IS FOUND, exactly (all of it in `RepeatedWords+Find.swift`):
//  - Nothing in the first minute (`firstMinute`): `ShowOpenings` owns it.
//  - A stretch is at least 15 s (`KnownAds.shortest`), at least 25 words (`KnownAds.fewestWords`)
//    and at most 300 s (`AdRules.maxLength`; a longer repeat is dropped, like the clean-up does).
//  - A few changed words are fine: runs may be missing for up to 7 in a row inside a stretch.
//  - An episode of which `AdRules.shareLimit` is repeated (a re-run, a "best of") gives nothing.
//
// BYTE ACCOUNTING (the file is JSON with no spaces; each hash is 4 bytes, which JSON writes as
// base64, 16/3 or about 5.33 characters; slashes are not escaped). The caps are `mostEpisodes` 3 a
// show, `mostShows` 60 and `mostHashesInAll` 1,200,000 hashes. The largest file that the caps
// allow, with names of 80 characters and five stretches denied for every show, is:
//   hashes    60 shows x 3 episodes x 6,666 hashes = 1,199,880, as 180 strings of 35,552  6,399,360
//   episodes  180 x ({"hashes":"","id":""} is 21 characters, plus the 80 of the name)       18,180
//   denied    300 x (100 hashes as 536 characters, plus {"at":1800000000,"hashes":""} of 29)
//                                                                                          169,500
//   shows     60 x ({"denied":[],"episodes":[],"id":""} is 35, plus 80), 419 commas and the
//             outer {"shows":[],"version":1} of 24                                            7,343
// which is 6,594,383 bytes, about 6.6 MB, under the 7 MB the round allows. `maxFileBytes` is 7 MiB
// (7,340,032): a file over it reads as empty, and so does one over any single cap. A real show has
// fewer, shorter episodes: one hour is about 9,000 words, so 9,000 hashes and 48 KB; three of them
// and 60 shows would be 8.6 MB, so the shows heard from longest ago go first, whichever of the 60
// shows and the 1,200,000 hashes is reached first. An episode is cut at `mostWords` (60,000
// words, over six hours).
import Foundation
import PodcastTranscripts

public struct RepeatedWords: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "repeat-words.json"
  /// The finder's name in `FoundAd.source` and in `FinderGuard`.
  public static let source = "repeat-words"

  /// How many episodes of one show, shows, and hashes in all are kept.
  public static let mostEpisodes = 3
  public static let mostShows = 60
  public static let mostHashesInAll = 1_200_000
  /// Only this many words of one episode are read. Its hashes are four fewer.
  public static let mostWords = 60_000
  /// A file bigger than this reads as empty.
  public static let maxFileBytes = 7 * 1024 * 1024
  /// Stretches the listener said are not ads, kept for each show, how many of a stretch's hashes
  /// are kept (spread over it) and for how many days.
  public static let mostDenied = 5
  public static let deniedSamples = 100
  public static let keepDeniedDays = 60.0

  /// One episode of a show: its name and the hashes of its runs, as bytes (`SpokenRuns.pack`).
  struct Episode: Codable, Sendable, Equatable {
    var id: String
    var hashes: Data
  }

  /// A stretch the listener said is not an ad: when (seconds since 1970) and some of its hashes.
  struct Denied: Codable, Sendable, Equatable {
    var at: Int
    var hashes: Data
  }

  struct Show: Codable, Sendable, Equatable {
    var id: String
    /// The oldest first.
    var episodes: [Episode]
    /// The oldest first.
    var denied: [Denied]
  }

  public var version: Int
  /// The show heard from longest ago first: a show that is heard from moves to the end.
  var shows: [Show]

  public init() {
    version = Self.currentVersion
    shows = []
  }

  // MARK: The file

  /// The memory in `data`. Bytes that are missing, too many, damaged, of another version or over
  /// a cap read as an empty memory.
  public static func read(_ data: Data) -> RepeatedWords {
    guard !data.isEmpty, data.count <= maxFileBytes,
      let file = try? JSONDecoder().decode(RepeatedWords.self, from: data),
      file.version == currentVersion, file.isWithinLimits
    else { return RepeatedWords() }
    return file
  }

  /// The file's bytes: JSON with sorted keys.
  public var data: Data {
    let encoder = JSONEncoder()
    // Base64 has slashes, which the encoder would otherwise write as two characters each.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)) ?? Data()
  }

  /// Whether the memory is what `remember` and `deny` can make: names that are kept as they are,
  /// no show or episode twice, every list and every hash count within its cap.
  var isWithinLimits: Bool {
    guard shows.count <= Self.mostShows, Set(shows.map(\.id)).count == shows.count else {
      return false
    }
    for show in shows {
      guard Self.isName(show.id), show.episodes.count <= Self.mostEpisodes,
        Set(show.episodes.map(\.id)).count == show.episodes.count,
        show.denied.count <= Self.mostDenied
      else { return false }
      for episode in show.episodes {
        guard Self.isName(episode.id), episode.hashes.count % 4 == 0,
          episode.hashes.count / 4 <= Self.mostWords
        else { return false }
      }
      for denied in show.denied {
        guard denied.hashes.count % 4 == 0, denied.hashes.count / 4 <= Self.deniedSamples else {
          return false
        }
      }
    }
    return hashCount <= Self.mostHashesInAll
  }

  /// How many episode hashes are kept in all (what `mostHashesInAll` limits).
  var hashCount: Int {
    shows.reduce(0) { $0 + $1.episodes.reduce(0) { $0 + $1.hashes.count / 4 } }
  }

  /// A name as it is kept: `FinderGuard`'s rule (80 characters, trimmed). Empty means no name.
  static func isName(_ text: String) -> Bool { !text.isEmpty && FinderGuard.name(text) == text }

  // MARK: Remembering

  /// Stores what an episode said, as hashes, after `find` was asked about it. Nothing changes for
  /// an empty name, an episode already stored, or one with too few words to hold a repeat. The
  /// show's oldest episode goes when it has more than three; the shows heard from longest ago go
  /// when there are more than 60, or when all the hashes together are over the cap.
  public mutating func remember(show: String, episode: String, lines: [TranscriptLine], now: Date) {
    let showId = FinderGuard.name(show)
    let episodeId = FinderGuard.name(episode)
    guard !showId.isEmpty, !episodeId.isEmpty else { return }
    forgetOldDenials(now: now)
    let known = shows.first(where: { $0.id == showId })
    guard known?.episodes.contains(where: { $0.id == episodeId }) != true else { return }
    let hashes = SpokenRuns(lines: lines).hashes
    guard hashes.count >= Self.fewestRuns else { return }
    var entry = take(showId)
    entry.episodes.append(Episode(id: episodeId, hashes: SpokenRuns.pack(hashes)))
    entry.episodes = Array(entry.episodes.suffix(Self.mostEpisodes))
    shows.append(entry)
    trim()
  }

  /// Remembers a stretch the listener said is not an ad (or whose skip they undid): up to a
  /// hundred of its hashes, spread over it. The same words are not offered again for 60 days. A
  /// stretch with fewer than ten runs, or times that are not numbers or not in order, change
  /// nothing. At most five stretches are kept for a show, the newest last.
  public mutating func deny(
    show: String, lines: [TranscriptLine], start: Double, end: Double, now: Date
  ) {
    let showId = FinderGuard.name(show)
    guard !showId.isEmpty, start.isFinite, end.isFinite, end > start else { return }
    forgetOldDenials(now: now)
    let spoken = SpokenRuns(lines: lines)
    let picked = spoken.hashes.indices.filter {
      spoken.middle(of: $0) >= start && spoken.middle(of: $0 + SpokenRuns.runLength - 1) <= end
    }.map { spoken.hashes[$0] }
    guard picked.count >= Self.fewestDeniedRuns else { return }
    let count = min(picked.count, Self.deniedSamples)
    let samples = SpokenRuns.pack((0..<count).map { picked[$0 * picked.count / count] })
    var entry = take(showId)
    entry.denied.removeAll { $0.hashes == samples }
    entry.denied.append(Denied(at: Self.seconds(now), hashes: samples))
    entry.denied = Array(entry.denied.suffix(Self.mostDenied))
    shows.append(entry)
    trim()
  }

  /// Fewest runs an episode needs to be stored (a repeat is at least `KnownAds.fewestWords`
  /// words), and fewest in a stretch worth remembering as "not an ad".
  static let fewestRuns = KnownAds.fewestWords - SpokenRuns.runLength + 1
  static let fewestDeniedRuns = 10

  /// Takes a show out of the list, or makes a new one. The caller puts it back at the end.
  private mutating func take(_ id: String) -> Show {
    guard let at = shows.firstIndex(where: { $0.id == id }) else {
      return Show(id: id, episodes: [], denied: [])
    }
    return shows.remove(at: at)
  }

  /// Drops the shows heard from longest ago while there are more than `mostShows`, or while all
  /// the episode hashes are over `limit`. The newest show is never dropped.
  mutating func trim(toHashes limit: Int = RepeatedWords.mostHashesInAll) {
    if shows.count > Self.mostShows { shows.removeFirst(shows.count - Self.mostShows) }
    var total = hashCount
    while total > limit, shows.count > 1 {
      total -= shows[0].episodes.reduce(0) { $0 + $1.hashes.count / 4 }
      shows.removeFirst()
    }
  }

  // MARK: Old denials

  /// Seconds since 1970 as a whole number; 0 for a date that is not a number.
  static func seconds(_ date: Date) -> Int {
    let time = date.timeIntervalSince1970
    return time.isFinite ? Int(max(-1e12, min(1e12, time))) : 0
  }

  static func isOld(_ denied: Denied, now: Date) -> Bool {
    Double(seconds(now)) - Double(denied.at) > keepDeniedDays * 86_400
  }

  /// Takes out the denials that are over `keepDeniedDays` days old, and a show left with nothing.
  mutating func forgetOldDenials(now: Date) {
    for at in shows.indices { shows[at].denied.removeAll { Self.isOld($0, now: now) } }
    shows.removeAll { $0.episodes.isEmpty && $0.denied.isEmpty }
  }
}
