// LOFI-FORK: `podcast-teach score` (see FORK.md). The work is in AdScoreCommand (PodcastAds), so
// tests can call it.
import Foundation
import PodcastAds

enum ScoreCommand {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) -> Int32 {
    AdScoreCommand.run(
      arguments,
      out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
