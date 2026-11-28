// LOFI-FORK: the episode map, a small picture of the copy of an episode the Mac marked (see FORK.md
// and docs/PLAN.md, milestones Z4 and Z19). Foundation only.
//
// WHY A MAP. The show's own audio is the same MP3 frames in every download of an episode; only the
// ads a host inserts differ. So the Mac writes down one byte for each frame of the copy it marked,
// with Claude's marks in that copy's seconds. A phone that plays another download (a stream as it
// arrives, or a file) lines its own frames up against the map (`EpisodeMapAligner`): where the
// frames match, the Mac's marks hold to the frame, and where they match nothing the phone has an
// ad the Mac's copy did not have.
//
// THE FILE (`Podcasts/maps/<copy id>.json`, version 1):
//
//   {"version": 1, "feed": "<feed address>", "guid": "<episode guid>", "sha256": "<the copy's>",
//    "duration": 3600.0, "frameSeconds": 0.026122, "frames": "<base64, one byte for each frame>",
//    "marks": [{"start": 612.0, "end": 671.5, "kind": "ad"}]}
//
// One byte for each frame is enough because frames are never matched alone: a match starts from 16
// frames in a row (128 bits) and counts only when it runs on for 3 seconds. An hour of audio is
// about 138,000 frames, so its map is about 185 KB.
import Foundation

/// One stretch the Mac marked, in seconds of the copy it marked.
public struct EpisodeMapMark: Codable, Sendable, Equatable {
  public var start: Double
  public var end: Double
  /// "ad", "promo" or "ownPlug" (the kinds of `ahead-ads.json`).
  public var kind: String

  public init(start: Double, end: Double, kind: String) {
    self.start = start
    self.end = end
    self.kind = kind
  }
}

public struct EpisodeMap: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  /// The folder of the maps, inside `Podcasts/` of the linked folder.
  public static let folder = "maps"
  /// A file bigger than this reads as no map (a ten hour episode is under 2 MB).
  public static let maxBytes = 4_000_000
  /// A map's file is read only when a frame is this long, in seconds (an MP3 frame is 0.024 to
  /// 0.072), and the copy is at most this long. So no number of the file is too big to count
  /// frames with.
  static let frameRange = 0.005...0.2
  static let maxDuration = 1_000_000.0
  /// A mark may end this long after the copy does (the two are rounded apart).
  static let markSlack = 1.0

  public var version = EpisodeMap.currentVersion
  public var feed: String
  public var guid: String
  /// The SHA-256 of the copy the map was made of.
  public var sha256: String
  /// The copy's length in seconds.
  public var duration: Double
  /// How long one frame of the copy is, in seconds. Frame `n` starts at `n * frameSeconds`.
  public var frameSeconds: Double
  /// One byte for each frame of the copy, in order (`short` of the frame's hash).
  public var frames: Data
  public var marks: [EpisodeMapMark]

  public init(
    feed: String, guid: String, sha256: String, duration: Double, frameSeconds: Double,
    frames: Data, marks: [EpisodeMapMark]
  ) {
    self.feed = feed
    self.guid = guid
    self.sha256 = sha256
    self.duration = duration
    self.frameSeconds = frameSeconds
    self.frames = frames
    self.marks = marks
  }

  /// The byte a frame is known by in a map: the eight bytes of its hash folded into one.
  public static func short(_ hash: UInt64) -> UInt8 {
    var folded = hash
    folded ^= folded >> 32
    folded ^= folded >> 16
    folded ^= folded >> 8
    return UInt8(truncatingIfNeeded: folded)
  }

  /// The name of the file a phone keeps the map of the copy with this SHA-256 under, or nil when
  /// that is not 64 hex digits. The file is named by the copy and not by the episode, so the map
  /// of an older copy never passes for the map of the copy the Mac made since.
  public static func fileName(sha256: String) -> String? {
    let hex = sha256.lowercased()
    guard hex.utf8.count == 64,
      hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { return nil }
    return hex + ".json"
  }

  /// The map in `data`, or nil when it is damaged, too big, of another version, or has no frames,
  /// no real frame length or no real length. A mark that is not a real stretch inside the copy is
  /// left out.
  public init?(data: Data) {
    guard data.count <= Self.maxBytes,
      var map = try? JSONDecoder().decode(EpisodeMap.self, from: data),
      map.version == Self.currentVersion, !map.frames.isEmpty,
      Self.frameRange.contains(map.frameSeconds), map.duration > 0,
      map.duration <= Self.maxDuration
    else { return nil }
    map.marks = map.marks.filter {
      $0.start >= 0 && $0.end <= map.duration + Self.markSlack && $0.end > $0.start
    }
    self = map
  }

  /// The file's bytes, as the Mac writes it (keys in order).
  public func encoded() -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(self)
  }

  /// The map of an MP3 file's bytes with the marks made on it, or nil when the bytes hold no MP3
  /// frames or frames of more than one length in time (a map counts every frame as equally long).
  public static func make(
    mp3 bytes: [UInt8], feed: String, guid: String, sha256: String, marks: [EpisodeMapMark]
  ) -> EpisodeMap? {
    let parse = MP3Frames.parse(bytes)
    guard let first = parse.frames.first,
      parse.frames.allSatisfy({ abs($0.duration - first.duration) < 1e-9 })
    else { return nil }
    return EpisodeMap(
      feed: feed, guid: guid, sha256: sha256, duration: parse.seconds,
      frameSeconds: first.duration, frames: Data(parse.frames.map { short($0.hash) }),
      marks: marks.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start })
  }
}

/// The frames a phone has of its own copy so far: one byte for each (as in a map) and when each
/// starts in the phone's copy.
public struct HeardFrames: Sendable, Equatable {
  public private(set) var hashes: [UInt8] = []
  public private(set) var starts: [Double] = []
  /// Where the last frame ends.
  public private(set) var end = 0.0

  public init() {}

  /// Frames that are all `frameSeconds` long, the first one starting at `from`.
  public init(hashes: [UInt8], frameSeconds: Double, from: Double = 0) {
    self.hashes = hashes
    starts = hashes.indices.map { from + Double($0) * frameSeconds }
    end = from + Double(hashes.count) * frameSeconds
  }

  public var count: Int { hashes.count }

  /// Adds frames that follow the ones there, with the times they carry.
  public mutating func add(_ frames: [MP3Frame]) {
    for frame in frames {
      hashes.append(EpisodeMap.short(frame.hash))
      starts.append(frame.start)
      end = frame.start + frame.duration
    }
  }

  /// When frame `index` starts; for the count itself, where the last frame ends.
  func time(_ index: Int) -> Double { index < starts.count ? starts[index] : end }
}
