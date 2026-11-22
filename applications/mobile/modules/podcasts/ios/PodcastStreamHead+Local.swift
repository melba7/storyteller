// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What a stream's head scan does with the layers that need no model of Apple's: after each step
// the words so far go through the word rules, the promo rules and, when the phone has been taught
// one, the small model (LocalAds, from PodcastTeaching), and the bytes the step already holds go
// through the sounds the Mac taught. One diary line says what they found and how long it took.
// Called from the scan's own background task: the sound matching reads up to 6 MB of bytes.
import Foundation
import PodcastAds
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
    return local + sounds
  }
}
