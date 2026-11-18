// LOFI-FORK: `podcast-ads --head N --timings <MP3 file>`: runs the first N seconds of an episode
// down the path a stream takes on the phone and times each step (see FORK.md).
//
// That path is what PodcastStreamHead does: one head transcriber made ready ahead, the start of
// the file cut with Mp3Prefix at a whole frame in steps (15, 30, 60 seconds, then every 30),
// `extend` for each step, the text rules (AdHeadRules) after each step, and the model at the 30,
// 60, 120 and 180 second steps (each with a session warmed after the last answer; only its sure
// answers count at the 30 second step). The file is whole here, so the cut is taken from its
// first bytes as if only those had arrived.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastSpeech
import PodcastTranscripts

enum HeadTimings {
  /// The most bytes a second of audio can take (320 kbit/s), to read enough for a step.
  static let mostBytesPerSecond = 40_000

  /// Runs the steps twice in this process: the first run is cold, the second warm.
  static func run(
    audio: URL, head: Double, locale requested: String, recogniser: PieceRecogniser, work: URL
  ) async throws {
    let duration = try recogniser.duration(of: audio)
    let headSeconds = min(head, duration)
    let steps = AdHeadRules.steps(upTo: headSeconds)
    print("File: \(audio.lastPathComponent), \(span(duration)) long. Head checked: the first \(Int(headSeconds)) s, in steps of \(steps.map { String(Int($0)) }.joined(separator: ", ")) s.")
    // Makes sure the speech model is on this Mac (the phone's scan never downloads it).
    let locale = try await recogniser.prepare(locale: requested)
    for run in ["Run 1 (cold)", "Run 2 (warm, same process)"] {
      print("")
      print(run)
      let t0 = ProcessInfo.processInfo.systemUptime
      func since() -> Double { ProcessInfo.processInfo.systemUptime - t0 }
      func line(_ label: String, _ detail: String) {
        print("  \(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(String(format: "%6.2f", since())) s  \(detail)")
      }

      guard let speech = AppleSpeech.makeHeadTranscriber(locale: locale) else {
        throw HeadError("This Mac has no speech recogniser for the head scan (needs macOS 26).")
      }
      var warm = AppleAds.makeWarmDetector()
      warm?.prewarm()
      try await speech.prepare()
      line("speech ready:", "")
      var fed = 0.0
      var modelAds: [FoundAd] = []
      var final: [FoundAd] = []
      do {
        for target in steps {
          let cut = try cutOfFile(audio, seconds: target, work: work)
          let began = since()
          let words = try await speech.extend(file: cut.file, from: fed, to: cut.seconds)
          fed = cut.seconds
          line("transcript to \(Int(target)) s:", "\(words.count) words, the step took \(String(format: "%.2f", since() - began)) s (audio fed \(String(format: "%.1f", cut.seconds)) s)")

          let lines = LineRule.lines(from: words)
          let transcript = Transcript(
            identity: TranscriptIdentity(
              locale: locale, recogniser: recogniser.name, recogniserVersion: recogniser.version,
              osVersion: recogniser.osVersion, sha256: ""),
            duration: fed, lines: lines, words: words)
          let ruleStart = since()
          let ruleAds = AdCleanup.run(
            ranges: AdHeadRules.find(lines: AdChunker.number(lines)), transcript: transcript)
          line("rules at \(Int(target)) s:", "\(ruleAds.count) ad(s) in \(String(format: "%.0f", (since() - ruleStart) * 1000)) ms")
          final = AdHeadRules.merge(ruleAds + modelAds)

          if AdHeadRules.modelSteps.contains(target) {
            // A warm session is used once, as on the phone; the next model step gets one made now.
            let model: AdDetector? = warm ?? AppleAds.makeDetector()
            warm = nil
            guard let model else { throw HeadError("This Mac has no on-device model.") }
            let asked = since()
            do {
              let answer = try await model.findAds(in: TranscriptPiece(lines: AdChunker.number(lines)))
              modelAds = AdCleanup.run(
                ranges: AdHeadRules.counted(answer, atStep: target), transcript: transcript)
              line("model at \(Int(target)) s:", "\(modelAds.count) ad(s), the model took \(String(format: "%.2f", since() - asked)) s")
            } catch {
              line("model at \(Int(target)) s:", "no answer (\(error))")
            }
            if steps.contains(where: { $0 > target && AdHeadRules.modelSteps.contains($0) }) {
              warm = AppleAds.makeWarmDetector()
              warm?.prewarm()
            }
            final = AdHeadRules.merge(ruleAds + modelAds)
          }
        }
      } catch {
        await speech.finish()
        throw error
      }
      await speech.finish()
      if final.isEmpty { print("  no ads in the head") }
      for ad in final {
        print("    [\(clock(ad.start)) - \(clock(ad.end))] \(ad.confidence.rawValue): \(ad.firstWords)")
      }
    }
    print("")
    print("All times are seconds from the start of that run. This is the phone's stream path (head")
    print("transcriber, MP3 cuts, text rules after each step, the model at 30, 60, 120 and 180 s), so a")
    print("stall or an error here is one the phone would meet too. A phone is slower than a Mac:")
    print("read these as the best case.")
  }

  struct HeadError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  /// The first `seconds` of the file as a small MP3 file cut at a whole frame, made from the
  /// file's first bytes only (as the stream's head scan does).
  static func cutOfFile(_ audio: URL, seconds: Double, work: URL) throws -> (file: URL, seconds: Double) {
    let handle = try FileHandle(forReadingFrom: audio)
    defer { try? handle.close() }
    let first = try handle.read(upToCount: 10) ?? Data()
    guard let start = Mp3Prefix.audioStart(first) else { throw HeadError("The file's tag cannot be read.") }
    try handle.seek(toOffset: 0)
    let want = start + Int(seconds) * mostBytesPerSecond + Mp3Prefix.searchWindow
    let data = try handle.read(upToCount: want) ?? Data()
    let whole = data.count < want  // the file ends inside what was read
    switch Mp3Prefix.look(data, complete: whole, maxSeconds: seconds) {
    case .cut(let cut):
      let file = work.appendingPathComponent("head-\(Int(seconds)).mp3")
      try data.prefix(cut.bytes).write(to: file)
      return (file, cut.seconds)
    case .needMore:
      throw HeadError("The start of the file has no whole MP3 frame (is it an MP3 file?).")
    case .notMp3:
      throw HeadError("--head follows the phone's stream path, which handles MP3 only; this file is not an MP3.")
    }
  }
}
