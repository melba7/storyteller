// LOFI-FORK: the phone's own library of ad sounds, learned from ads it skipped (see FORK.md).
//
// When the phone has skipped an ad and the listener did not undo it, the phone keeps a small print
// of that stretch: the same anchors the Mac's `ad-sounds.json` has (one number for every eighth
// frame). The next episode that holds the same bytes is skipped from the bytes alone. This type
// is pure: it reads no file, takes no lock and never looks at the clock. The caller passes the
// time as `now`, in seconds since 1970, and does the file, the lock and the save. Foundation only.
//
// How the phone uses it (the wiring is another package's job):
//
//   var own = OwnAdSounds.read(data)       // the file's bytes; missing or damaged reads as empty
//   own.library(for: show)                 // an AdSoundLibrary to scan an episode of `show` with
//   own.library                            // all the prints, for tests and tools
//   OwnAdSounds.trusted(hits)              // the hits of that scan worth skipping (see below)
//   own.data                               // the file's bytes; write them after learn and forget
//   OwnAdSoundsFile.frames(in: url, stretches: [(start: Double, end: Double)]) -> [MP3Frame]
//                                          // only the frames inside the stretches, read in pieces
//   own.learn(show: String, frames: [MP3Frame], stretches: [MarkedStretch],
//             mac: AdSoundLibrary = AdSoundLibrary(), now: Double) -> Int
//                                          // sure skips only (see below); how many were added
//   own.forget(frames: [MP3Frame], start: Double, end: Double, now: Double) -> Int
//                                          // the listener undid this skip; how many were dropped
//   own.prune(now: Double)                 // age, count and size limits (learn and forget do it too)
//
// What `learn` is given, as `KnownAds.learn` is: the SURE ads of the final ads file that the
// existing finders found, or that the listener said yes to (source "tap"), which the listener did
// not undo and did not trim (AdTrim), and only after the joint snap has put their borders on the
// frames. Never a skip of a new finder that is only `unsure`: a wrong skip nobody noticed would be
// learned and refreshed for good. On Undo the phone calls `forget` with the stretch as it was
// skipped (read the frames with `OwnAdSoundsFile.frames`), before the file is saved again.
//
// The stretches are the skipped stretches as they were skipped, with no margin: the print covers
// all of each, so the next skip begins and ends where this one did. A stretch is learned only
// when it lasts 8 to 600 seconds. The index of a sound in `library` can change after learn,
// forget and prune, so make the scanner from `library` again after them.
import Foundation

/// One of the phone's own sounds: the print, the show it was learned in and when it was last met.
public struct OwnAdSound: Sendable, Equatable {
  public var show: String
  /// Seconds since 1970.
  public var lastSeen: Double
  public var sound: AdSound

  public init(show: String, lastSeen: Double, sound: AdSound) {
    self.show = show
    self.lastSeen = lastSeen
    self.sound = sound
  }
}

