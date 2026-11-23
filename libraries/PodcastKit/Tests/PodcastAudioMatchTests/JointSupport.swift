import Foundation

@testable import PodcastAudioMatch

/// Made-up frames for the joint tests, in runs that share one header. No MP3 bytes are built.
enum JointFrames {
  /// One run of frames. By default a run is 128 kbps stereo at 44.1 kHz, every frame reaching back
  /// into the bit reservoir (a pointer above 0), so a run on its own holds no joint at all.
  struct Run {
    var count: Int
    var kbps = 128
    var rate = 44100
    var mono = false
    /// The first frame of the run holds an Xing or Info tag.
    var tag = false
    /// The bit reservoir pointer of every frame of the run (nil: it cannot be read).
    var pointer: Int? = 1
  }

  /// The length of one frame at 44.1 kHz.
  static let duration = 1152.0 / 44100

  /// The time at which frame `index` starts in a file of 44.1 kHz frames.
  static func time(_ index: Int) -> Double { Double(index) * duration }

  static func frames(_ runs: [Run]) -> [MP3Frame] {
    var made: [MP3Frame] = []
    var offset = 0
    var start = 0.0
    for run in runs {
      let length = 144 * run.kbps * 1000 / run.rate
      let seconds = 1152.0 / Double(run.rate)
      for place in 0..<run.count {
        made.append(
          MP3Frame(
            offset: offset, length: length, start: start, duration: seconds,
            hash: UInt64(made.count + 1) &* 0x9E37_79B9_7F4A_7C15, bitrate: run.kbps * 1000,
            sampleRate: run.rate, channels: run.mono ? 1 : 2, hasInfoTag: run.tag && place == 0,
            mainDataBegin: run.pointer))
        offset += length
        start += seconds
      }
    }
    return made
  }

  /// A file that is the show at 128 kbps with an ad of 64 kbps inside it: joints at frame 300
  /// and at frame 1,300. The two bitrates are far enough apart that the file is not steady.
  static func spliced() -> [MP3Frame] {
    frames([Run(count: 300), Run(count: 1000, kbps: 64), Run(count: 3000)])
  }

  /// A file with `joints` changes of bitrate, 50 frames (the shortest that counts) apart.
  static func busy(joints: Int) -> [MP3Frame] {
    frames(
      (0...joints).map { Run(count: SeekDrift.seamFrames, kbps: $0 % 2 == 0 ? 128 : 64) })
  }

  /// What `SeekDrift.report` says the joints are: the times of its seams and of the frames where
  /// the reservoir is reset, each time once and in order.
  static func expected(_ parse: MP3Parse) -> [Double] {
    let report = SeekDrift.report(parse)
    let times = report.seams.map(\.time) + report.reservoirResets.map { parse.frames[$0].start }
    return Array(Set(times)).sorted()
  }

  /// A small generator that gives the same numbers on every run, so a failing file can be made again.
  struct Dice {
    var state: UInt64

    mutating func next(_ limit: Int) -> Int {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((state >> 33) % UInt64(limit))
    }
  }
}
