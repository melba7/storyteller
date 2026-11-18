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

/// A skip the listener found too far: they went back into the ad that was just skipped, so from
/// then on that ad ends where they went back to. A trim only ever shortens an ad.
public struct AdTrim: Codable, Sendable, Equatable {
  /// Where the ad started when it was skipped.
  public var adStart: Double
  /// Where the ad ends from now on.
  public var end: Double

  public init(adStart: Double, end: Double) {
    self.adStart = adStart
    self.end = end
  }

  /// Whether this trim is for `ad`: the ad starts where the trimmed one did (a little earlier or
  /// later is the same ad found again) or runs over that place.
  func applies(to ad: FoundAd) -> Bool { ad.start - 0.5 <= adStart && adStart < ad.end }
}

extension FoundAd {
  /// This ad cut short by the trims that are for it: it ends at the earliest of its own end and
  /// theirs. An ad is never made longer.
  func trimmed(by trims: [AdTrim]) -> FoundAd {
    var ad = self
    for trim in trims where trim.applies(to: self) { ad.end = min(ad.end, trim.end) }
    return ad
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
  /// The skips the listener found too far. Nil when there are none (and in a file saved before
  /// trims existed).
  public var trims: [AdTrim]?

  public init(
    sha256: String, detector: String, detectorVersion: String, osVersion: String, duration: Double,
    ads: [FoundAd], undone: [UndoneAd] = [],
    coveredUntil: Double? = nil, refusedPieces: Int? = nil, trims: [AdTrim]? = nil
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
    self.trims = trims
  }

  /// Adds a trim. For the same ad the earlier end stays, so a trim never makes an ad longer.
  public mutating func addTrim(_ trim: AdTrim) {
    var list = trims ?? []
    if let index = list.firstIndex(where: { abs($0.adStart - trim.adStart) < 0.5 }) {
      list[index].end = min(list[index].end, trim.end)
    } else {
      list.append(trim)
    }
    trims = list
  }

  /// Whether the listener undid the skip of this ad: the ad starts where an undone one did, or
  /// overlaps it (the same ad found again a little later, or cut a little differently).
  public func isUndone(_ ad: FoundAd) -> Bool {
    undone.contains { abs($0.start - ad.start) < 0.5 || ($0.start < ad.end && ad.start < $0.end) }
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
    try Self.encoder.encode(carryingTrims(file)).write(
      to: url(detector: file.detector), options: .atomic)
  }

  /// `file` with the trims already saved for this detector (in its final or partial file). A
  /// detector that writes a file does not know them, and the listener's trims must outlive it.
  func carryingTrims(_ file: AdsFile) -> AdsFile {
    var carried = file
    for earlier in [load(detector: file.detector), loadPartial(detector: file.detector)] {
      for trim in earlier?.trims ?? [] { carried.addTrim(trim) }
    }
    return carried
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

  /// Records that the listener found the skip of the ad `trim` is for too far, so that ad ends
  /// at `trim.end` from now on. False when there is no such ad in the file.
  @discardableResult
  public func markTrimmed(detector: String, _ trim: AdTrim) -> Bool {
    let isFinal = load(detector: detector) != nil
    guard var file = best(detector: detector), file.ads.contains(where: { trim.applies(to: $0) })
    else { return false }
    file.addTrim(trim)
    return (try? (isFinal ? save(file) : savePartial(file))) != nil
  }
}
