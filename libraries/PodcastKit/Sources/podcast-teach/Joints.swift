// LOFI-FORK: `podcast-teach joints` (see FORK.md). The work is in `JointsCache.fill` (PodcastAudioMatch),
// so tests can call it; this finds the episodes' MP3 files the way the scorer does.
import Foundation
import PodcastAds
import PodcastAudioMatch

enum JointsCommand {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) -> Int32 {
    guard arguments.count == 1, !arguments[0].hasPrefix("--") else {
      print("Usage: podcast-teach joints <teaching folder>")
      return 2
    }
    let folder = URL(fileURLWithPath: arguments[0], isDirectory: true)
    return JointsCache.fill(folder: folder, audio: TeachingAudio.files(in: folder))
  }
}
