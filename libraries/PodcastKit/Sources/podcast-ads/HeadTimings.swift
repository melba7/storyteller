// LOFI-FORK: `podcast-ads --head N --timings <audio file>`: times the first N seconds of an
// episode through the same speech and ad code the phone uses (see FORK.md).
import Foundation
import PodcastAds
import PodcastDownloads
import PodcastTranscripts

enum HeadTimings {
  /// How much audio the "first words" step reads: the most the first words could need.
  static let firstWordsSeconds = 15.0

  /// Runs the steps twice in this process: the first run is cold, the second warm.
  static func run(
    audio: URL, head: Double, locale requested: String, recogniser: PieceRecogniser,
    detector: AdDetector, work: URL
  ) async throws {
    let duration = try recogniser.duration(of: audio)
    let headSeconds = min(head, duration)
    print("File: \(audio.lastPathComponent), \(span(duration)) long. Head checked: the first \(Int(headSeconds)) s.")
    let sha = try FileHash.sha256(of: audio)
    for run in ["Run 1 (cold)", "Run 2 (warm, same process)"] {
      print("")
      print(run)
      let t0 = ProcessInfo.processInfo.systemUptime
      func since() -> Double { ProcessInfo.processInfo.systemUptime - t0 }

      let locale = try await recogniser.prepare(locale: requested)
      print("  speech model ready:        \(String(format: "%6.2f", since())) s")

      let before = since()
      let first = try await recogniser.recognise(
        file: audio, locale: locale, from: 0, to: min(firstWordsSeconds, headSeconds))
      let words = first.prefix(8).map(\.text).joined(separator: " ")
      print("  first words:               \(String(format: "%6.2f", since())) s  (read the first \(Int(firstWordsSeconds)) s in \(String(format: "%.2f", since() - before)) s: \"\(words)\")")

      let heard = try await recogniser.recognise(file: audio, locale: locale, from: 0, to: headSeconds)
      print("  head transcript done:      \(String(format: "%6.2f", since())) s  (\(heard.count) words)")

      let identity = TranscriptIdentity(
        locale: locale, recogniser: recogniser.name, recogniserVersion: recogniser.version,
        osVersion: recogniser.osVersion, sha256: sha)
      let store = AdsStore(folder: work.appendingPathComponent(UUID().uuidString), sha256: sha)
      try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
      let asked = since()
      let outcome = try await AdsRunner.runPartial(
        partial: PartialTranscript(
          identity: identity, duration: duration, reached: headSeconds, words: heard),
        detector: detector, store: store, osVersion: recogniser.osVersion)
      switch outcome {
      case .finished(let file):
        print("  model's first answer:      \(String(format: "%6.2f", since())) s  (the model took \(String(format: "%.2f", since() - asked)) s; \(file.ads.count) ad(s) found)")
        for ad in file.ads {
          print("    [\(clock(ad.start)) - \(clock(ad.end))] \(ad.confidence.rawValue): \(ad.firstWords)")
        }
      default:
        print("  model's first answer:      none (the head was too short for a piece, or it stopped)")
      }
    }
    print("")
    print("All times are seconds from the start of that run. The first answer needs the whole head")
    print("transcript, so the last line is how long a stream's first \(Int(headSeconds)) s take to check on this Mac.")
    print("A phone is slower than a Mac: read these as the best case.")
  }
}
