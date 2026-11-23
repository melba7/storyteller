// LOFI-FORK: the logic of `podcast-teach sounds`, in the library so that tests can call it (see FORK.md).
import Foundation

public enum AdSoundCommand {
  /// What the owner needs to know about a run.
  private struct Tally {
    var read = 0
    var noAudio = 0
    var notMP3 = 0
    var noLabel = 0
    var unreadable = 0
    var stretches = 0
  }

  /// The sorts that are read as sound. Host asks are read live and do not repeat as sound.
  private static let sorts: Set<String> = ["sponsor", "network_promo", "intro_credits"]

  /// The ids in `exam.json` (`{"episodes": ["id", ...]}`): none when there is no file, nil when
  /// the file cannot be read, because the exam must not be learned from by mistake.
  private static func examIds(_ folder: URL) -> Set<String>? {
    let url = folder.appendingPathComponent("exam.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    guard let data = try? Data(contentsOf: url),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let ids = root["episodes"] as? [Any], ids.allSatisfy({ $0 is String })
    else { return nil }
    return Set(ids.compactMap { $0 as? String })
  }

  /// `<teaching folder> [--labels NAME]`. Writes `ad-sounds.json` into the folder and says what it
  /// did through `say`. Returns 0 when it worked (also with nothing to do) and 2 for a set-up problem.
  public static func run(_ arguments: [String], say: (String) -> Void = { print($0) }) -> Int32 {
    var folderPath: String?
    var labels = "labels"
    var rest = arguments[...]
    while let argument = rest.popFirst() {
      if argument == "--labels", let name = rest.popFirst() {
        labels = name
      } else if !argument.hasPrefix("--"), folderPath == nil {
        folderPath = argument
      } else {
        say("Usage: podcast-teach sounds <teaching folder> [--labels NAME]")
        return 2
      }
    }
    guard let folderPath, safe(labels) else {
      say("Usage: podcast-teach sounds <teaching folder> [--labels NAME]")
      return 2
    }
    let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
    guard let episodes = manifest(folder) else {
      say("There is no usable episodes.json in \(folderPath). Run the gather step first.")
      return 2
    }

    guard let exam = examIds(folder) else {
      say("exam.json in \(folderPath) is not in the expected shape, so nothing was learned.")
      return 2
    }
    var tally = Tally()
    var builder = AdSoundBuilder()
    for episode in episodes {
      guard let id = episode["id"] as? String, safe(id, plain: true) else {
        tally.unreadable += 1
        continue
      }
      // The sealed exam never teaches anything.
      if exam.contains(id) { continue }
      guard let file = episode["file"] as? String else {
        tally.noAudio += 1
        continue
      }
      guard safe(file), URL(fileURLWithPath: file).pathExtension.lowercased() == "mp3" else {
        tally.notMP3 += 1
        continue
      }
      let audio = folder.appendingPathComponent(file)
      let label = folder.appendingPathComponent(labels).appendingPathComponent(id + ".json")
      guard FileManager.default.fileExists(atPath: audio.path) else {
        tally.noAudio += 1
        continue
      }
      guard FileManager.default.fileExists(atPath: label.path) else {
        tally.noLabel += 1
        continue
      }
      guard let marked = stretches(label) else {
        tally.unreadable += 1
        continue
      }
      guard let bytes = try? Data(contentsOf: audio) else {
        tally.unreadable += 1
        continue
      }
      let frames = MP3Frames.parse([UInt8](bytes)).frames
      guard !frames.isEmpty else {
        tally.notMP3 += 1
        continue
      }
      tally.read += 1
      tally.stretches += marked.count
      builder.add(episode: id, frames: frames, marked: marked)
    }

    report(tally, say)
    guard tally.read > 0 else {
      say("Nothing to do: no episode has both an MP3 file and a label.")
      return 0
    }
    let library = builder.library()
    let again = library.sounds.filter { $0.seen > 1 }.count
    say("Kept \(count(library.sounds.count, "different sound")).")
    if again == 0 {
      say(
        "None of them was heard in more than one episode, so matching by sound has nothing to work with yet.")
    } else {
      say(
        "\(again) of them \(again == 1 ? "was" : "were") heard in more than one episode, so matching by sound works for these shows."
      )
    }
    guard let data = try? library.data(), AdSoundLibrary.install(data: data, folder: folder) else {
      say("Could not write \(AdSoundLibrary.fileName) into \(folderPath).")
      return 2
    }
    say("Wrote \(folder.appendingPathComponent(AdSoundLibrary.fileName).path).")
    return 0
  }

  private static func report(_ tally: Tally, _ say: (String) -> Void) {
    say("Read \(count(tally.read, "episode")).")
    let skipped = [
      (tally.noAudio, "with no audio"), (tally.notMP3, tally.notMP3 == 1 ? "that is not MP3" : "that are not MP3"),
      (tally.noLabel, "with no label"), (tally.unreadable, "that could not be read"),
    ]
    for (number, reason) in skipped where number > 0 {
      say("Skipped \(count(number, "episode")) \(reason).")
    }
    say("Looked at \(count(tally.stretches, "marked stretch", plural: "marked stretches")).")
  }

  private static func count(_ number: Int, _ noun: String, plural: String? = nil) -> String {
    "\(number) \(number == 1 ? noun : (plural ?? noun + "s"))"
  }

  /// Whether `name` stays inside the teaching folder: no leading slash and no `..`. A plain name
  /// has no slash at all.
  private static func safe(_ name: String, plain: Bool = false) -> Bool {
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return !name.isEmpty && !name.hasPrefix("/") && !parts.contains("..") && !parts.contains("")
      && (!plain || parts.count == 1)
  }

  /// The episodes of `episodes.json`, or nil when it is missing or not a version 1 list.
  private static func manifest(_ folder: URL) -> [[String: Any]]? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("episodes.json")),
      let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      top["version"] as? Int == 1, let list = top["episodes"] as? [[String: Any]]
    else { return nil }
    return list
  }

  /// The high confidence stretches of the sorts that are read as sound in a label file, or nil
  /// when the file does not read.
  private static func stretches(_ label: URL) -> [MarkedStretch]? {
    guard let data = try? Data(contentsOf: label),
      let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let segments = top["segments"] as? [[String: Any]]
    else { return nil }
    return segments.compactMap { segment in
      guard segment["confidence"] as? String == "high", let sort = segment["sort"] as? String,
        sorts.contains(sort), let start = (segment["start"] as? NSNumber)?.doubleValue,
        let end = (segment["end"] as? NSNumber)?.doubleValue, end > start
      else { return nil }
      return MarkedStretch(start: start, end: end, sort: sort, who: segment["who"] as? String ?? "")
    }
  }
}
