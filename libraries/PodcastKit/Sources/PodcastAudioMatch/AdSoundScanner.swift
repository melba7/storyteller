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
}

/// Matches frames against the anchors of a library. A frame whose low 32 bits are an anchor
/// starts a trail; the trail goes on while the frame one step later is the sound's next anchor
/// and confirms the sound after `need` anchors in a row.
public struct AdSoundScanner: Sendable {
  public static let need = 4

  private struct Place: Sendable {
    var sound: Int32
    var anchor: Int32
  }

  /// A trail that expects anchor number `next` of `sound` at a known frame.
  private struct Trail: Sendable {
    var sound: Int
    var next: Int
    var matched: Int
    var first: Int  // the file frame at which the sound would start
  }

  private let sounds: [AdSound]
  private var starts: [UInt32: [Place]] = [:]  // only anchors that are good enough to start a trail
  private var trails: [Int: [Trail]] = [:]  // by the file frame at which they expect their anchor
  private var reported: [Int: [Int]] = [:]  // by sound, the first frames of the places reported
  private var times: [Double] = []  // the start times of the latest frames
  private var firstTime = 0  // the file frame that `times[0]` belongs to
  private let window: Int  // how many frames of times a trail may need
  private var count = 0  // frames fed so far

  public init(library: AdSoundLibrary) {
    sounds = library.sounds
    window = ((library.sounds.map(\.anchors.count).max() ?? 0) + 4) * AdSoundLibrary.step
    var places: [UInt32: Int] = [:]
    for sound in sounds { for anchor in sound.anchors { places[anchor, default: 0] += 1 } }
    for (index, sound) in sounds.enumerated() where sound.anchors.count >= AdSoundScanner.need {
      for (number, anchor) in sound.anchors.enumerated() {
        // An anchor in many places, or one that repeats the anchor before it, says little.
        if places[anchor, default: 0] > 3 || (number > 0 && sound.anchors[number - 1] == anchor) {
          continue
        }
        starts[anchor, default: []].append(Place(sound: Int32(index), anchor: Int32(number)))
      }
    }
  }

  /// Feed the frames of one file in order, in as many calls as you like. Returns the sounds
  /// confirmed by these frames.
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
        guard sounds[trail.sound].anchors[trail.next] == anchor else { continue }
        trail.matched += 1
        continued.insert(trail.sound << 32 | trail.next)
        if trail.matched >= AdSoundScanner.need {
          if let hit = confirm(trail) { hits.append(hit) }
          continue
        }
        trail.next += 1
        guard trail.next < sounds[trail.sound].anchors.count else { continue }
        trails[index + step, default: []].append(trail)
      }
      for place in starts[anchor] ?? [] {
        let sound = Int(place.sound)
        let number = Int(place.anchor)
        guard !continued.contains(sound << 32 | number), number + 1 < sounds[sound].anchors.count
        else { continue }
        trails[index + step, default: []].append(
          Trail(sound: sound, next: number + 1, matched: 1, first: index - number * step))
      }
    }
    return hits
  }

  /// The hit for a confirmed trail, or nil when that place was reported already.
  private mutating func confirm(_ trail: Trail) -> AdSoundHit? {
    let known = reported[trail.sound, default: []]
    guard !known.contains(where: { abs($0 - trail.first) <= AdSoundLibrary.step }) else { return nil }
    reported[trail.sound, default: []].append(trail.first)
    let spot = trail.first - firstTime
    let start = trail.first < 0 || spot < 0 ? 0 : times[spot]
    let sound = sounds[trail.sound]
    return AdSoundHit(
      sound: trail.sound, sort: sound.sort, who: sound.who, start: start, end: start + sound.seconds)
  }
}
