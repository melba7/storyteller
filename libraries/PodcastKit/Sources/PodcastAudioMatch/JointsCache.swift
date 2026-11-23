// LOFI-FORK: `joints.json` in the teaching folder, the joints of each episode's file found once, so
// that `podcast-teach score` gets its joint rows without the audio (see FORK.md). Foundation only.
import Foundation

public struct JointsCache: Equatable, Sendable {
  public static let fileName = "joints.json"
  /// A file bigger than this is not read (it is damaged or not ours).
  private static let readLimit = 64 * 1024 * 1024
  /// The cache is written again after this many new episodes, so a long run loses little.
  private static let saveEvery = 25

  /// The joints of each episode, by the episode's id.
  public var episodes: [String: Joints]

  public init(episodes: [String: Joints] = [:]) { self.episodes = episodes }

  private struct Entry: Codable {
    var seconds: Double
    var steady: Bool
    var overflowed: Bool
    var times: [Double]
  }

  private struct Root: Codable {
    var version: Int
    var episodes: [String: Entry]
  }

  /// The cache in the file at `url`. A file that is not there is an empty cache and no problem. A
  /// file that cannot be used (not JSON, another version) is an empty cache and one plain line
  /// saying so. An entry that cannot be used is left out; the next `fill` makes it again.
  public static func load(from url: URL) -> (cache: JointsCache, problem: String?) {
    guard FileManager.default.fileExists(atPath: url.path) else { return (JointsCache(), nil) }
    let ignored = "\(fileName) is damaged or not a version 1 file, so it is ignored."
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
      size <= readLimit, let data = try? Data(contentsOf: url),
      let root = try? JSONDecoder().decode(LenientRoot.self, from: data), root.version == 1
    else { return (JointsCache(), ignored) }
    var found: [String: Joints] = [:]
    for (id, entry) in root.episodes {
      guard let entry, entry.seconds.isFinite, entry.seconds > 0,
        entry.times.allSatisfy({ $0.isFinite && $0 >= 0 })
      else { continue }
      found[id] = Joints(
        times: entry.times, seconds: entry.seconds, steady: entry.steady,
        overflowed: entry.overflowed)
    }
    return (JointsCache(episodes: found), nil)
  }

  /// Entries that do not decode are nil, so one bad entry does not cost the others.
  private struct LenientRoot: Decodable {
    var version: Int
    var episodes: [String: Entry?]

    private enum Keys: String, CodingKey { case version, episodes }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      version = try box.decode(Int.self, forKey: .version)
      let list = try box.nestedContainer(keyedBy: AnyKey.self, forKey: .episodes)
      var made: [String: Entry?] = [:]
      for key in list.allKeys { made[key.stringValue] = try? list.decode(Entry.self, forKey: key) }
      episodes = made
    }
  }

  private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  /// Writes the file in one piece (a reader never sees half of it).
  public func write(to url: URL) throws {
    let root = Root(
      version: 1,
      episodes: episodes.mapValues {
        Entry(seconds: $0.seconds, steady: $0.steady, overflowed: $0.overflowed, times: $0.times)
      })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(root).write(to: url, options: .atomic)
  }

  /// `podcast-teach joints`: finds the joints of each file in `audio` (by episode id) that has no
  /// entry in the folder's `joints.json` yet, and saves them there, keeping the entries it has.
  /// Says what it did through `say`. Returns 0 when it worked (also with nothing to do) and 2 for a
  /// set-up problem (no folder, or the file cannot be written).
  public static func fill(
    folder: URL, audio: [String: URL], say: (String) -> Void = { print($0) }
  ) -> Int32 {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue
    else {
      say("There is no teaching folder at \(folder.path).")
      return 2
    }
    let url = folder.appendingPathComponent(fileName)
    let loaded = load(from: url)
    if let problem = loaded.problem { say(problem) }
    var cache = loaded.cache
    let todo = audio.keys.sorted().filter { cache.episodes[$0] == nil }
    var made = 0
    var unreadable = 0
    for (place, id) in todo.enumerated() {
      guard let joints = audio[id].flatMap({ ScoreSounds.joints(in: $0) }), joints.seconds > 0 else {
        say("The joints of episode \(id) could not be found: its file cannot be read as MP3.")
        unreadable += 1
        continue
      }
      cache.episodes[id] = joints
      made += 1
      if made % saveEvery == 0, (try? cache.write(to: url)) == nil { break }
      if place % 10 == 9 { say("Joints: \(place + 1) of \(todo.count) files read.") }
    }
    if made > 0 {
      do {
        try cache.write(to: url)
      } catch {
        say("\(fileName) could not be written to \(folder.path): \(error.localizedDescription)")
        return 2
      }
    }
    say(
      "\(fileName): \(made) new, \(audio.count - todo.count) already there, \(unreadable) could not be read.")
    return 0
  }
}
