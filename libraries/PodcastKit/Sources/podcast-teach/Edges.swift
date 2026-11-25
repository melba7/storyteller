// LOFI-FORK: `podcast-teach edges` (see FORK.md). The work is in EdgeCommand (PodcastAudioMatch), so
// tests can call it with made-up sound; this file only hands in a Mac's decoder. Where there is none
// (Linux) the command says so and exits with 2.
import Foundation
import PodcastAudioMatch
import PodcastEdgeAudio

enum EdgesTool {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) async -> Int32 {
    await EdgeCommand.run(
      arguments, reader: MacEdgeReader.make(), out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
