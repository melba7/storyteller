// LOFI-FORK: `podcast-teach agree` (see FORK.md). The work is in AdAgreeCommand (PodcastAds), so
// tests can call it.
import Foundation
import PodcastAds

enum AgreeCommand {
  static func run(_ arguments: [String]) -> Int32 {
    AdAgreeCommand.run(
      arguments, out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
