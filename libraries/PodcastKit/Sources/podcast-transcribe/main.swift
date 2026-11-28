// LOFI-FORK: transcribes one audio file on a Mac with the same code the app uses (see FORK.md).
//
//   swift run -c release podcast-transcribe [--locale en-US] [--words <file>] <audio file>
//
// Prints each line with its time ("[00:01:23.4] text") to the standard output and progress
// to the standard error. With --words it also saves where each word and each line starts and
// ends, in seconds, to that file (see WordTimes), so a line's end is the end of its last word. Needs macOS 26. Where there is no Speech framework (Linux) it only
// says so, so `swift build` and `swift test` still work there. Progress is kept in
// the temporary folder, so a run that was stopped carries on where it was.
import Foundation
import PodcastDownloads
import PodcastSpeech
import PodcastTranscripts

func clock(_ seconds: Double) -> String {
  let total = Int(seconds)
  let tenths = Int((seconds - Double(total)) * 10)
  return String(format: "%02d:%02d:%02d.%d", total / 3600, total / 60 % 60, total % 60, tenths)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var locale = Locale.current.identifier(.bcp47)
if let at = arguments.firstIndex(of: "--locale") {
  guard arguments.indices.contains(at + 1) else { fail("--locale needs a language, such as en-US") }
  locale = arguments[at + 1]
  arguments.removeSubrange(at...at + 1)
}
var wordsFile: URL?
if let at = arguments.firstIndex(of: "--words") {
  guard arguments.indices.contains(at + 1) else { fail("--words needs a file name") }
  wordsFile = URL(fileURLWithPath: arguments[at + 1])
  arguments.removeSubrange(at...at + 1)
}
guard arguments.count == 1 else {
  fail("Usage: podcast-transcribe [--locale en-US] [--words <file>] <audio file>")
}
let audio = URL(fileURLWithPath: arguments[0])
guard FileManager.default.fileExists(atPath: audio.path) else { fail("No file at \(audio.path)") }
guard let recogniser = AppleSpeech.makeRecogniser() else { fail("Needs macOS 26 (and Xcode 26 to build).") }

do {
  let sha = try FileHash.sha256(of: audio)
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "podcast-transcribe/\(sha)", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let outcome = try await TranscriptRunner.run(
    audio: audio, sha256: sha, locale: locale, recogniser: recogniser,
    store: TranscriptStore(folder: folder, sha256: sha),
    progress: { FileHandle.standardError.write(Data("\($0)%\n".utf8)) })
  guard case .finished(let transcript) = outcome else { fail("Stopped before the end.") }
  for line in transcript.lines { print("[\(clock(line.start))] \(line.text)") }
  if let wordsFile { try WordTimes(transcript).write(to: wordsFile) }
  try? FileManager.default.removeItem(at: folder)
} catch {
  fail("Could not transcribe: \(error)")
}
