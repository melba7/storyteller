// LOFI-FORK: where the teaching folder keeps each episode's audio (see FORK.md). Foundation only.
import Foundation

enum TeachingAudio {
  /// The MP3 file of each episode that has one, by the episode's id: the file `episodes.json` names
  /// for it, when that name stays inside the folder, ends in `.mp3` and the file is there. An
  /// episode with no such file is not in the answer (the sound rows leave it out).
  static func files(in folder: URL) -> [String: URL] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("episodes.json")),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let entries = root["episodes"] as? [Any]
    else { return [:] }
    var found: [String: URL] = [:]
    for case let entry as [String: Any] in entries {
      guard let id = entry["id"] as? String, !id.isEmpty, let file = entry["file"] as? String,
        isInside(file), URL(fileURLWithPath: file).pathExtension.lowercased() == "mp3"
      else { continue }
      let url = folder.appendingPathComponent(file)
      var isFolder: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue {
        found[id] = url
      }
    }
    return found
  }

  /// Whether a name stays inside the teaching folder: not empty, no leading slash, no `..`.
  static func isInside(_ name: String) -> Bool {
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return !name.isEmpty && !name.hasPrefix("/") && !parts.contains("..") && !parts.contains("")
  }
}
