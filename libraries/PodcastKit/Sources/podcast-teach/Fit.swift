// LOFI-FORK: `podcast-teach fit` (see FORK.md). The work is in AdWordFit (PodcastAds), so tests can
// call it; this file only wires the output.
import Foundation
import PodcastAds

enum FitTool {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) -> Int32 {
    AdWordFit.run(
      arguments, out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
