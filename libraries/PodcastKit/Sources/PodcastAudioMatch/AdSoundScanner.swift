// LOFI-FORK: finds taught ad sounds in the frames of an episode as they arrive (see FORK.md).
import Foundation

public struct AdSoundHit: Sendable, Equatable {
  /// The index of the sound in the library.
  public var sound: Int
  public var sort: String
  public var who: String
  /// Seconds in the file being scanned.
  public var start: Double
  public var end: Double
  /// How many anchors in a row matched, one for every eighth frame. A hit starts where the whole
  /// sound would start and ends where the matching stopped, so a hit whose matched anchors cover
  /// only a small part of its length matched a part of the sound only. It is 0 for a hit made by hand.
  public var matched: Int = 0
}

/// Matches frames against the anchors of a library. A frame whose low 32 bits are an anchor
/// starts a trail; the trail goes on while the frame one step later is the sound's next anchor.
/// After `need` anchors in a row the sound is confirmed, but the scanner keeps following it: a
/// hit is given when the match ends (the frames stop matching, or the sound's last anchor is
/// reached), and it ends where the matching stopped, so a cut of a longer sound is not taken
/// for the whole of it. Frames still matching when the data runs out are given by `finish()`.
public struct AdSoundScanner: Sendable {
  public static let need = 4

  /// One anchor of one sound in the index. The top bit of `number` says the place may not start
  /// a trail (it repeats the anchor before it, or its sound is too short).
  private struct Place: Sendable {
    var sound: UInt32
    var packed: UInt32
    static let weak: UInt32 = 0x8000_0000
    var number: Int { Int(packed & ~Place.weak) }
    var starts: Bool { packed & Place.weak == 0 }
  }

  /// A trail that expects anchor number `next` of `sound` at a known frame.
  private struct Trail: Sendable {
    var sound: Int
    var next: Int
    var matched: Int
    var first: Int  // the file frame at which the sound would start
    var start: Double  // the time of that frame, or 0 when it came before the first frame fed
    var lastTime: Double  // the time of the latest matched anchor's frame
  }

  private var sounds: [AdSound]
  // Every anchor of every sound as flat arrays sorted by anchor, searched by binary search: a
  // library of thousands of sounds then costs a few bytes for each anchor, not a dictionary
  // entry and an array.
  private var keys: [UInt32] = []
  private var places: [Place] = []
  private var trails: [Int: [Trail]] = [:]  // by the file frame at which they expect their anchor
  private var reported: [Int: [Int]] = [:]  // by sound, the first frames of the places reported
  private var times: [Double] = []  // the start times of the latest frames
  private var firstTime = 0  // the file frame that `times[0]` belongs to
  private var window: Int  // how many frames of times a trail may need
  private var count = 0  // frames fed so far

  public init(library: AdSoundLibrary) {
    sounds = []
    window = 0
    add(library.sounds)
  }

  /// Adds one sound to the index without building it again from the start.
  public mutating func add(_ sound: AdSound) { add([sound]) }

  private mutating func add(_ more: [AdSound]) {
    var entries: [(key: UInt32, place: Place)] = []
    for sound in more {
      let index = UInt32(sounds.count)
      sounds.append(sound)
      window = max(window, (sound.anchors.count + 4) * AdSoundLibrary.step)
      let long = sound.anchors.count >= AdSoundScanner.need
      for (number, anchor) in sound.anchors.enumerated() {
        let repeats = number > 0 && sound.anchors[number - 1] == anchor
        let packed = UInt32(number) | (long && !repeats ? 0 : Place.weak)
        entries.append((anchor, Place(sound: index, packed: packed)))
      }
    }
    entries.sort { ($0.key, $0.place.sound, $0.place.packed) < ($1.key, $1.place.sound, $1.place.packed) }
    guard !keys.isEmpty else {
      keys = entries.map(\.key)
      places = entries.map(\.place)
      return
    }
    // One pass that merges the new entries into the old ones.
    var mergedKeys: [UInt32] = []
    var mergedPlaces: [Place] = []
    mergedKeys.reserveCapacity(keys.count + entries.count)
    mergedPlaces.reserveCapacity(keys.count + entries.count)
    var old = 0
    for entry in entries {
      while old < keys.count, keys[old] <= entry.key {
        mergedKeys.append(keys[old])
        mergedPlaces.append(places[old])
        old += 1
      }
      mergedKeys.append(entry.key)
      mergedPlaces.append(entry.place)
    }
    mergedKeys.append(contentsOf: keys[old...])
    mergedPlaces.append(contentsOf: places[old...])
    keys = mergedKeys
    places = mergedPlaces
  }

