// LOFI-FORK: `podcast-teach map`, which writes the episode map of one MP3 file (see FORK.md and
// EpisodeMap.swift). The Mac's preparing run calls it for each copy it publishes (teach_maps.py).
// Foundation only, so tests can call it and it runs on Linux too.
//
//   podcast-teach map <audio.mp3> --out <map.json> --marks <marks.json> --sha256 <64 hex>
//                     [--feed <feed address>] [--guid <episode guid>]
//
// <marks.json> is a list of the marks made on that file, in its seconds:
// [{"start": 612.0, "end": 671.5, "kind": "ad"}]. The map is written whole or not at all.
// Exit codes: 0 written, 1 the file cannot be read or holds no map, 2 the command is wrong.
import Foundation

public enum EpisodeMapCommand {
  static let usage =
    "Usage: podcast-teach map <audio.mp3> --out <map.json> --marks <marks.json> --sha256 <64 hex> [--feed <feed address>] [--guid <episode guid>]"

  /// Runs the command and returns its exit code. What it says goes to `say`, one line.
  public static func run(_ arguments: [String], say: (String) -> Void = { print($0) }) -> Int32 {
    var values: [String: String] = [:]
    var files: [String] = []
    var at = 0
    while at < arguments.count {
      let word = arguments[at]
      if ["--out", "--marks", "--sha256", "--feed", "--guid"].contains(word) {
        guard at + 1 < arguments.count else {
          say(usage)
          return 2
        }
        values[word] = arguments[at + 1]
        at += 2
      } else if word.hasPrefix("--") {
        say(usage)
        return 2
      } else {
        files.append(word)
        at += 1
      }
    }
    guard files.count == 1, let out = values["--out"], let marksFile = values["--marks"],
      let sha = values["--sha256"]?.lowercased(), sha.utf8.count == 64,
      sha.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
    else {
      say(usage)
      return 2
    }
    guard let marksData = try? Data(contentsOf: URL(fileURLWithPath: marksFile)),
      let marks = try? JSONDecoder().decode([EpisodeMapMark].self, from: marksData)
    else {
      say("No map: the marks in \(marksFile) cannot be read.")
      return 1
    }
    guard let audio = try? Data(contentsOf: URL(fileURLWithPath: files[0]), options: .mappedIfSafe)
    else {
      say("No map: \(files[0]) cannot be read.")
      return 1
    }
    guard
      let map = EpisodeMap.make(
        mp3: [UInt8](audio), feed: values["--feed"] ?? "", guid: values["--guid"] ?? "",
        sha256: sha, marks: marks), let data = map.encoded(), data.count <= EpisodeMap.maxBytes
    else {
      say("No map: \(files[0]) is not an MP3 file a map can be made of.")
      return 1
    }
    do {
      try data.write(to: URL(fileURLWithPath: out), options: .atomic)
    } catch {
      say("No map: \(out) cannot be written (\(error.localizedDescription)).")
      return 1
    }
    say(
      "Map written: \(map.frames.count) frames, \(map.marks.count) marks, \((data.count + 512) / 1024) KB."
    )
    return 0
  }
}
