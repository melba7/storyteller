// LOFI-FORK: reads `show-settings.json` as the Mac writes it (see ShowTuning.swift and FORK.md).
// Foundation only.
import Foundation

extension ShowTuning {
  /// Reads one value of a list or a dictionary and keeps nil when it is of the wrong shape.
  private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
  }

  /// One block of the file (the default block or a show's entry). Anything of the wrong type is
  /// left out, and so is every name and level the phone does not know.
  private struct Block: Decodable {
    var choices = Choices()
    var feed: String?
    var ask: Double?

    private enum Keys: String, CodingKey { case feed, finders, sorts, joints, steadyJoints, ask }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      feed = try? box.decode(String.self, forKey: .feed)
      choices.finders = Self.levels(try? box.decode([String: Lossy<String>].self, forKey: .finders), ShowTuning.finderNames)
      choices.sorts = Self.levels(try? box.decode([String: Lossy<String>].self, forKey: .sorts), ShowTuning.sortNames)
      choices.joints = try? box.decode(Bool.self, forKey: .joints)
      choices.steadyJoints = try? box.decode(Bool.self, forKey: .steadyJoints)
      if let number = try? box.decode(Double.self, forKey: .ask), number.isFinite { ask = number }
    }

    /// The levels of `names` that the file gives as "skip", "ask" or "off".
    private static func levels(_ found: [String: Lossy<String>]?, _ names: [String]) -> [String: FinderMode] {
      var levels: [String: FinderMode] = [:]
      for name in names {
        if let text = found?[name]?.value, let level = FinderMode(rawValue: text) { levels[name] = level }
      }
      return levels
    }
  }

  private struct File: Decodable {
    var version: Int?
    var block: Block?
    var shows: [Lossy<Block>] = []

    private enum Keys: String, CodingKey { case version, shows, `default` }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      version = try? box.decode(Int.self, forKey: .version)
      block = try? box.decode(Block.self, forKey: .default)
      shows = (try? box.decode([Lossy<Block>].self, forKey: .shows)) ?? []
    }
  }

  /// The settings in `data`. A file that is not a version 1 object, is damaged or is over 5 MB
  /// reads as the built-in default (never as "everything off"). Each show's feed address is turned
  /// into the app's show id by `showOf`; a show it does not know is left out.
  public init(data: Data, showOf: MacFiles.ShowOf = MacFiles.feedAsShow) {
    self.init()
    guard data.count <= Self.maxBytes,
      let file = try? JSONDecoder().decode(File.self, from: data),
      file.version == Self.currentVersion
    else { return }
    if let block = file.block {
      base = Self.builtIn.overlaid(by: block.choices)
      if let ask = block.ask { askThreshold = min(max(ask, Self.askRange.lowerBound), Self.askRange.upperBound) }
    }
    for item in file.shows {
      guard let entry = item.value, let feed = entry.feed, let show = showOf(feed), !show.isEmpty else { continue }
      shows[show] = (shows[show] ?? Choices()).overlaid(by: entry.choices)
    }
  }

  /// The same for the text of the file; nil reads as the built-in default.
  public init(text: String?, showOf: MacFiles.ShowOf = MacFiles.feedAsShow) {
    guard let text, text.utf8.count <= Self.maxBytes else {
      self.init()
      return
    }
    self.init(data: Data(text.utf8), showOf: showOf)
  }
}
