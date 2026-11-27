// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The maybes of an episode (`AdMaybes` in PodcastAds), set by the whole-transcript pass after its
// questions. A maybe is a stretch that a tap on skip forward may confirm: what the finders only
// asked about and did not get a question for, and the weak spans of the word model. They are
// never shown. Each pass replaces the open maybes of the file; a confirmed one is kept.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
  /// Puts the maybes into `file` (the file after the questions were added) and returns how many
  /// open ones it holds. The word model's weak spans run under its mark, as its questions do, and
  /// only while it is on and a word model is loaded. `picked` are the questions just added.
  func settingMaybes(
    _ id: String, _ modes: NewModes, _ transcript: Transcript, _ collect: NewCollect,
    picked: [FoundAd], in file: inout AdsFile
  ) -> Int {
    var spans: [FoundAd] = []
    if modes.level(FinderNames.wordModel) != .off, let model = PodcastTeaching.shared.files.model {
      let outside = file.ads + (file.asks ?? [])
      spans =
        PodcastFinderGuard.shared.hold([FinderNames.wordModel], episode: id) { _ in
          AdMaybes.weak(
            model: model, lines: AdChunker.number(transcript.lines),
            duration: transcript.duration, outside: outside, source: FinderNames.wordModel)
        } ?? []
    }
    let found = collect.maybes(besides: picked, spans: spans)
    file = AdMaybes.setting(found, in: file)
    return AdMaybes.open(in: file).count
  }
}
