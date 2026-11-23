// LOFI-FORK: the audio code `podcast-teach score` hands to the score command (see FORK.md). The
// rows are made in PodcastAds (AdScoreRows, SoundScoreLayers); this file only connects them to
// PodcastAudioMatch, which PodcastAds cannot see, and to Apple's sentence embedding. It has no
// logic of its own to test beyond the plain functions it calls, which are tested in
// PodcastAudioMatchTests (ScoreSoundsTests) and PodcastAdsTests (SoundScoreLayersTests).
import Foundation
import PodcastAds
import PodcastAudioMatch

#if canImport(NaturalLanguage)
  import PodcastAdsOnDevice
#endif

enum AudioScoreLayers {
  /// The sound finders and the embedder, for one run of the command.
  static func extras() -> ScoreExtras {
    ScoreExtras(
      sounds: { folder, now in AudioScoreBox(folder: folder, now: now).kit },
      embedder: embedder)
  }

  /// Apple's English sentence embedding of the revision the model was trained on, or nil when
  /// this build has none (Linux) or this Mac does not have that revision.
  @Sendable
  static func embedder(for model: AdMeaningModel) -> LineEmbedder? {
    #if canImport(NaturalLanguage)
      return AppleLineEmbedder(revision: model.revision)
    #else
      return nil
    #endif
  }
}

/// What the sound rows learn while the scorecard goes through the episodes in order: the phone's
/// own sounds, the prints of each show's last episodes and the joints of the file being looked at.
/// The scorecard calls one row at a time, but the compiler cannot know it, so a lock guards all.
final class AudioScoreBox: @unchecked Sendable {
  private let lock = NSLock()
  private let now: Double
  /// The Mac's library of ad sounds: what it holds the phone's own sounds do not learn again.
  private let mac: AdSoundLibrary
  private var own = OwnAdSounds()
  private var prints: [String: ShowPrints] = [:]
  /// Counts the episodes that were scanned: the print of a later episode is the newer one.
  private var scanned = 0.0
  /// The joints of the file looked at last. The rows of one episode come one after the other, so
  /// one file at a time is enough, and a long run does not keep every file's joints.
  private var lastJoints: (path: String, joints: Joints?)?
  /// The joints the Mac found before (`podcast-teach joints`), by episode id.
  private let kept: [String: Joints]

  init(folder: URL, now: Date) {
    self.now = now.timeIntervalSince1970
    mac = AdSoundLibrary.load(from: folder.appendingPathComponent(AdSoundLibrary.fileName))
    let loaded = JointsCache.load(from: folder.appendingPathComponent(JointsCache.fileName))
    if let problem = loaded.problem { FileHandle.standardError.write(Data((problem + "\n").utf8)) }
    kept = loaded.cache.episodes
  }

  var kit: ScoreSoundKit {
    ScoreSoundKit(
      ownSounds: { [self] url, show, _, learn in ownSounds(url, show, learn) },
      repeatedSounds: { [self] url, show, episode in repeatedSounds(url, show, episode) },
      snapJoints: { [self] url, spans, steady in snapJoints(url, spans, steady) },
      cachedJoints: ScoreCachedJoints(
        has: { [self] in kept[$0] != nil },
        snap: { [self] id, spans, steady in
          guard let joints = kept[id] else { return spans }
          return snapped(spans, joints, steady)
        }))
  }

  /// The sounds the show's earlier episodes taught that play in this file, and then what this
  /// episode's skipped stretches teach: an episode is never searched with its own ads.
  private func ownSounds(_ url: URL, _ show: String, _ learn: [ScoreSpan]) -> [ScoreSpan] {
    lock.lock()
    defer { lock.unlock() }
    let stretches = learn.map { MarkedStretch(start: $0.start, end: $0.end, sort: $0.sort, who: "") }
    let found = ScoreSounds.scanThenLearn(
      &own, show: show, in: url, stretches: stretches, mac: mac, now: now)
    return found.map { ScoreSpan(start: $0.start, end: $0.end, sort: $0.sort) }
  }

  /// The stretches an earlier episode of the show also had, and then this episode's print is kept.
  private func repeatedSounds(_ url: URL, _ show: String, _ episode: String) -> [ScoreSpan] {
    lock.lock()
    defer { lock.unlock() }
    scanned += 1
    let result = ScoreSounds.scanRepeats(
      in: url, older: prints[show]?.prints ?? [], episode: episode, date: scanned)
    if let print = result.print { prints[show] = (prints[show] ?? ShowPrints()).adding(print) }
    return result.spans.map { ScoreSpan(start: $0.start, end: $0.end, sort: $0.sort) }
  }

  /// The stretches with their borders on the joints of the file; as they were when the file has
  /// no joints to use.
  private func snapJoints(_ url: URL, _ spans: [ScoreSpan], _ steady: Bool) -> [ScoreSpan] {
    lock.lock()
    defer { lock.unlock() }
    let joints: Joints?
    if let last = lastJoints, last.path == url.path {
      joints = last.joints
    } else {
      joints = ScoreSounds.joints(in: url)
      lastJoints = (url.path, joints)
    }
    guard let joints else { return spans }
    return snapped(spans, joints, steady)
  }

  private func snapped(_ spans: [ScoreSpan], _ joints: Joints, _ steady: Bool) -> [ScoreSpan] {
    let moved = ScoreSounds.snap(
      spans.map { SoundSpan(start: $0.start, end: $0.end, sort: $0.sort) }, joints: joints,
      steadyToo: steady)
    return moved.map { ScoreSpan(start: $0.start, end: $0.end, sort: $0.sort) }
  }
}
