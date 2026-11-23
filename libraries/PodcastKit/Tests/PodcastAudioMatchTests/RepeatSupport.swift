import Foundation

@testable import PodcastAudioMatch

/// Made-up episodes for the repeat tests. An episode is a list of frame ids (see `Snd`): ids that
/// are not shared between two lists are different audio, so each `filler` call gives audio that
/// matches nothing else.
enum Rep {
  /// One frame is 1152 / 44100 s long, so 8 s are 307 frames and 30 s are 1148 frames.
  static let duration = Snd.duration

  /// Frames that no other call gives (an id range of its own for each `tag`).
  static func filler(_ tag: Int, _ count: Int) -> [Int] {
    Array((tag * 1_000_000)..<(tag * 1_000_000 + max(count, 0)))
  }

  /// The print of an episode made of `ids`, with the frames fed in pieces of `pieces`.
  static func print(
    _ ids: [Int], episode: String = "old", date: Double = 0, pieces: Int = 5000
  ) -> EpisodePrint {
    var builder = EpisodePrintBuilder()
    let frames = Snd.frames(ids)
    for start in stride(from: 0, to: frames.count, by: max(pieces, 1)) {
      builder.feed(Array(frames[start..<min(start + pieces, frames.count)]))
    }
    return builder.finish(episode: episode, date: date)
  }

  /// What the scanner gives for a new episode made of `ids` against older prints.
  static func scan(
    _ older: [EpisodePrint], _ ids: [Int], episode: String = "new", pieces: Int = 5000
  ) -> [RepeatStretch] {
    var scanner = RepeatScanner(older: older, episode: episode)
    let frames = Snd.frames(ids)
    for start in stride(from: 0, to: frames.count, by: max(pieces, 1)) {
      scanner.feed(Array(frames[start..<min(start + pieces, frames.count)]))
    }
    return scanner.finish()
  }
}
