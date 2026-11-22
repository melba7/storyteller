// LOFI-FORK: puts the local finders' ads into an episode's ads files (see FORK.md).
import Foundation

/// The player skips what is in an episode's ads files: a partial file while the episode is still
/// being checked, a final file after. These functions add the ads the local finders found.
public enum LocalAdsFile {
  /// The `detectorVersion` of a final file that only the local finders made. It is the result
  /// while the model cannot be asked, and old once it can (`AdsRules.status`).
  public static let localVersion = ""

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
    let ads = joined(file, adding: added)
    let reach = max(file.coveredUntil ?? covered, covered)
    guard existing == nil || ads != file.ads || reach != file.coveredUntil else { return false }
    file.ads = ads
    file.coveredUntil = reach
    return (try? store.savePartial(file)) != nil
  }

  /// The file's ads and `added` joined. Ads the listener undid take no part in the join (a new
  /// ad beside one would be joined to it and lost with it); they stay in the list as they were.
  private static func joined(_ file: AdsFile, adding added: [FoundAd]) -> [FoundAd] {
    let undone = file.ads.filter { file.isUndone($0) }
    let live = file.ads.filter { !file.isUndone($0) }
    return (AdJoin.join(live + added) + undone).sorted { $0.start < $1.start }
  }

  /// Adds `found` to the episode's final ads file. The file as it is now, or nil when there is none.
  @discardableResult
  public static func addToFinal(_ found: [FoundAd], store: AdsStore, detector: String) -> AdsFile? {
    guard var file = store.load(detector: detector) else { return nil }
    let ads = joined(file, adding: found.filter { !file.isUndone($0) })
    guard ads != file.ads else { return file }
    let before = file
    file.ads = ads
    guard (try? store.save(file)) != nil else { return before }
    return store.load(detector: detector) ?? file
  }

  /// Saves `found` as the episode's final ads file, for a phone with no model to ask.
  ///
  /// With `afterFailure` (the model could not be asked, or its run failed), what the model found
  /// so far (the partial file's ads) stays in the result, and the scratch files stay, so the
  /// next run of the model asks only the pieces it has no answer for. Without it, the scratch
  /// files go.
  public static func saveFinal(
    _ found: [FoundAd], store: AdsStore, detector: String, detectorVersion: String,
    osVersion: String, duration: Double, afterFailure: Bool = false
  ) throws -> AdsFile {
    let partial = store.loadPartial(detector: detector)
    var file = AdsFile(
      sha256: store.sha256, detector: detector, detectorVersion: detectorVersion,
      osVersion: osVersion, duration: duration, ads: [],
      undone: store.undoneSoFar(detector: detector))
    // After a failed run, what the model found stays: the pieces done now, and the ads of an
    // older model result that is being replaced (a local-only final file has none to keep).
    var modelAds = afterFailure ? partial?.ads ?? [] : []
    if afterFailure, let older = store.load(detector: detector),
      older.detectorVersion != localVersion
    {
      modelAds += older.ads
    }
    file.ads = AdJoin.join((found + modelAds).filter { !file.isUndone($0) })
    try store.save(file)
    if !afterFailure { store.removeScratch(detector: detector) }
    return file
  }

  /// A local-only final file is about to be replaced by the model's run, which starts from the
  /// partial file. The skips the listener took back from the local result are put there, so the
  /// model's result keeps them. Nothing is done for any other final file.
  public static func carryChoices(store: AdsStore, detector: String) {
    guard let final = store.load(detector: detector), final.detectorVersion == localVersion,
      !final.undone.isEmpty
    else { return }
    var partial =
      store.loadPartial(detector: detector)
      ?? AdsFile(
        sha256: store.sha256, detector: detector, detectorVersion: final.detectorVersion,
        osVersion: final.osVersion, duration: final.duration, ads: [], coveredUntil: 0)
    let missing = final.undone.filter { !partial.undone.contains($0) }
    guard !missing.isEmpty else { return }
    partial.undone += missing
    try? store.savePartial(partial)
  }
}