public struct OwnAdSounds: Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "own-ad-sounds.json"
  /// The limits of `KnownAds` (ads kept by their words), and the most bytes the file may have.
  public static let mostPerShow = 40
  public static let mostInAll = 400
  public static let keepDays = 60.0
  public static let maxBytes = 1_500_000
  /// How many undone stretches are remembered, and how many stretches one `learn` looks at.
  static let mostUndone = 40
  static let mostStretches = 100

  /// The sounds, the newest first.
  public internal(set) var entries: [OwnAdSound] = []
  /// The prints of stretches the listener undid, which are not learned again. They are kept like
  /// sounds; their show is empty and their sort and who mean nothing.
  var undone: [OwnAdSound] = []

  public init() {}

  /// The sounds as a library for the scanner.
  public var library: AdSoundLibrary { AdSoundLibrary(sounds: entries.map(\.sound)) }

  // MARK: Learning

  /// Learns the stretches of an episode that were skipped and not undone. `frames` are the frames
  /// of the file, or at least those inside the stretches (`OwnAdSoundsFile.frames`). A stretch
  /// that is a sound already held is counted as seen again; one that lasts less than 8 seconds,
  /// that the Mac's library `mac` holds, or that the listener undid before adds nothing. Returns
  /// how many sounds were added. Save the file afterwards, also when it is 0. At most 100 stretches
  /// are looked at. The frames are in order of time.
  @discardableResult
  public mutating func learn(
    show: String, frames: [MP3Frame], stretches: [MarkedStretch],
    mac: AdSoundLibrary = AdSoundLibrary(), now: Double
  ) -> Int {
    guard Self.isTime(now), Self.isName(show), !frames.isEmpty else { return 0 }
    expire(now: now)
    let macHolds = SoundLookup(mac)
    let wasUndone = SoundLookup(AdSoundLibrary(sounds: undone.map(\.sound)))
    let own = SoundLookup(library)
    var wanted: [MarkedStretch] = []
    for stretch in stretches.prefix(Self.mostStretches)
    where stretch.start.isFinite && stretch.end.isFinite && stretch.end > stretch.start
      && AdSoundLibrary.sorts.contains(stretch.sort)
    {
      let slice = Self.cut(frames, from: stretch.start, to: stretch.end)
      let seconds = slice.reduce(0) { $0 + $1.duration }
      guard seconds >= AdSoundBuilder.minSeconds, seconds <= AdSoundBuilder.maxSeconds else { continue }
      if macHolds.holding(slice, seconds: seconds, sameLength: false) != nil
        || wasUndone.holding(slice, seconds: seconds, sameLength: false) != nil
      {
        continue
      }
      if let at = own.holding(slice, seconds: seconds, sameLength: true) {
        entries[at].sound.seen = min(entries[at].sound.seen + 1, AdSoundLibrary.maxSeen)
        entries[at].lastSeen = now
        continue
      }
      wanted.append(stretch)
    }
    let made = Self.made(frames: frames, stretches: wanted)
    for var sound in made {
      sound.who = String(sound.who.unicodeScalars.prefix(Self.mostName))
      entries.append(OwnAdSound(show: show, lastSeen: now, sound: sound))
    }
    prune(now: now)
    return made.count
  }

  /// The listener undid the skip of the stretch from `start` to `end`: drops every sound that was
  /// found in it over at least half of the smaller of the sound and the stretch, so a sound that
  /// matched only a part of itself, or only a short stretch, goes too. It keeps the print of the
  /// stretch (when it lasts 8 seconds or more) so the same bytes are not learned again for 60
  /// days. `frames` are the frames of that stretch (or of the whole file). Returns how many
  /// sounds were dropped. Save the file afterwards, also when it is 0.
  @discardableResult
  public mutating func forget(frames: [MP3Frame], start: Double, end: Double, now: Double) -> Int {
    guard Self.isTime(now), start.isFinite, end.isFinite, end > start else { return 0 }
    expire(now: now)
    let slice = Self.cut(frames, from: start, to: end)
    guard !slice.isEmpty else { return 0 }
    let seconds = slice.reduce(0) { $0 + $1.duration }
    var dropped = 0
    if !entries.isEmpty {
      let sounds = entries.map(\.sound)
      let inside = Set(
        SoundLookup(AdSoundLibrary(sounds: sounds)).hits(in: slice)
          .filter { ($0.end - $0.start) * 2 >= min(sounds[$0.sound].seconds, seconds) }.map(\.sound))
      entries = entries.enumerated().filter { !inside.contains($0.offset) }.map(\.element)
      dropped = inside.count
    }
    // Keep the print of the undone stretch so its bytes are not learned again (or, when it is
    // kept already, note that it was undone once more).
    if let print = Self.made(
      frames: frames, stretches: [MarkedStretch(start: start, end: end, sort: "sponsor", who: "")]
    ).first {
      let known = SoundLookup(AdSoundLibrary(sounds: undone.map(\.sound)))
        .holding(slice, seconds: print.seconds, sameLength: false)
      if let known {
        undone[known].lastSeen = now
      } else {
        undone.append(OwnAdSound(show: "", lastSeen: now, sound: print))
      }
    }
    prune(now: now)
    return dropped
  }

  // MARK: Limits

  /// Drops what was not seen for `keepDays` days, then the oldest beyond `mostPerShow` for a show
  /// and `mostInAll`, then the oldest until the file fits in `maxBytes`. The newest come first.
  public mutating func prune(now: Double) { prune(now: now, maxBytes: Self.maxBytes) }

  mutating func prune(now: Double, maxBytes: Int) {
    expire(now: now)
    fit(maxBytes: maxBytes)
  }

  /// The age and count limits. A `now` that is not a time leaves the age alone.
  mutating func expire(now: Double) {
    if now.isFinite {
      let oldest = now - Self.keepDays * 86_400
      entries.removeAll { $0.lastSeen < oldest }
      undone.removeAll { $0.lastSeen < oldest }
    }
    limitCounts()
  }

  /// The count limits only: the newest 40 of a show, 400 in all and 40 undone stretches.
  mutating func limitCounts() {
    var perShow: [String: Int] = [:]
    entries = Self.newestFirst(entries).filter {
      perShow[$0.show, default: 0] += 1
      return perShow[$0.show, default: 0] <= Self.mostPerShow
    }
    entries = Array(entries.prefix(Self.mostInAll))
    undone = Array(Self.newestFirst(undone).prefix(Self.mostUndone))
  }

  /// Newest first; of two seen at the same time the one seen more often, then the earlier one.
  static func newestFirst(_ list: [OwnAdSound]) -> [OwnAdSound] {
    list.enumerated().sorted {
      ($0.element.lastSeen, $0.element.sound.seen, $1.offset)
        > ($1.element.lastSeen, $1.element.sound.seen, $0.offset)
    }.map(\.element)
  }
}
