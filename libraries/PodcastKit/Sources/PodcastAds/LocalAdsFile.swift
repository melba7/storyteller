// LOFI-FORK: puts the local finders' ads into an episode's ads files (see FORK.md).
import Foundation

/// The player skips what is in an episode's ads files: a partial file while the episode is still
/// being checked, a final file after. These functions add the ads the local finders found.
public enum LocalAdsFile {
  /// Adds `found` to the episode's partial ads file, making the file when there is none.
  /// True when the file was written.
  @discardableResult
  public static func addToPartial(
    _ found: [FoundAd], store: AdsStore, detector: String, detectorVersion: String,
    osVersion: String, duration: Double, covered: Double
  ) -> Bool {
    guard store.load(detector: detector) == nil else { return false }
    let existing = store.loadPartial(detector: detector)
    let added = found.filter { !(existing?.isUndone($0) ?? false) }
    if existing == nil && added.isEmpty { return false }
    var file =
      existing
      ?? AdsFile(
        sha256: store.sha256, detector: detector, detectorVersion: detectorVersion,
        osVersion: osVersion, duration: duration, ads: [])
    let ads = AdJoin.join(file.ads + added)
    let reach = max(file.coveredUntil ?? covered, covered)
    guard existing == nil || ads != file.ads || reach != file.coveredUntil else { return false }
    file.ads = ads
    file.coveredUntil = reach
    return (try? store.savePartial(file)) != nil
  }

  /// Adds `found` to the episode's final ads file. The file as it is now, or nil when there is none.
  @discardableResult
  public static func addToFinal(_ found: [FoundAd], store: AdsStore, detector: String) -> AdsFile? {
    guard var file = store.load(detector: detector) else { return nil }
    let ads = AdJoin.join(file.ads + found.filter { !file.isUndone($0) })
    guard ads != file.ads else { return file }
    let before = file
    file.ads = ads
    guard (try? store.save(file)) != nil else { return before }
    return store.load(detector: detector) ?? file
  }

  /// Saves `found` as the episode's final ads file, for a phone with no model to ask.
  public static func saveFinal(
    _ found: [FoundAd], store: AdsStore, detector: String, detectorVersion: String,
    osVersion: String, duration: Double
  ) throws -> AdsFile {
    let undone = store.loadPartial(detector: detector)?.undone ?? []
    var file = AdsFile(
      sha256: store.sha256, detector: detector, detectorVersion: detectorVersion,
      osVersion: osVersion, duration: duration, ads: [], undone: undone)
    file.ads = AdJoin.join(found.filter { !file.isUndone($0) })
    try store.save(file)
    store.removeScratch(detector: detector)
    return file
  }
}
