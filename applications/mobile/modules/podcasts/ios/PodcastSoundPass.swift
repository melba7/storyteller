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
//
// `NewAds` at the end holds the plain rules for the ads the new finders give: what a sound or a
// repeat turns into, which parts lie outside the ads already known, and the snap onto joints.
import Foundation
import PodcastAds
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

  /// Forgets what was kept for a file (it was deleted).
  func forget(sha: String) {
    lock.withLock { entries.removeAll { $0.sha == sha } }
  }
}

/// The plain rules for the ads of the new finders, with no file, clock or lock.
enum NewAds {
  /// A new finder's ad stays this far from every other ad. `AdJoin` joins ads that lie within
  /// half a second, and it takes the higher confidence and drops the name, so no new ad may come
  /// that near.
  static let apart = 0.6
  /// How far from an ad's start a trim of it may lie before the ad is left alone by the snap:
  /// the snap moves a start up to 3 seconds, and a trim is found by where its ad started.
  static let trimReach = 3.5

  /// An ad's borders before and after the snap moved them.
  struct Moved: Equatable {
    var wasStart: Double
    var wasEnd: Double
    var start: Double
    var end: Double
  }

  static func overlap(_ a: FoundAd, _ b: FoundAd) -> Bool { a.start < b.end && b.start < a.end }

  /// Whether a stretch the listener undid or said "no" to lies over `ad`.
  static func overlap(_ a: UndoneAd, _ b: FoundAd) -> Bool { a.start < b.end && b.start < a.end }

  /// The ads of sounds that were heard (sure, as `LocalAdsFile.soundAd` makes them). A hit of a
  /// sort the Mac does not know is left out.
  static func ads(ofSounds hits: [AdSoundHit]) -> [FoundAd] {
    hits.compactMap {
      LocalAdsFile.soundAd(sort: $0.sort, who: $0.who, start: $0.start, end: $0.end)
    }
  }

  /// The ads of repeated sounds: plain ads, unsure, of 10 to 300 seconds (the ads' own rules).
  static func ads(ofRepeats stretches: [RepeatStretch]) -> [FoundAd] {
    stretches.compactMap { stretch in
      guard stretch.start.isFinite, stretch.end.isFinite, stretch.start >= 0,
        (AdRules.minLength...AdRules.maxLength).contains(stretch.end - stretch.start)
      else { return nil }
      return FoundAd(
        start: stretch.start, end: stretch.end, kind: .ad, advertiser: "", confidence: .unsure,
        firstWords: "")
    }
  }

  /// The parts of `ads` that lie outside every blocker (each widened by `apart`), at least
  /// `AdRules.minLength` seconds long and at most `AdRules.maxLength`. An ad nothing touches comes
  /// back whole. Ads and blockers that are not real stretches are ignored.
  static func outside(_ ads: [FoundAd], of blockers: [FoundAd]) -> [FoundAd] {
    var spans: [(start: Double, end: Double)] = []
    for blocker in blockers.sorted(by: { $0.start < $1.start })
    where blocker.start.isFinite && blocker.end.isFinite && blocker.end > blocker.start {
      let wide = (start: blocker.start - apart, end: blocker.end + apart)
      if let last = spans.last, wide.start <= last.end {
        spans[spans.count - 1].end = max(last.end, wide.end)
      } else {
        spans.append(wide)
      }
    }
    var result: [FoundAd] = []
    for ad in ads where ad.start.isFinite && ad.end.isFinite && ad.end > ad.start {
      var from = ad.start
      var parts: [(start: Double, end: Double)] = []
      for span in spans where span.end > from {
        if span.start >= ad.end { break }
        if span.start > from { parts.append((from, span.start)) }
        from = max(from, span.end)
      }
      if from < ad.end { parts.append((from, ad.end)) }
      for part in parts
      where (AdRules.minLength...AdRules.maxLength).contains(part.end - part.start) {
        var piece = ad
        piece.start = part.start
        piece.end = part.end
        result.append(piece)
      }
    }
    return result
  }

  /// The ads (in order of start) with each border put on a joint of the file, when `JointSnap`
  /// finds one near. An ad that `fixed` names is left as it is. An ad's start never goes before
  /// the end of the ad before it (after that one's own snap), and its end never after the start of
  /// the next as it was found.
  static func snap(
    _ found: [FoundAd], joints: Joints, steadyToo: Bool,
    leaving fixed: (FoundAd) -> Bool = { _ in false }
  ) -> (ads: [FoundAd], moved: [Moved]) {
    var ads = found
    var moved: [Moved] = []
    for (index, ad) in found.enumerated() where !fixed(ad) {
      let to = JointSnap.snap(
        start: ad.start, end: ad.end, joints: joints,
        previousEnd: index > 0 ? ads[index - 1].end : nil,
        nextStart: index + 1 < found.count ? found[index + 1].start : nil, steadyToo: steadyToo)
      guard to.start != ad.start || to.end != ad.end else { continue }
      ads[index].start = to.start
      ads[index].end = to.end
      moved.append(Moved(wasStart: ad.start, wasEnd: ad.end, start: to.start, end: to.end))
    }
    return (ads, moved)
  }

  /// An ad that the listener confirmed (source "tap"), undid or trimmed keeps its borders.
  static func isFixed(_ ad: FoundAd, in file: AdsFile) -> Bool {
    ad.source == AdAsking.source || file.isUndone(ad)
      || (file.trims ?? []).contains { $0.adStart >= ad.start - trimReach && $0.adStart < ad.end }
  }
}
