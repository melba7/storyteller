// LOFI-FORK: the sound bank, what is kept of an episode's ads so that its audio can be deleted (see FORK.md).
//
// Learning an ad sound needs very little of an episode: for every frame of each marked stretch, the
// low 32 bits of its hash (the anchors and the matching use no more), when it starts and how long
// it lasts. The bank keeps just that, 12 bytes a frame, in `sound-bank/<episode id>.json` in the
// teaching folder. `podcast-teach sounds` writes it next to the audio and learns from it when the
// audio is gone. Foundation only.
import Foundation

/// One frame of a banked stretch.
public struct BankedFrame: Sendable, Equatable {
  /// The low 32 bits of the frame's hash.
  public var hash: UInt32
  /// Seconds from the first frame of the stretch, and how long the frame lasts.
  public var start: Float
  public var duration: Float

  public init(hash: UInt32, start: Float, duration: Float) {
    self.hash = hash
    self.start = start
    self.duration = duration
  }
}

/// A stretch of an episode that was marked as an ad, as the bank keeps it: its frames.
public struct BankedStretch: Sendable, Equatable {
  public var sort: String
  public var who: String
  public var frames: [BankedFrame]

  public init(sort: String, who: String, frames: [BankedFrame]) {
    self.sort = sort
    self.who = who
    self.frames = frames
  }

  /// How long the stretch lasts: the frames' durations added up in order.
  public var seconds: Double { frames.reduce(0) { $0 + Double($1.duration) } }
}

public enum SoundBank {
  public static let currentVersion = 1
  /// The folder of the teaching folder that holds one file for each episode learned from.
  public static let folderName = "sound-bank"
  static let bytesPerFrame = 12

  /// What a stretch looks like in the file: its frames as one base64 text of
  /// (UInt32 hash, Float32 start, Float32 duration) for each frame, little endian.
  private struct Wire: Codable {
    var sort: String
    var who: String
    var frames: Int
    var data: String
  }

  private struct File: Codable {
    var version: Int
    var episode: String
    /// The folder of labels the stretches were cut from ("labels" or "labels-snapped"). A file
    /// without it still reads: the name only tells the cleanup in teach_free.py whether the bank
    /// is as exact as the audio would be.
    var labels: String?
    var stretches: [Wire]
  }

  public static func fileURL(episode: String, in folder: URL) -> URL {
    folder.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(episode + ".json")
  }

  /// The file's bytes, with sorted keys, so the same stretches always make the same bytes.
  public static func data(episode: String, stretches: [BankedStretch], labels: String = "labels") throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(
      File(version: currentVersion, episode: episode, labels: labels, stretches: stretches.map(wire)))
  }

  private static func wire(_ stretch: BankedStretch) -> Wire {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(stretch.frames.count * bytesPerFrame)
    func put(_ value: UInt32) {
      for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }
    for frame in stretch.frames {
      put(frame.hash)
      put(frame.start.bitPattern)
      put(frame.duration.bitPattern)
    }
    return Wire(
      sort: stretch.sort, who: stretch.who, frames: stretch.frames.count,
      data: Data(bytes).base64EncodedString())
  }

  /// Reads a bank file. Nil when the data is not JSON, is of another version or another episode,
  /// or holds a stretch whose data does not fit its frame count or has a time that cannot be one.
  public static func stretches(from data: Data, episode: String) -> [BankedStretch]? {
    guard let file = try? JSONDecoder().decode(File.self, from: data),
      file.version == currentVersion, file.episode == episode
    else { return nil }
    var stretches: [BankedStretch] = []
    for wire in file.stretches {
      guard let stretch = stretch(wire) else { return nil }
      stretches.append(stretch)
    }
    return stretches
  }

  private static func stretch(_ wire: Wire) -> BankedStretch? {
    // The length is checked by dividing, so a huge frame count cannot overflow.
    guard wire.frames >= 0, let data = Data(base64Encoded: wire.data),
      data.count % bytesPerFrame == 0, data.count / bytesPerFrame == wire.frames
    else { return nil }
    let bytes = [UInt8](data)
    func get(_ at: Int) -> UInt32 {
      (0..<4).reduce(0) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
    }
    var frames: [BankedFrame] = []
    frames.reserveCapacity(wire.frames)
    for at in stride(from: 0, to: bytes.count, by: bytesPerFrame) {
      let start = Float(bitPattern: get(at + 4))
      let duration = Float(bitPattern: get(at + 8))
      guard start.isFinite, start >= 0, duration.isFinite, duration >= 0 else { return nil }
      frames.append(BankedFrame(hash: get(at), start: start, duration: duration))
    }
    return BankedStretch(sort: wire.sort, who: wire.who, frames: frames)
  }

  /// The stretches in the bank file of `episode`, or nil when the file is missing or does not read.
  public static func load(episode: String, in folder: URL) -> [BankedStretch]? {
    (try? Data(contentsOf: fileURL(episode: episode, in: folder)))
      .flatMap { stretches(from: $0, episode: episode) }
  }

  /// Writes the bank file of `episode`, atomically, but only when it is missing or different (a
  /// file that does not read counts as different; a file that is the same is touched so that it is
  /// as new as this run). True when it wrote the file. An episode with no
  /// stretches gets a file too, with an empty list: the file says the episode was learned.
  @discardableResult
  public static func save(
    _ stretches: [BankedStretch], episode: String, in folder: URL, labels: String = "labels"
  ) throws -> Bool {
    let bytes = try data(episode: episode, stretches: stretches, labels: labels)
    let url = fileURL(episode: episode, in: folder)
    if let old = try? Data(contentsOf: url), old == bytes {
      // The same bytes, but the file is current as of now: teach_free.py frees an episode's audio only
      // when its bank is newer than the marks it was cut from.
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
      return false
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: url, options: .atomic)
    return true
  }
}
