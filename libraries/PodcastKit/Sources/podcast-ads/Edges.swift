// LOFI-FORK: `podcast-ads --edges [--truth <file>] <transcript or audio>`: says what each step did
// to the edges of the ads found in an episode, and how exact the player's seeks are (see FORK.md).
//
// The trace comes from AdCleanup.explain on the answers the model gave for each piece, so it is
// what the app does. With an MP3 file it also checks the file's frames for the kind of bitrate
// that makes Apple's player seek to the wrong place (PodcastAudioMatch.SeekDrift), and compares
// the duration the player is given (the app does not set the precise-timing option) with the
// decoded one. The transcript's word times are described too, and that part needs no model, so
// it works for a transcript file where there is no Apple Intelligence.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastAudioMatch
import PodcastDownloads
import PodcastSpeech
import PodcastTranscripts

#if canImport(AVFoundation)
  import AVFoundation
#endif

/// Passes each question to a detector and keeps every answer, so the clean-up can be explained
/// from the same answers the runner used.
final class RecordingDetector: AdDetector, @unchecked Sendable {
  private let base: AdDetector
  private let lock = NSLock()
  private var kept: [AdRange] = []

  init(_ base: AdDetector) { self.base = base }

  var name: String { base.name }
  var version: String { base.version }
  var tokenBudget: Int { base.tokenBudget }

  /// The answers so far, in the order the runner took them.
  var ranges: [AdRange] {
    lock.lock()
    defer { lock.unlock() }
    return kept
  }

  func findAds(in piece: TranscriptPiece) async throws -> [AdRange] {
    let answer = try await base.findAds(in: piece)
    keep(answer)
    return answer
  }

  private func keep(_ answer: [AdRange]) {
    lock.lock()
    kept += answer
    lock.unlock()
  }
}

