// LOFI-FORK: a compact print of a whole episode, to find what repeats across a show (see FORK.md).
//
// A standing plug, a network promo or a jingle plays again in the next episode, and a host splices
// it in byte for byte. So an episode's frames, one number for every eighth frame (the anchors of
// `AdSoundLibrary`, 4 bytes each, about 69 KB an hour), are enough to see in a later episode which
// stretches have been heard before. The phone keeps the prints of a show's newest three episodes
// and scans a new episode against them. Foundation only, and no dependency on PodcastAds.
//
// What the phone's code calls (the files are the phone's to write, under Library/Caches, and any of
// them may be missing: with no print nothing repeats and everything else works):
//
//   EpisodePrintBuilder                                 (this file)
//     init()
//     mutating func feed(_ frames: [MP3Frame])          frames of one file, in order, in pieces
//     func finish(episode: String, date: Double) -> EpisodePrint
//   EpisodePrint                                        (this file)
//     episode: String, date: Double, frames: Int, seconds: Double, anchors: [UInt32]
//   ShowPrints                                          (ShowPrints.swift): one show's file
//     init(data: Data)                                  damaged, cut, other version: empty
//     func data() -> Data
//     func adding(_ print: EpisodePrint) -> ShowPrints  the newest 3 episodes of the show are kept
//     func prints(excluding episode: String) -> [EpisodePrint]
//   PrintShelf.evictions(_ entries: [PrintShelf.Entry]) -> [String]
//                                                       (PrintShelf.swift): which shows' files
//                                                       to delete for 60 shows and 12 MB in all
//   RepeatScanner(older: [EpisodePrint], episode: String = "")   (RepeatScanner.swift)
//     mutating func feed(_ frames: [MP3Frame])          the new episode's frames, in pieces
//     mutating func finish() -> [RepeatStretch]         (start, end) in seconds in the new file
import Foundation

/// The print of one episode: its anchors, and what the store needs to know about it.
public struct EpisodePrint: Sendable, Equatable {
  public static let step = AdSoundLibrary.step
  /// The most anchors a print holds: 100,000 are over five hours, 400 KB. A longer file is
  /// printed up to there.
  public static let maxAnchors = 100_000
  /// The most frames a print covers.
  static let maxFrames = maxAnchors * step
  /// The longest episode id a stored print may have, in bytes.
  static let maxIdBytes = 256

  /// The episode's own id. The scanner leaves out a print whose id is the episode it scans.
  public var episode: String
  /// When the episode came out, in seconds since 1970 (the phone may use the day it was
  /// downloaded when the feed does not say). A show keeps the prints with the newest dates.
  public var date: Double
  /// How many frames the anchors cover, and how many seconds they last.
  public var frames: Int
  public var seconds: Double
  /// The low 32 bits of the hash of every `step`th frame, from the first frame of the file.
  public var anchors: [UInt32]

  public init(episode: String, date: Double, frames: Int, seconds: Double, anchors: [UInt32]) {
    self.episode = episode
    self.date = date.isFinite ? date : 0
    self.frames = max(frames, 0)
    self.seconds = seconds.isFinite ? max(seconds, 0) : 0
    self.anchors = anchors
  }

  /// Whether a store may keep this print: it has an id and some anchors, and fits the limits.
  var storable: Bool {
    !episode.isEmpty && episode.utf8.count <= Self.maxIdBytes && !anchors.isEmpty
      && anchors.count <= Self.maxAnchors && anchors.count == (frames + Self.step - 1) / Self.step
  }
}

/// Makes the print of a file from its frames, in one pass: frames go in as they come, in as many
/// calls as you like. What it holds is the print itself (4 bytes for every eighth frame), not the
/// file.
public struct EpisodePrintBuilder: Sendable {
  private var anchors: [UInt32] = []
  private var count = 0  // frames fed so far, up to the limit
  private var seconds = 0.0

  public init() {}

  /// Frames after `EpisodePrint.maxFrames` are not looked at.
  public mutating func feed(_ frames: [MP3Frame]) {
    for frame in frames {
      guard count < EpisodePrint.maxFrames else { return }
      if count % EpisodePrint.step == 0 { anchors.append(UInt32(truncatingIfNeeded: frame.hash)) }
      count += 1
      let end = frame.start + frame.duration
      if end.isFinite { seconds = max(seconds, end) }
    }
  }

  public func finish(episode: String, date: Double) -> EpisodePrint {
    EpisodePrint(episode: episode, date: date, frames: count, seconds: seconds, anchors: anchors)
  }
}
