// LOFI-FORK: the library of ad sounds, the file the Mac writes and the phone reads (see FORK.md).
//
// Podcast hosts splice ready-made ad recordings into episodes as they are, so the same ad is the
// same MP3 frames in another episode. A taught sound keeps one number of every eighth frame (its
// anchors), which is enough to recognise it again by its bytes alone. Foundation only.
import Foundation

/// One taught sound: a stretch of audio that is an ad wherever it plays.
public struct AdSound: Sendable, Equatable {
  /// "sponsor", "network_promo", "host_ask" or "intro_credits".
  public var sort: String
  public var who: String
  /// Its length in frames and in seconds.
  public var frames: Int
  public var seconds: Double
  /// In how many episodes the Mac met it.
  public var seen: Int
  /// The low 32 bits of the hash of every `step`th frame, from its first frame.
  public var anchors: [UInt32]

  public init(sort: String, who: String, frames: Int, seconds: Double, seen: Int, anchors: [UInt32]) {
    self.sort = sort
    self.who = who
    self.frames = frames
    self.seconds = seconds
    self.seen = seen
    self.anchors = anchors
  }
}

public struct AdSoundLibrary: Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "ad-sounds.json"
  public static let step = 8
  /// The most bytes the phone reads.
  public static let maxBytes = 5_000_000
  /// The most bytes the Mac publishes (`teach_publish.py` refuses a larger file).
  public static let publishBytes = 4_500_000
  /// The most frames a sound may have: ten minutes of the shortest MP3 frames (24 ms).
  static let maxFrames = 25_000
  /// The most episodes a sound may claim to have been seen in.
  static let maxSeen = 1_000_000
  static let sorts: Set<String> = ["sponsor", "network_promo", "host_ask", "intro_credits"]
  static let minAnchors = 8

  public var sounds: [AdSound]

  public init(sounds: [AdSound] = []) { self.sounds = sounds }

  /// What a sound looks like in the file.
  private struct Wire: Codable {
    var sort: String
    var who: String
    var frames: Int
    var seconds: Double
    var seen: Int
    var anchors: String
  }

  private struct Lenient: Decodable {
    var wire: Wire?
    init(from decoder: Decoder) throws { wire = try? Wire(from: decoder) }
  }

  private struct File: Decodable {
    var version: Int
    var step: Int
    var sounds: [Lenient]
  }

  private struct Out: Encodable {
    var version = AdSoundLibrary.currentVersion
    var step = AdSoundLibrary.step
    var sounds: [Wire]
  }

  /// Reads a library file. Nil when the data is too large, is not JSON, is of another version or
  /// step, or does not hold a list of sounds. A sound that cannot be trusted is left out alone.
  public init?(data: Data) {
    guard data.count <= AdSoundLibrary.maxBytes,
      let file = try? JSONDecoder().decode(File.self, from: data),
      file.version == AdSoundLibrary.currentVersion, file.step == AdSoundLibrary.step
    else { return nil }
    sounds = file.sounds.compactMap { $0.wire.flatMap(AdSoundLibrary.sound) }
  }

  /// The sound of one entry of the file, or nil when it breaks a rule of the format.
  private static func sound(_ wire: Wire) -> AdSound? {
    guard sorts.contains(wire.sort), (1...maxFrames).contains(wire.frames),
      (0...maxSeen).contains(wire.seen), wire.seconds.isFinite,
      (1...600).contains(wire.seconds), let bytes = Data(base64Encoded: wire.anchors),
      bytes.count % 4 == 0, bytes.count / 4 >= minAnchors,
      bytes.count / 4 == (wire.frames + step - 1) / step
    else { return nil }
    let anchors = stride(from: 0, to: bytes.count, by: 4).map { at -> UInt32 in
      (0..<4).reduce(0) { $0 | UInt32(bytes[bytes.startIndex + at + $1]) << (8 * UInt32($1)) }
    }
    return AdSound(
      sort: wire.sort, who: wire.who, frames: wire.frames, seconds: wire.seconds, seen: wire.seen,
      anchors: anchors)
  }

  /// The file's bytes, with sorted keys.
  public func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(Out(sounds: sounds.map(AdSoundLibrary.wire)))
  }

  private static func wire(_ sound: AdSound) -> Wire {
    let bytes = sound.anchors.flatMap { anchor in
      (0..<4).map { UInt8(truncatingIfNeeded: anchor >> (8 * UInt32($0))) }
    }
    return Wire(
      sort: sound.sort, who: sound.who, frames: sound.frames, seconds: sound.seconds,
      seen: sound.seen, anchors: Data(bytes).base64EncodedString())
  }

  /// The library in `url`, or an empty one when the file is missing or cannot be read.
  public static func load(from url: URL) -> AdSoundLibrary {
    (try? Data(contentsOf: url)).flatMap { AdSoundLibrary(data: $0) } ?? AdSoundLibrary()
  }

  /// Checks `data` and writes it as `fileName` in `folder`, atomically. False when it is too
  /// large or does not read.
  public static func install(data: Data, folder: URL) -> Bool {
    guard AdSoundLibrary(data: data) != nil else { return false }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
      return true
    } catch {
      return false
    }
  }
}