enum Edges {
  /// Prints the report and answers the exit code.
  static func run(input: URL, truthFile: URL?, locale: String) async -> Int32 {
    var truth: [TruthAd] = []
    if let truthFile {
      do {
        truth = try AdTruth.parse(String(contentsOf: truthFile, encoding: .utf8))
      } catch {
        say("Could not read the marked ads: \(error)")
        return 1
      }
    }
    let work = FileManager.default.temporaryDirectory.appendingPathComponent(
      "podcast-ads/\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let isAudio = !input.lastPathComponent.hasSuffix(".transcript.json")
    do {
      try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
      var recogniser: PieceRecogniser?
      let transcript: Transcript
      if isAudio {
        guard let made = AppleSpeech.makeRecogniser() else {
          say("Needs macOS 26 to transcribe.")
          return 1
        }
        recogniser = made
        let sha = try FileHash.sha256(of: input)
        let outcome = try await TranscriptRunner.run(
          audio: input, sha256: sha, locale: locale, recogniser: made,
          store: TranscriptStore(folder: work, sha256: sha),
          progress: { say("Transcribing \($0)%") })
        guard case .finished(let finished) = outcome else {
          say("Stopped before the end.")
          return 1
        }
        transcript = finished
      } else {
        transcript = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: input))
      }

      var code: Int32 = 0
      if let detector = AppleAds.makeDetector(), AppleAds.unavailable() == nil {
        let found = try await trace(transcript, detector: detector, work: work)
        if !truth.isEmpty {
          print("")
          AdEdgeReport.lines(for: AdTruth.compare(found: found, truth: truth)).forEach { print($0) }
        }
      } else {
        say("The trace of the ads needs macOS 26 with Apple Intelligence on, so it is left out.")
        code = 1
      }
      print("")
      AdEdgeReport.lines(for: AdEdgeReport.stats(of: transcript)).forEach { print($0) }
      if isAudio { try await seeks(input, recogniser: recogniser) }
      return code
    } catch AdDetectorError.unavailable(let reason) {
      say("Cannot find ads now: \(reason.reason).")
    } catch {
      say("Could not check the edges: \(error)")
    }
    return 1
  }

  /// Asks the model about the whole transcript, prints what the clean-up did to each ad's edges
  /// and answers the ads.
  private static func trace(
    _ transcript: Transcript, detector: AdDetector, work: URL
  ) async throws -> [FoundAd] {
    let recording = RecordingDetector(detector)
    let store = AdsStore(folder: work, sha256: transcript.identity.sha256)
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: recording, store: store,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      progress: { done, total in say("Finding ads: piece \(done) of \(total)") })
    guard case .finished = outcome else { throw AdDetectorError.failed("Stopped before the end.") }
    let traces = AdCleanup.explain(ranges: recording.ranges, transcript: transcript)
    if traces.isEmpty { print("No ads found.") }
    for (index, one) in traces.enumerated() {
      AdEdgeReport.lines(for: one, number: index + 1, transcript: transcript).forEach { print($0) }
      print("")
    }
    return traces.map(\.ad)
  }

  /// The seek lines for an audio file: what its MP3 frames say, and the durations.
  private static func seeks(_ audio: URL, recogniser: PieceRecogniser?) async throws {
    print("")
    let data = try Data(contentsOf: audio, options: .mappedIfSafe)
    let parse = MP3Frames.parse([UInt8](data))
    guard !parse.frames.isEmpty else {
      print("Seeking: this is not an MP3 file, so the check of its frames is left out.")
      return
    }
    seekLines(SeekDrift.report(parse), parse: parse).forEach { print($0) }
    #if canImport(AVFoundation)
      let decoded = try recogniser?.duration(of: audio)
      let reported = try? await AVURLAsset(url: audio).load(.duration).seconds
      if let reported, let decoded {
        let gap = reported - decoded
        print(
          String(
            format: "  Duration the player is given: %.1f s. Decoded: %.1f s. Off by %+.1f s.",
            reported, decoded, gap))
      }
    #endif
  }

  private static func seekLines(_ report: SeekDriftReport, parse: MP3Parse) -> [String] {
    let frames = parse.frames.count
    let seconds = parse.seconds
    var text = ["Seeking: the file has \(frames) MP3 frames, \(AdEdgeReport.clock(seconds)) long."]
    let byBitrate = report.framesPerBitrate.sorted { $0.key < $1.key }.map { entry in
      let share = String(format: "%.1f %%", Double(entry.value) / Double(frames) * 100)
      return "\(entry.key / 1000) kbps: \(entry.value) (\(share))"
    }
    text.append("  Frames by bitrate: " + byBitrate.joined(separator: ", ") + ".")
    text.append(
      report.steady
        ? "  The bitrate is steady, so the player's seeks land where they should."
        : "  The bitrate is not steady, so the player can seek to the wrong place in this file.")
    text.append(
      String(format: "  Worst seek error from the ratio guess: %.1f s.", report.worstSeconds))
    if report.seams.isEmpty {
      text.append("  No change of encoding inside the file.")
    } else {
      text.append("  Where the encoding changes (often where an ad was spliced in):")
      for seam in report.seams.prefix(20) {
        text.append("    \(AdEdgeReport.clock(seam.time)): \(seam.reason)")
      }
      if report.seams.count > 20 { text.append("    and \(report.seams.count - 20) more.") }
    }
    if report.reservoirResets.isEmpty {
      text.append("  No reservoir resets.")
    } else {
      text.append(
        "  Reservoir resets (a frame that needs nothing from the frames before it, after \(SeekDrift.resetAfter) that did; a spot encoded on its own starts so): \(report.reservoirResets.count)."
      )
      for index in report.reservoirResets.prefix(20) {
        text.append("    \(AdEdgeReport.clock(parse.frames[index].start))")
      }
      if report.reservoirResets.count > 20 {
        text.append("    and \(report.reservoirResets.count - 20) more.")
      }
    }
    return text
  }
}
