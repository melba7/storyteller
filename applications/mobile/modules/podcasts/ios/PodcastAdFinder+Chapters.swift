// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder and the file's own chapters: a chapter named like an ad break, with words that
// sell inside it, is an ad of the final ads file (ChapterAds). It runs in the finder's own
// background task, never on the main thread.
import Foundation
import PodcastAds
import PodcastChapters
import PodcastTranscripts

extension PodcastAdFinder {
  /// The final ads file with what the downloaded file's chapters add and cut, saved when it
  /// changed. The file as it was when the episode has no chapters, no download or no change.
  func withChapterAds(
    _ id: String, ads: AdsStore, finished file: AdsFile, transcript: Transcript
  ) async -> AdsFile {
    guard let local = PodcastDownloader.shared.localFile(for: id) else { return file }
    let marks = await PodcastChapterSource.fromFile(local).map {
      ChapterAds.Mark(start: $0.start, end: $0.end, title: $0.title)
    }
    guard !marks.isEmpty else { return file }
    // The saved file also holds the skips the listener took back or trimmed meanwhile.
    var saved = ads.load(detector: Self.detectorName) ?? file
    let merged = ChapterAds.apply(
      marks, to: saved.ads, transcript: transcript, episodeDuration: transcript.duration)
    guard merged != saved.ads else { return saved }
    saved.ads = merged
    try? ads.save(saved)
    return saved
  }
}
