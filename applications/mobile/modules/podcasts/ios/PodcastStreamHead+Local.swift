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
  /// The ads of the local layers and of the taught sounds in `audio` (the audio of this step),
  /// and apart from them the ads the phone's own sounds add (`own`, which the caller cuts again
  /// before it joins them, see `NewAds.headAds`). `episodeDuration` is the episode's length when
  /// it is known. `blockers` are the ads of the memory and the model, which the caller joins with
  /// these: a new finder keeps away from them.
  func findLocal(
    lines: [TranscriptLine], transcript: Transcript, sponsors: [SponsorName],
    episodeDuration: Double?, audio: Data, blockers: [FoundAd]
  ) -> (old: [FoundAd], own: [FoundAd]) {
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
    return withOwnSoundsAndJoints(local + sounds, audio: audio, blockers: blockers)
  }

  /// `found` with every border put on a joint of `audio`, and with what the phone's own sounds
  /// add in it, when the listener's switches, the show's settings and the guard allow it. The old
  /// ads come first: their borders snap, and a snap never goes into one of the `blockers` (the
  /// ads the memory and the model found, which are joined with these later). Then only the own
  /// sounds that may skip are added (the head scan asks no questions), and only the parts that
  /// lie outside every old ad, snapped or not, so a new finder only adds a stretch and never
  /// lengthens or upgrades an old ad. Both are new finders: a guard mark is on disk while they
  /// run (all of it, the snap and the sorting too), and iOS holds the time. `found` itself when
  /// nothing may run. The own sounds' ads come back apart from the old ones.
  private func withOwnSoundsAndJoints(
    _ found: [FoundAd], audio: Data, blockers: [FoundAd]
  ) -> (old: [FoundAd], own: [FoundAd]) {
    let unchanged = (old: found, own: [FoundAd]())
    guard let show = EpisodeShows.shared.show(for: episodeId), !show.isEmpty else {
      return unchanged
    }
    let listener = PodcastAdFinder.listenerSwitches(forShow: show)
    guard listener.skipsAnySort else { return unchanged }
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
    guard !finders.isEmpty else { return unchanged }
    let made = guardian.hold(finders, episode: episodeId) {
      held -> (old: [FoundAd], own: [FoundAd], moved: Int) in
      var allowed = pass
      if !held.finders.contains(FinderNames.ownSound) { allowed.own = AdSoundLibrary() }
      if !held.finders.contains(FinderNames.joints) { allowed.wantsJoints = false }
      let result = allowed.run(data: audio)
      var old = found
      var moved = 0
      if result.ran.contains(.joints), let joints = result.joints {
        let snapped = snap(
          found, among: blockers, joints: joints, steadyToo: tuning.steadyJoints(show: show))
        old = snapped.ads
        moved = snapped.moved
      }
      var added: [FoundAd] = []
      if result.ran.contains(.own) {
        let heard = NewAds.ads(ofSounds: result.own).filter { listener.allows($0.kind) }.map {
          ad -> FoundAd in
          var one = ad
          one.source = FinderNames.ownSound
          one.confidence = .unsure
          return one
        }
        added = tuning.apply(to: NewAds.outside(heard, of: old + blockers), show: show).skip
      }
      return (old, added, moved)
    }
    guard let made else {
      PodcastTimeline.mark(episodeId, "head: no time held")
      return unchanged
    }
    if !made.own.isEmpty || made.moved > 0 {
      PodcastTimeline.mark(
        episodeId, "head: \(made.own.count) own sounds, \(made.moved) borders on joints")
    }
    return (made.old, made.own)
  }

  /// The old ads with their borders on the joints. The blockers are neighbours that stay as they
  /// are: they hold the places the old ads may not move into, and they are not given back. It
  /// passes no `words`, so the head scan never pulls a late start back (`JointPull`).
  private func snap(
    _ found: [FoundAd], among blockers: [FoundAd], joints: Joints, steadyToo: Bool
  ) -> (ads: [FoundAd], moved: Int) {
    let all = (found.map { (ad: $0, fixed: false) } + blockers.map { (ad: $0, fixed: true) })
      .sorted { $0.ad.start < $1.ad.start }
    let snapped = NewAds.snap(
      all.map(\.ad), joints: joints, steadyToo: steadyToo, leaving: { blockers.contains($0) })
    let mine = zip(all, snapped.ads).filter { !$0.0.fixed }.map(\.1)
    return (mine, snapped.moved.count)
  }
}
