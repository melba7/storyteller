// LOFI-FORK: finds the ads in one episode on a Mac with the same code the app uses (see FORK.md).
//
//   swift run -c release podcast-ads [--locale en-US] <episode.transcript.json | audio file>
//   swift run -c release podcast-ads --play [--locale en-US] <audio file>
//   swift run -c release podcast-ads --head 90 --timings [--locale en-US] <audio file>
//   swift run -c release podcast-ads --edges [--truth <file>] [--locale en-US] <transcript or audio>
//   swift run -c release podcast-ads --probe <episode address>
//   swift run -c release podcast-ads --shared <episode.mp3> <another episode of the show.mp3>
//   swift run -c release podcast-ads --truth-from-copies <download.mp3> <second download.mp3>
//
// Prints each ad with its times, kind, advertiser, how sure the model is and its first words,
// to the standard output, and progress to the standard error. An audio file is transcribed
// first (as podcast-transcribe does). With --play it does what the phone does for an episode
// that is playing (a transcript piece, then a partial ad pass, and so on), times each step, and
// says for each ad whether a listener who pressed play at 0:00 would have had it skipped. With
// --head N --timings (an MP3 file) it runs the first N seconds down the path a stream takes
// on the phone (the head transcriber, cuts of the file's first bytes, the text rules after each
// step of 15, 30, 60 s and so on, the model at 30, 60, 120 and 180 s), twice in one process
// (cold, then warm), and prints the time of each step. With --edges it prints, for each ad,
// what the model said and what each clean-up step did to the ends, the lines around each edge,
// what the transcript's word times look like and, for an MP3 file, how exact the player's
// seeks are (Edges.swift); with --truth (a file of hand-marked ads, one "12:30 13:45" to a
// line) it also compares the two. With --probe it downloads the first 3 MB of an episode
// address twice as two different listeners and prints where the two copies differ (no speech
// or model needed). With --shared (two MP3 files, two different episodes of one show) it prints
// the stretches that are byte for byte the same in both, and whether a reset of the bit
// reservoir or a change of encoding sits at each edge (Shared.swift). With --truth-from-copies
// (two MP3 files, two downloads of one episode) it writes the stretches where the first differs
// from the second as "<first file>.truth.txt", a file of marked ads for --edges --truth. These
// two need no speech or model either. Needs macOS 26 with Apple Intelligence on, except for
// --probe, --shared and --truth-from-copies. Where there is no Foundation Models framework
// (Linux) it only says so, so `swift build` and `swift test` still work there.
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

/// "12.3 s", or "2 min 5 s" from a minute on.
func span(_ seconds: Double) -> String {
  guard seconds >= 60 else { return String(format: "%.1f s", seconds) }
  return "\(Int(seconds) / 60) min \(Int(seconds) % 60) s"
}

/// One line for each ad that the player would skip, then the times.
func printPlay(_ result: PlayCheckResult) {
  if result.verdicts.isEmpty { print("No ads found.") }
  for verdict in result.verdicts {
    let ad = verdict.ad
    let kind = ad.kind.label
    let who = ad.advertiser.isEmpty ? "" : " \(ad.advertiser)"
    let outcome =
      verdict.skipped
      ? "SKIPPED, known \(span(verdict.lead)) before the playhead got there"
      : "NOT SKIPPED, known \(span(-verdict.lead)) after the playhead passed"
    print(
      "[\(clock(ad.start)) - \(clock(ad.end))] \(kind), \(ad.confidence.rawValue)\(who): known after \(span(verdict.knownAt)) of work; playhead there at \(span(verdict.reachedAt)); \(outcome)"
    )
  }
  let skipped = result.verdicts.filter(\.skipped).count
  print("")
  print("\(skipped) of \(result.verdicts.count) ads would have been skipped (played from 0:00 at 1x).")
  print("Transcribing: \(span(result.transcribeSeconds)). Model: \(span(result.modelSeconds)). In all: \(span(result.totalSeconds)).")
  print(
    "The episode is \(span(result.duration)) long: \(String(format: "%.1f", result.speed)) times real time (above 1 keeps ahead of a listener)."
  )
  if result.refusedPieces > 0 {
    print("The model refused \(result.refusedPieces) piece(s); they count as having no ads.")
  }
}

