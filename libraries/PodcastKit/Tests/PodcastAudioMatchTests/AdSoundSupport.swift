import Foundation

@testable import PodcastAudioMatch

/// Made-up frames for the ad sound tests: a frame is told apart by its id alone, and equal ids
/// give equal hashes (and different ids different low 32 bits). No MP3 bytes are built.
enum Snd {
  static let duration = 1152.0 / 44100

  static func ids(_ ranges: Range<Int>...) -> [Int] { ranges.flatMap { Array($0) } }

  static func frames(_ ids: [Int]) -> [MP3Frame] {
    ids.enumerated().map { place, id in
      MP3Frame(
        offset: place * 417, length: 417, start: Double(place) * duration,
        duration: duration, hash: UInt64(id + 1) &* 0x9E37_79B9_7F4A_7C15, bitrate: 128_000,
        sampleRate: 44100, channels: 2, hasInfoTag: false, mainDataBegin: 0)
    }
  }

  /// The time at which the frame `index` of a made-up file starts.
  static func time(_ index: Int) -> Double { Double(index) * duration }

  static func sound(
    _ ids: [Int], sort: String = "sponsor", who: String = "Acme", seen: Int = 1
  ) -> AdSound {
    let made = frames(ids)
    return AdSound(
      sort: sort, who: who, frames: made.count, seconds: Double(made.count) * duration, seen: seen,
      anchors: stride(from: 0, to: made.count, by: AdSoundLibrary.step).map {
        UInt32(truncatingIfNeeded: made[$0].hash)
      })
  }
}
