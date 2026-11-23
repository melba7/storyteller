// LOFI-FORK: how the phone's own sounds are matched against the frames of a stretch (see FORK.md).
import Foundation

/// A library made ready to be looked up in the frames of a stretch. The scanner is made once and
/// copied for each stretch, so a library of hundreds of sounds is indexed once for an episode.
struct SoundLookup: Sendable {
  private let sounds: [AdSound]
  private let scanner: AdSoundScanner?

  init(_ library: AdSoundLibrary) {
    sounds = library.sounds
    scanner = library.sounds.isEmpty ? nil : AdSoundScanner(library: library)
  }

  /// The sounds found in the frames of one stretch, with times counted from its first frame.
  func hits(in slice: [MP3Frame]) -> [AdSoundHit] {
    guard var scan = scanner, let first = slice.first else { return [] }
    let shifted = slice.map { frame -> MP3Frame in
      var moved = frame
      moved.start -= first.start
      return moved
    }
    return scan.feed(shifted) + scan.finish()
  }

  /// The number of the sound that is this stretch: one found over at least half of the stretch's
  /// `seconds`. With `sameLength` it must also have nearly as many frames as the stretch (a cut of
  /// a longer sound is another sound), as `AdSoundBuilder` asks.
  func holding(_ slice: [MP3Frame], seconds: Double, sameLength: Bool) -> Int? {
    let covered = hits(in: slice)
      .filter { !sameLength || abs(sounds[$0.sound].frames - slice.count) <= AdSoundBuilder.frameTolerance }
      .map { (sound: $0.sound, seconds: min($0.end, seconds) - max($0.start, 0)) }
    guard let best = covered.max(by: { $0.seconds < $1.seconds }), best.seconds * 2 >= seconds
    else { return nil }
    return best.sound
  }
}

extension OwnAdSounds {
  /// The longest name (show or advertiser) kept, in characters, and read, in bytes.
  static let mostName = 100
  static let mostNameBytes = 500

  /// A time as the caller gives it: seconds since 1970, a number that is not negative.
  static func isTime(_ time: Double) -> Bool { time.isFinite && time >= 0 }

  /// A show as the library knows it: some text that is not very long.
  static func isName(_ show: String) -> Bool { !show.isEmpty && show.utf8.count <= mostNameBytes }

  /// The frames of `frames` that lie wholly between the times `from` and `to` (the frames are in
  /// order of time). Never more than the longest sound and a second, so a stretch that is far too
  /// long costs nothing; its seconds then show it is too long.
  static func cut(_ frames: [MP3Frame], from: Double, to: Double) -> [MP3Frame] {
    var low = 0
    var high = frames.count
    while low < high {
      let middle = (low + high) / 2
      if frames[middle].start < from - 1e-9 { low = middle + 1 } else { high = middle }
    }
    var end = low
    while end < frames.count, frames[end].start + frames[end].duration <= to + 1e-9,
      frames[end].start - frames[low].start <= AdSoundBuilder.maxSeconds + 1
    {
      end += 1
    }
    return Array(frames[low..<end])
  }

  /// The sounds the builder makes of these stretches. The stretches are widened by the builder's
  /// margin first, so the print covers each stretch as it is.
  static func made(frames: [MP3Frame], stretches: [MarkedStretch]) -> [AdSound] {
    guard !stretches.isEmpty else { return [] }
    var builder = AdSoundBuilder()
    builder.add(
      episode: "episode", frames: frames,
      marked: stretches.map {
        MarkedStretch(
          start: $0.start - AdSoundBuilder.margin, end: $0.end + AdSoundBuilder.margin,
          sort: $0.sort, who: $0.who)
      })
    return builder.library(maxBytes: .max).sounds
  }
}
