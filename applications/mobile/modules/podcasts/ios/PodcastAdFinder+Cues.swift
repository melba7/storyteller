// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The two finders that move skips with the cues the Mac learned (`ad-cues.json`, `CueAds` in
// PodcastAds): opening lines and filled holes. They run in the whole-transcript pass, right after
// the borders were put on the joints and before the questions are picked, so what they add is in
// the file's ads when the questions and the maybes look at it. Each runs under its own mark in
// `PodcastFinderGuard`, and only at the level skip: these finders never ask, so a level of ask
// reads as off.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
  /// Adds the stretches of both finders to `file` and says how many each added. Nothing when the
  /// Mac taught no cues or the finder may not work now. `marks` are the Mac's marks of this
  /// episode: the ad-end check leaves an end that is a mark's end, also when the mark lost its
  /// finder's name in a join.
  func addCueStretches(
    _ id: String, _ modes: NewModes, _ transcript: Transcript, to file: inout AdsFile,
    marks: [FoundAd]
  ) -> (openings: Int, holes: Int) {
    let cues = PodcastTeaching.shared.files.cues
    guard !cues.isEmpty, allowedNow else { return (0, 0) }
    let guardian = PodcastFinderGuard.shared
    var openings = 0
    var holes = 0
    if modes.level(FinderNames.openingLines) == .skip {
      let skips = cueSkips(file, modes)
      let found = guardian.hold([FinderNames.openingLines], episode: id) { _ in
        CueAds.openings(lines: transcript.lines, skips: skips, cues: cues, show: modes.show)
      }
      openings = keepCueStretches(found ?? [], in: &file, modes)
    }
    if modes.level(FinderNames.filledHoles) == .skip {
      let skips = cueSkips(file, modes)
      let found = guardian.hold([FinderNames.filledHoles], episode: id) { _ in
        CueAds.holes(
          lines: transcript.lines, skips: skips, cues: cues, show: modes.show, marks: marks)
      }
      holes = keepCueStretches(found ?? [], in: &file, modes)
    }
    return (openings, holes)
  }

  /// The skips of the file as it stands: unsure or better, of a sort the listener skips, and not
  /// undone by the listener.
  private func cueSkips(_ file: AdsFile, _ modes: NewModes) -> [FoundAd] {
    file.ads.filter {
      $0.confidence >= .unsure && modes.listener.allows($0.kind) && !file.isUndone($0)
    }
  }

  /// Puts what a finder returned into the file's ads, in order of start, and returns how many it
  /// kept: those of a sort the listener skips that the settings put at skip, over no ad of the
  /// file, no stretch the listener undid and no "no" answer. They are not cut back with
  /// `NewAds.outside` and its gap: these stretches touch the ads they extend on purpose, so the
  /// player's chain (`AdSkipper.chainGap`) skips both in one jump. They are not joined with the
  /// file's ads either, so each keeps its finder's `source` and the guard hears of an Undo.
  private func keepCueStretches(
    _ found: [FoundAd], in file: inout AdsFile, _ modes: NewModes
  ) -> Int {
    let wanted = found.filter { modes.listener.allows($0.kind) }
    let placed = modes.tuning.apply(to: wanted, show: modes.show).skip
    var kept = 0
    for ad in placed {
      guard !file.ads.contains(where: { NewAds.overlap($0, ad) }), !file.isUndone(ad),
        !(file.denied ?? []).contains(where: { NewAds.overlap($0, ad) })
      else { continue }
      file.ads.append(ad)
      kept += 1
    }
    if kept > 0 { file.ads.sort { $0.start < $1.start } }
    return kept
  }
}
