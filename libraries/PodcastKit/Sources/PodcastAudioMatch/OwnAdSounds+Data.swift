// LOFI-FORK: the phone's own sounds as the text of a file (see FORK.md).
//
// The file is the Mac's `ad-sounds.json` (version 1, step 8, a list of sounds with their anchors
// as base 64) with a `show` and a `lastSeen` added to each sound, and a list `undone` of the
// prints of stretches the listener undid. `AdSoundLibrary(data:)` reads it too and ignores what
// it does not know. Foundation only.
import Foundation

extension OwnAdSounds {
  /// What a sound looks like in the file.
  private struct Wire: Codable {
    var show: String
    var lastSeen: Double
    var sort: String
    var who: String
    var frames: Int
    var seconds: Double
    var seen: Int
    var anchors: String
  }

  /// A sound that cannot be read is left out alone, not the whole file.
  private struct Lenient: Decodable {
    var wire: Wire?
    init(from decoder: Decoder) throws { wire = try? Wire(from: decoder) }
  }

  private struct File: Decodable {
    var version: Int
    var step: Int
    var sounds: [Lenient]
    var undone: [Lenient]?
  }

  private struct Out: Encodable {
    var version = OwnAdSounds.currentVersion
    var step = AdSoundLibrary.step
    var sounds: [Wire]
    var undone: [Wire]
  }

  /// The file's bytes, with sorted keys. Write them after `learn` and `forget`.
  public var data: Data { Self.encoded(entries[...], undone) }

  /// What a file holds. Empty when the data is larger than `maxBytes`, is not JSON, is of another
  /// version or step, or does not hold a list of sounds. A sound that breaks the rules of the
  /// format is left out alone, and the count limits are applied.
  public static func read(_ data: Data) -> OwnAdSounds {
    guard data.count <= maxBytes,
      let file = try? JSONDecoder().decode(File.self, from: data),
      file.version == currentVersion, file.step == AdSoundLibrary.step
    else { return OwnAdSounds() }
    var own = OwnAdSounds()
    own.entries = file.sounds.compactMap { $0.wire.flatMap { entry($0, undone: false) } }
    own.undone = (file.undone ?? []).compactMap { $0.wire.flatMap { entry($0, undone: true) } }
    own.limitCounts()
    return own
  }

  /// The entry of one sound of the file, or nil when it breaks a rule of the format.
  private static func entry(_ wire: Wire, undone: Bool) -> OwnAdSound? {
    guard AdSoundLibrary.sorts.contains(wire.sort), (1...AdSoundLibrary.maxFrames).contains(wire.frames),
      (0...AdSoundLibrary.maxSeen).contains(wire.seen), wire.seconds.isFinite,
      (1...600).contains(wire.seconds), isTime(wire.lastSeen),
      undone || isName(wire.show), wire.show.utf8.count <= mostNameBytes,
      wire.who.utf8.count <= mostNameBytes, let bytes = Data(base64Encoded: wire.anchors),
      bytes.count % 4 == 0, bytes.count / 4 >= AdSoundLibrary.minAnchors,
      bytes.count / 4 == (wire.frames + AdSoundLibrary.step - 1) / AdSoundLibrary.step
    else { return nil }
    let anchors = stride(from: 0, to: bytes.count, by: 4).map { at -> UInt32 in
      (0..<4).reduce(0) { $0 | UInt32(bytes[bytes.startIndex + at + $1]) << (8 * UInt32($1)) }
    }
    return OwnAdSound(
      show: wire.show, lastSeen: wire.lastSeen,
      sound: AdSound(
        sort: wire.sort, who: wire.who, frames: wire.frames, seconds: wire.seconds, seen: wire.seen,
        anchors: anchors))
  }

  private static func wire(_ entry: OwnAdSound) -> Wire {
    let sound = entry.sound
    let bytes = sound.anchors.flatMap { anchor in
      (0..<4).map { UInt8(truncatingIfNeeded: anchor >> (8 * UInt32($0))) }
    }
    return Wire(
      show: entry.show, lastSeen: entry.lastSeen, sort: sound.sort, who: sound.who,
      frames: sound.frames, seconds: sound.seconds, seen: sound.seen,
      anchors: Data(bytes).base64EncodedString())
  }

  /// The bytes of a file holding these sounds and undone stretches. Empty bytes (which read as an
  /// empty library) when a number cannot be written, which the rules above keep from happening.
  static func encoded(_ sounds: ArraySlice<OwnAdSound>, _ undone: [OwnAdSound]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(Out(sounds: sounds.map(wire), undone: undone.map(wire)))) ?? Data()
  }

  /// Drops the oldest sounds until the file is no larger than `maxBytes`. The sounds are the
  /// newest first, so the most that fit is found by halving.
  mutating func fit(maxBytes: Int) {
    guard Self.encoded(entries[...], undone).count > maxBytes else { return }
    var low = 0  // this many sounds always fit, if the undone prints do
    var high = entries.count
    while low < high {
      let middle = (low + high + 1) / 2
      if Self.encoded(entries[..<middle], undone).count <= maxBytes {
        low = middle
      } else {
        high = middle - 1
      }
    }
    entries = Array(entries.prefix(low))
    if Self.encoded(entries[...], undone).count > maxBytes { undone = [] }
  }
}