  /// The places of the index that hold `anchor`.
  private func range(of anchor: UInt32) -> Range<Int> {
    var low = 0
    var high = keys.count
    while low < high {
      let middle = (low + high) / 2
      if keys[middle] < anchor { low = middle + 1 } else { high = middle }
    }
    var end = low
    while end < keys.count, keys[end] == anchor { end += 1 }
    return low..<end
  }

  /// Feed the frames of one file in order, in as many calls as you like. Returns the sounds
  /// whose match ended with these frames; call `finish()` after the last frames for the rest.
  public mutating func feed(_ frames: [MP3Frame]) -> [AdSoundHit] {
    var hits: [AdSoundHit] = []
    let step = AdSoundLibrary.step
    for frame in frames {
      let index = count
      count += 1
      times.append(frame.start)
      if times.count > 2 * window + 1 {
        times.removeFirst(times.count - window - 1)
        firstTime = count - times.count
      }
      let anchor = UInt32(truncatingIfNeeded: frame.hash)
      var continued: Set<Int> = []  // sound * 2^32 + anchor number, of trails that go on here
      for var trail in trails.removeValue(forKey: index) ?? [] {
        let anchors = sounds[trail.sound].anchors
        guard anchors[trail.next] == anchor else {
          // The frames stopped matching: the match ends where it got to.
          if trail.matched >= AdSoundScanner.need, let hit = confirm(trail) { hits.append(hit) }
          continue
        }
        continued.insert(trail.sound << 32 | trail.next)
        trail.matched += 1
        trail.lastTime = frame.start
        trail.next += 1
        if trail.next < anchors.count {
          trails[index + step, default: []].append(trail)
        } else if trail.matched >= AdSoundScanner.need, let hit = confirm(trail) {
          hits.append(hit)  // the whole sound matched
        }
      }
      let found = range(of: anchor)
      // An anchor in many places says little, so it starts no trail.
      guard !found.isEmpty, found.count <= 3 else { continue }
      for place in places[found] where place.starts {
        let sound = Int(place.sound)
        let number = place.number
        guard !continued.contains(sound << 32 | number), number + 1 < sounds[sound].anchors.count
        else { continue }
        let first = index - number * step
        let spot = first - firstTime
        trails[index + step, default: []].append(
          Trail(
            sound: sound, next: number + 1, matched: 1, first: first,
            start: first < 0 || spot < 0 ? 0 : times[spot], lastTime: frame.start))
      }
    }
    return hits
  }

  /// The sounds still matching when the frames ran out, with their ends where the matching
  /// got to. Call it once after the last frames of a file. The scanner has no trails afterwards.
  public mutating func finish() -> [AdSoundHit] {
    let open = trails.values.flatMap { $0 }
    trails = [:]
    return open.filter { $0.matched >= AdSoundScanner.need }
      .compactMap { confirm($0) }
      .sorted { ($0.start, $0.sound) < ($1.start, $1.sound) }
  }

  /// The hit for a trail that has ended, or nil when that place was reported already. The hit
  /// ends one step after the last anchor that matched, and never after the sound's own length.
  private mutating func confirm(_ trail: Trail) -> AdSoundHit? {
    let known = reported[trail.sound, default: []]
    guard !known.contains(where: { abs($0 - trail.first) <= AdSoundLibrary.step }) else { return nil }
    reported[trail.sound, default: []].append(trail.first)
    let sound = sounds[trail.sound]
    let perFrame = sound.seconds / Double(max(sound.frames, 1))
    let end = min(trail.lastTime + Double(AdSoundLibrary.step) * perFrame, trail.start + sound.seconds)
    return AdSoundHit(
      sound: trail.sound, sort: sound.sort, who: sound.who, start: trail.start,
      end: max(end, trail.start), matched: trail.matched)
  }
}
