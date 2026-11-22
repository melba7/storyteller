// LOFI-FORK: the local finders on a transcript that is still being made (see FORK.md).
import Foundation
import PodcastTranscripts

extension LocalAds {
  /// The ads in the words of a partial transcript, cut into lines as the detector's pieces are.
  /// With `limit`, only the words that end within that many seconds are looked at (the head of an
  /// episode that is not playing). The episode's whole length is passed on, as it is known.
  public func ads(
    partial: PartialTranscript, limit: Double? = nil, sponsors: [SponsorName] = []
  ) -> [FoundAd] {
    let words = limit.map { limit in partial.words.filter { $0.end <= limit } } ?? partial.words
    let lines = LineRule.lines(from: words)
    guard !lines.isEmpty else { return [] }
    let transcript = Transcript(
      identity: partial.identity, duration: partial.duration, lines: lines, words: words)
    return ads(transcript: transcript, sponsors: sponsors, episodeDuration: partial.duration)
  }
}
