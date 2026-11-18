// LOFI-FORK: the ad files of a downloaded episode (see FORK.md).
import Foundation

/// An ad the listener undid: the skip was wrong. Saved so two detectors can be compared later.
public struct UndoneAd: Codable, Sendable, Equatable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

/// The finished result of one detector on one file, saved as `<sha256>.ads.<detector>.json`.
public struct AdsFile: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var version: Int
  public var sha256: String
  public var detector: String
  public var detectorVersion: String
  public var osVersion: String
  /// Seconds of audio.
  public var duration: Double
  public var ads: [FoundAd]
  /// The ads whose skip the listener took back.
  public var undone: [UndoneAd]
  /// For a partial file: the seconds of audio checked so far. Nil in a final file.
  public var coveredUntil: Double?
  /// How many pieces the model refused to read (counted as having no ads). Nil when none, so
  /// the app can tell a clean "no ads" from one with parts unread.
  public var refusedPieces: Int?

  public init(
    sha256: String, detector: String, detectorVersion: String, osVersion: String, duration: Double,
    ads: [FoundAd], undone: [UndoneAd] = [],
    coveredUntil: Double? = nil, refusedPieces: Int? = nil
  ) {
    self.version = Self.currentVersion
    self.sha256 = sha256
    self.detector = detector
    self.detectorVersion = detectorVersion
    self.osVersion = osVersion
    self.duration = duration
    self.ads = ads
    self.undone = undone
    self.coveredUntil = coveredUntil
    self.refusedPieces = refusedPieces
  }

  /// Whether the listener undid the skip of this ad.
  public func isUndone(_ ad: FoundAd) -> Bool {
    undone.contains { abs($0.start - ad.start) < 0.5 }
  }
}

/// Where one episode's ad files live: in its download folder next to the audio, so deleting
/// the download deletes them.
public struct AdsStore: Sendable {
  public let folder: URL
  public let sha256: String

  public init(folder: URL, sha256: String) {
    self.folder = folder
    self.sha256 = sha256
  }

  /// The file for a detector. Anything but letters, digits, `-` and `_` in its name is left
  /// out, so a name cannot point outside the folder.
  public func url(detector: String) -> URL {
    let safe = String(detector.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    return folder.appendingPathComponent("\(sha256).ads.\(safe).json")
  }

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  public func save(_ file: AdsFile) throws {
    try Self.encoder.encode(file).write(to: url(detector: file.detector), options: .atomic)
  }

  /// The detector's result for this file, or nil when there is none, it cannot be read, or it
  /// is of another file (a different sha256).
  public func load(detector: String) -> AdsFile? {
    guard let data = try? Data(contentsOf: url(detector: detector)),
      let file = try? JSONDecoder().decode(AdsFile.self, from: data),
      file.version == AdsFile.currentVersion, file.sha256 == sha256
    else { return nil }
    return file
  }

  /// The detector's result as saved, for the app to read, or nil as for `load`.
  public func json(detector: String) -> String? {
    guard load(detector: detector) != nil,
      let data = try? Data(contentsOf: url(detector: detector))
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Records that the listener undid the skip of the ad starting at `start`. False when
  /// there is no such ad in the file. Undoing twice is recorded once.
  @discardableResult
  public func markUndone(detector: String, adStart start: Double) -> Bool {
    let isFinal = load(detector: detector) != nil
    guard var file = best(detector: detector),
      let ad = file.ads.first(where: { abs($0.start - start) < 0.5 })
    else { return false }
    if !file.isUndone(ad) { file.undone.append(UndoneAd(start: ad.start, end: ad.end)) }
    return (try? (isFinal ? save(file) : savePartial(file))) != nil
  }
}