var arguments = Array(CommandLine.arguments.dropFirst())
var locale = Locale.current.identifier(.bcp47)
if let at = arguments.firstIndex(of: "--locale") {
  guard arguments.indices.contains(at + 1) else { fail("--locale needs a language, such as en-US") }
  locale = arguments[at + 1]
  arguments.removeSubrange(at...at + 1)
}
if let at = arguments.firstIndex(of: "--probe") {
  guard arguments.count == 2, arguments.indices.contains(at + 1) else {
    fail("Usage: podcast-ads --probe <episode address>")
  }
  exit(Probe.run(arguments[at + 1]))
}
for flag in ["--shared", "--truth-from-copies"] {
  guard let at = arguments.firstIndex(of: flag) else { continue }
  arguments.remove(at: at)
  guard arguments.count == 2 else { fail("Usage: podcast-ads \(flag) <first file.mp3> <second file.mp3>") }
  let files = arguments.map { URL(fileURLWithPath: $0) }
  for file in files where !FileManager.default.fileExists(atPath: file.path) {
    fail("No file at \(file.path)")
  }
  exit(flag == "--shared" ? Shared.run(files[0], files[1]) : Shared.truthFromCopies(files[0], files[1]))
}
var headSeconds: Double?
if let at = arguments.firstIndex(of: "--head") {
  guard arguments.indices.contains(at + 1), let seconds = Double(arguments[at + 1]), seconds >= 10 else {
    fail("--head needs a number of seconds, at least 10, such as --head 90")
  }
  headSeconds = seconds
  arguments.removeSubrange(at...at + 1)
}
var timings = false
if let at = arguments.firstIndex(of: "--timings") {
  timings = true
  arguments.remove(at: at)
}
var play = false
if let at = arguments.firstIndex(of: "--play") {
  play = true
  arguments.remove(at: at)
}
var edges = false
if let at = arguments.firstIndex(of: "--edges") {
  edges = true
  arguments.remove(at: at)
}
var truthFile: URL?
if let at = arguments.firstIndex(of: "--truth") {
  guard arguments.indices.contains(at + 1) else { fail("--truth needs a file of marked ads") }
  truthFile = URL(fileURLWithPath: arguments[at + 1])
  arguments.removeSubrange(at...at + 1)
}
guard arguments.count == 1 else {
  fail(
    "Usage: podcast-ads [--play | --head 90 --timings | --edges [--truth <file>]] [--locale en-US] <episode.transcript.json or audio file>\n       podcast-ads --probe <episode address>\n       podcast-ads --shared | --truth-from-copies <first file.mp3> <second file.mp3>"
  )
}
let input = URL(fileURLWithPath: arguments[0])
guard FileManager.default.fileExists(atPath: input.path) else { fail("No file at \(input.path)") }
if truthFile != nil, !edges { fail("--truth is used with --edges.") }
if let truthFile, !FileManager.default.fileExists(atPath: truthFile.path) {
  fail("No file at \(truthFile.path)")
}
if edges {
  // The transcript's own numbers need no model, so this runs before the model is looked for.
  exit(await Edges.run(input: input, truthFile: truthFile, locale: locale))
}
guard let detector = AppleAds.makeDetector() else { fail("Needs macOS 26 (and Xcode 26 to build).") }
if let reason = AppleAds.unavailable() { fail("Cannot find ads now: \(reason.reason).") }

let work = FileManager.default.temporaryDirectory.appendingPathComponent(
  "podcast-ads/\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: work) }

do {
  try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
  if let head = headSeconds {
    guard timings else { fail("--head is used with --timings.") }
    guard !input.lastPathComponent.hasSuffix(".transcript.json") else {
      fail("--head needs an audio file.")
    }
    guard let recogniser = AppleSpeech.makeRecogniser() else { fail("Needs macOS 26 to transcribe.") }
    try await HeadTimings.run(
      audio: input, head: head, locale: locale, recogniser: recogniser, work: work)
    exit(0)
  }
  if play {
    guard !input.lastPathComponent.hasSuffix(".transcript.json") else {
      fail("--play needs an audio file, because it times the transcribing too.")
    }
    guard let recogniser = AppleSpeech.makeRecogniser() else { fail("Needs macOS 26 to transcribe.") }
    let sha = try FileHash.sha256(of: input)
    let result = try await PlayCheck.run(
      audio: input, sha256: sha, locale: locale, recogniser: recogniser, detector: detector,
      store: AdsStore(folder: work, sha256: sha), now: { ProcessInfo.processInfo.systemUptime },
      progress: { say($0) })
    printPlay(result)
    exit(0)
  }
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
    let kind = ad.kind.label
    let who = ad.advertiser.isEmpty ? "" : " \(ad.advertiser)"
    print(
      "[\(clock(ad.start)) - \(clock(ad.end))] \(Int(ad.duration.rounded())) s, \(kind), \(ad.confidence.rawValue)\(who): \(ad.firstWords)"
    )
  }
  let sure = file.ads.filter { $0.confidence == .sure }.count
  say("\(file.ads.count) found, \(sure) sure. The player skips sure and unsure ads alike, with Undo.")
} catch AdDetectorError.unavailable(let reason) {
  fail("Cannot find ads now: \(reason.reason).")
} catch {
  fail("Could not find ads: \(error)")
}
