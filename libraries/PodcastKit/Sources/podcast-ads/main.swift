// LOFI-FORK: finds the ads in one episode on a Mac with the same code the app uses (see FORK.md).
//
//   swift run -c release podcast-ads [--locale en-US] <episode.transcript.json | audio file>
//
// Prints each ad with its times, kind, advertiser, how sure the model is and its first words,
// to the standard output, and progress to the standard error. An audio file is transcribed
// first (as podcast-transcribe does). Needs macOS 26 with Apple Intelligence on. Where there
// is no Foundation Models framework (Linux) it only says so, so `swift build` and `swift test`
// still work there.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastDownloads
import PodcastSpeech
import PodcastTranscripts

func clock(_ seconds: Double) -> String {
  let total = Int(seconds)
  let tenths = Int((seconds - Double(total)) * 10)
  return String(format: "%02d:%02d:%02d.%d", total / 3600, total / 60 % 60, total % 60, tenths)
}

func say(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

func fail(_ message: String) -> Never {
  say(message)
  exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var locale = Locale.current.identifier(.bcp47)
if let at = arguments.firstIndex(of: "--locale") {
  guard arguments.indices.contains(at + 1) else { fail("--locale needs a language, such as en-US") }
  locale = arguments[at + 1]
  arguments.removeSubrange(at...at + 1)
}
guard arguments.count == 1 else {
  fail("Usage: podcast-ads [--locale en-US] <episode.transcript.json or audio file>")
}
let input = URL(fileURLWithPath: arguments[0])
guard FileManager.default.fileExists(atPath: input.path) else { fail("No file at \(input.path)") }
guard let detector = AppleAds.makeDetector() else { fail("Needs macOS 26 (and Xcode 26 to build).") }
if let reason = AppleAds.unavailable() { fail("Cannot find ads now: \(reason.reason).") }

let work = FileManager.default.temporaryDirectory.appendingPathComponent(
  "podcast-ads/\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: work) }

do {
  try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
  let transcript: Transcript
  if input.lastPathComponent.hasSuffix(".transcript.json") {
    transcript = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: input))
  } else {
    guard let recogniser = AppleSpeech.makeRecogniser() else { fail("Needs macOS 26 to transcribe.") }
    let sha = try FileHash.sha256(of: input)
    let outcome = try await TranscriptRunner.run(
      audio: input, sha256: sha, locale: locale, recogniser: recogniser,
      store: TranscriptStore(folder: work, sha256: sha),
      progress: { say("Transcribing \($0)%") })
    guard case .finished(let finished) = outcome else { fail("Stopped before the end.") }
    transcript = finished
  }

  let store = AdsStore(folder: work, sha256: transcript.identity.sha256)
  let outcome = try await AdsRunner.run(
    transcript: transcript, detector: detector, store: store,
    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
    progress: { done, total in say("Finding ads: piece \(done) of \(total)") })
  guard case .finished(let file) = outcome else { fail("Stopped before the end.") }

  if file.ads.isEmpty { print("No ads found.") }
  for ad in file.ads {
    let kind = ad.kind == .ad ? "ad" : "own plug"
    let who = ad.advertiser.isEmpty ? "" : " \(ad.advertiser)"
    print(
      "[\(clock(ad.start)) - \(clock(ad.end))] \(Int(ad.duration.rounded())) s, \(kind), \(ad.confidence.rawValue)\(who): \(ad.firstWords)"
    )
  }
  let sure = file.ads.filter { $0.confidence == .sure }.count
  say("\(file.ads.count) found, \(sure) sure (those are the ones the player skips).")
} catch AdDetectorError.unavailable(let reason) {
  fail("Cannot find ads now: \(reason.reason).")
} catch {
  fail("Could not find ads: \(error)")
}
