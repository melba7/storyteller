// LOFI-FORK: `podcast-teach apple` (see FORK.md). The work is in AppleCommand (PodcastAds), so tests
// can call it with a fake detector; this file only hands in Apple's model. Where there is none
// (Linux, an older macOS, Apple Intelligence off) the command says so and exits with 2.
import Foundation
import PodcastAds
import PodcastAdsOnDevice

enum AppleTool {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) async -> Int32 {
    let detector = AppleAds.unavailable() == nil ? AppleAds.makeDetector() : nil
    return await AppleCommand.run(
      arguments, detector: detector, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
