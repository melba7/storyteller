// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What a stream's head scan does with the layers that need no model of Apple's: after each step
// the words so far go through the word rules, the promo rules and, when the phone has been taught
// one, the small model (LocalAds, from PodcastTeaching), and the bytes the step already holds go
// through the sounds the Mac taught and the phone's own sounds, and the borders of what was found
// snap onto the joints of those bytes. One diary line says what they found and how long it took.
// Called from the scan's own background task: the sound matching reads up to 6 MB of bytes.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastTranscripts

extension PodcastStreamHead {
  /// The ads of the local layers and of the taught sounds in `audio` (the audio of this step).
  /// `episodeDuration` is the episode's length when it is known.
  func findLocal(
    lines: [TranscriptLine], transcript: Transcript, sponsors: [SponsorName],
    episodeDuration: Double?, audio: Data
  ) -> [FoundAd] {
    let started = Date()
    let teaching = PodcastTeaching.shared
    let ranges = teaching.files.local.ranges(
      lines: AdChunker.number(lines), sponsors: sponsors, episodeDuration: episodeDuration)
    let local = AdCleanup.run(ranges: ranges, transcript: transcript)
    let sounds = teaching.soundAds(in: audio)
    PodcastTimeline.mark(
      episodeId,
      HeadNotes.local(
        ads: local.count, sounds: sounds.count,
        milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
    return withOwnSoundsAndJoints(local + sounds, audio: audio)
  }

  /// `found` with what the phone's own sounds add in `audio`, and with every border put on a
  /// joint of `audio` when the listener's switches, the show's settings and the guard allow it.
  /// Only the own sounds that may skip are added (the head scan asks no questions), and only the
  /// parts outside `found`, so they can only add. Both are new finders: a guard mark is on disk
  /// while they run, and iOS holds the time. `found` itself when nothing may run.
  private func withOwnSoundsAndJoints(_ found: [FoundAd], audio: Data) -> [FoundAd] {
    guard let show = EpisodeShows.shared.show(for: episodeId), !show.isEmpty else { return found }
    let listener = PodcastAdFinder.listenerSwitches(forShow: show)
    guard listener.skipsAnySort else { return found }
    let tuning = PodcastTeaching.shared.files.tuning
    let guardian = PodcastFinderGuard.shared
    let own = ShowTuning.stricter(
      guardian.mode(finder: FinderNames.ownSound, show: show, episode: episodeId),
      tuning.level(forFinder: FinderNames.ownSound, show: show))
    let snaps =
      tuning.joints(show: show)
      && guardian.mode(finder: FinderNames.joints, show: show, episode: episodeId) == .skip
    var pass = SoundPass()
    if own == .skip { pass.own = PodcastOwnSounds.shared.library(for: show) }
    pass.wantsJoints = snaps
    var finders: [String] = []
    if pass.consumers.contains(.own) { finders.append(FinderNames.ownSound) }
    if pass.consumers.contains(.joints) { finders.append(FinderNames.joints) }
    guard !finders.isEmpty else { return found }
    let result = guardian.hold(finders, episode: episodeId) { held -> SoundPassResult in
      var allowed = pass
      if !held.finders.contains(FinderNames.ownSound) { allowed.own = AdSoundLibrary() }
      if !held.finders.contains(FinderNames.joints) { allowed.wantsJoints = false }
      return allowed.run(data: audio)
    }
    guard let result else { return found }
    var ads = found
    if result.ran.contains(.own) {
      let heard = NewAds.ads(ofSounds: result.own).filter { listener.allows($0.kind) }.map {
        ad -> FoundAd in
        var one = ad
        one.source = FinderNames.ownSound
        one.confidence = .unsure
        return one
      }
      ads += tuning.apply(to: NewAds.outside(heard, of: found), show: show).skip
    }
    var moved = 0
    if result.ran.contains(.joints), let joints = result.joints {
      let snapped = NewAds.snap(
        ads.sorted { $0.start < $1.start }, joints: joints,
        steadyToo: tuning.steadyJoints(show: show))
      ads = snapped.ads
      moved = snapped.moved.count
    }
    if ads.count != found.count || moved > 0 {
      PodcastTimeline.mark(
        episodeId, "head: \(ads.count - found.count) own sounds, \(moved) borders on joints")
    }
    return ads
  }
}
