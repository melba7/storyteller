// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// One pass over an MP3 file for every sound consumer: the frames are cut once by one
// `MP3FrameReader` from byte 0, and each frame goes to the taught sounds (the Mac's), the phone's
// own sounds, the repeat scanner, the print builder and the joint finder. A consumer that is not
// wanted costs nothing. The file is read in pieces, so memory stays small whatever its length.
// It reads the file, so only a background task calls it, never the main actor.
//
// The taught sounds' hits are what `AdSoundFile.hits` gives (same scanner, same order), so with
// no other consumer wanted the result is today's. The other consumers need the whole file: when
// the time is up in the middle (the stop flag), their results are left out and only the taught
// sounds' hits, which are right as far as they go, are kept.
import Foundation
import PodcastAudioMatch

/// What a pass over one file found.
struct SoundPassResult: Sendable {
  /// The taught sounds (the Mac's), in the order they play.
  var mac: [AdSoundHit] = []
  /// The phone's own sounds whose match covers enough of the print to be trusted.
  var own: [AdSoundHit] = []
  /// The stretches that an older episode of the show had too.
  var repeats: [RepeatStretch] = []
  /// The print of the whole file, when asked for.
  var print: EpisodePrint?
  var joints: Joints?
  /// The consumers that were run to the end of the file.
  var ran: Set<SoundPass.Consumer> = []
}

/// What a pass is asked to do. An empty library, or no older print, switches that consumer off.
struct SoundPass: Sendable {
  enum Consumer: String, Sendable { case mac, own, repeats, print, joints }

  var mac = AdSoundLibrary()
  var own = AdSoundLibrary()
  var older: [EpisodePrint] = []
  /// The episode's id and date, when its print is wanted (even with no older print to compare).
  var printOf: (episode: String, date: Double)?
  var wantsRepeats = false
  var wantsJoints = false
  /// The episode being scanned: an older print of it is not compared with it.
  var episode = ""

  /// Which consumers this asks for.
  var consumers: Set<Consumer> {
    var all: Set<Consumer> = []
    if !mac.sounds.isEmpty { all.insert(.mac) }
    if !own.sounds.isEmpty { all.insert(.own) }
    if wantsRepeats && !older.isEmpty { all.insert(.repeats) }
    if printOf != nil { all.insert(.print) }
    if wantsJoints { all.insert(.joints) }
    return all
  }

  /// The pass over the file at `url`, or nil when it cannot be opened.
  func run(file url: URL, stop: StopFlag? = nil, chunkSize: Int = AdSoundFile.defaultChunkSize)
    -> SoundPassResult?
  {
    guard chunkSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var state = State(self)
    // A folder opens but cannot be read: that ends the loop at once, like the end of a file.
    while !(stop?.isStopped ?? false), let chunk = try? handle.read(upToCount: chunkSize),
      !chunk.isEmpty
    {
      state.feed([UInt8](chunk))
    }
    return state.finish(complete: !(stop?.isStopped ?? false))
  }

  /// The pass over bytes held in memory (the first bytes of a stream).
  func run(data: Data, chunkSize: Int = AdSoundFile.defaultChunkSize) -> SoundPassResult {
    var state = State(self)
    var at = data.startIndex
    while at < data.endIndex, chunkSize > 0 {
      let end = data.index(at, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
      state.feed([UInt8](data[at..<end]))
      at = end
    }
    return state.finish(complete: true)
  }

  /// The scanners of one pass and what they found so far.
  private struct State {
    let pass: SoundPass
    var reader = MP3FrameReader()
    var mac: AdSoundScanner?
    var own: AdSoundScanner?
    var repeats: RepeatScanner?
    var printer: EpisodePrintBuilder?
    var joints: JointFinder?
    var macHits: [AdSoundHit] = []
    var ownHits: [AdSoundHit] = []

    init(_ pass: SoundPass) {
      self.pass = pass
      let wanted = pass.consumers
      if wanted.contains(.mac) { mac = AdSoundScanner(library: pass.mac) }
      if wanted.contains(.own) { own = AdSoundScanner(library: pass.own) }
      if wanted.contains(.repeats) {
        repeats = RepeatScanner(older: pass.older, episode: pass.episode)
      }
      if wanted.contains(.print) { printer = EpisodePrintBuilder() }
      if wanted.contains(.joints) { joints = JointFinder() }
    }

    mutating func feed(_ bytes: [UInt8]) {
      let frames = reader.feed(bytes)
      guard !frames.isEmpty else { return }
      macHits += mac?.feed(frames) ?? []
      ownHits += own?.feed(frames) ?? []
      repeats?.feed(frames)
      printer?.feed(frames)
      joints?.feed(frames)
    }

    mutating func finish(complete: Bool) -> SoundPassResult {
      var result = SoundPassResult()
      if var scanner = mac {
        result.mac = Self.ordered(macHits + scanner.finish())
        result.ran.insert(.mac)
      }
      guard complete else { return result }
      if var scanner = own {
        result.own = OwnAdSounds.trusted(Self.ordered(ownHits + scanner.finish()))
        result.ran.insert(.own)
      }
      if var scanner = repeats {
        result.repeats = scanner.finish()
        result.ran.insert(.repeats)
      }
      if let printer, let of = pass.printOf {
        result.print = printer.finish(episode: of.episode, date: of.date)
        result.ran.insert(.print)
      }
      if let joints {
        result.joints = joints.joints
        result.ran.insert(.joints)
      }
      return result
    }

    private static func ordered(_ hits: [AdSoundHit]) -> [AdSoundHit] {
      hits.sorted { ($0.start, $0.sound) < ($1.start, $1.sound) }
    }
  }
}

/// The results of the passes made in this launch, by the download's SHA-256, so the ad finder
/// does not read a file again for its second step. Small: the newest few only.
final class PodcastSoundPasses: @unchecked Sendable {
  static let shared = PodcastSoundPasses()

  /// What a result was made with. It is stale when the taught or own sounds changed since.
  struct Stamp: Equatable, Sendable {
    var taught: Int
    var own: Int
  }

  private struct Entry {
    var sha: String
    var stamp: Stamp
    var result: SoundPassResult
  }

  private static let most = 6
  private let lock = NSLock()
  private var entries: [Entry] = []

  /// The result for this file, when one was made with these sounds and ran every consumer in
  /// `needs`.
  func result(sha: String, stamp: Stamp, needs: Set<SoundPass.Consumer>) -> SoundPassResult? {
    lock.withLock {
      entries.first { $0.sha == sha && $0.stamp == stamp && needs.isSubset(of: $0.result.ran) }?
        .result
    }
  }

  func store(_ result: SoundPassResult, sha: String, stamp: Stamp) {
    lock.withLock {
      entries.removeAll { $0.sha == sha }
      entries.append(Entry(sha: sha, stamp: stamp, result: result))
      if entries.count > Self.most { entries.removeFirst(entries.count - Self.most) }
    }
  }
}
