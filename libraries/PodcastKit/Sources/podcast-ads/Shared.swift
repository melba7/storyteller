// LOFI-FORK: `podcast-ads --shared <a.mp3> <b.mp3>` and `--truth-from-copies <a.mp3> <b.mp3>`
// (see FORK.md). Both read two MP3 files, cut them into frames and compare the frames' bytes.
// They need no speech, no model and no network.
//
// --shared takes two different episodes of one show and says which stretches are byte for byte the
// same in both (a spot that the host stitched in as it was) and what the bytes look like at each
// edge of such a stretch. --truth-from-copies takes two downloads of one episode and writes the
// stretches where they differ as a file of marked ads, the kind `--edges --truth` reads.
import Foundation
import PodcastAudioMatch

/// One of the two files: its frames and what the frames say about the encoding.
private struct Side {
  var title: String
  var file: URL
  var parse: MP3Parse
  var report: SeekDriftReport

  var seconds: Double { parse.seconds }

  func evidence(at frame: Int) -> EdgeEvidence {
    SharedRuns.evidence(at: frame, in: parse, report: report)
  }

  /// "0:07.8 to 0:37.8 (frames 300 to 1449)".
  func times(_ range: Range<Int>) -> String {
    let first = parse.frames[range.lowerBound]
    let last = parse.frames[range.upperBound - 1]
    return "\(Probe.seconds(first.start)) to \(Probe.seconds(last.start + last.duration))"
      + " (frames \(range.lowerBound) to \(range.upperBound - 1))"
  }

  func length(_ range: Range<Int>) -> Double {
    parse.frames[range].reduce(0) { $0 + $1.duration }
  }

  /// Whether a reset or a change of encoding sits at both ends of the run.
  func marksBothEnds(_ range: Range<Int>) -> Bool {
    evidence(at: range.lowerBound).any && evidence(at: range.upperBound).any
  }
}

enum Shared {
  /// The bytes of each file, or nil (with a message) when one cannot be read or both are one file.
  private static func read(_ files: [URL]) -> [[UInt8]]? {
    var all: [[UInt8]] = []
    for file in files {
      do {
        all.append([UInt8](try Data(contentsOf: file, options: .mappedIfSafe)))
      } catch {
        say("Could not read \(file.path): \(error.localizedDescription)")
        return nil
      }
    }
    if all[0] == all[1] {
      say("These are the same file twice. Choose two different files.")
      return nil
    }
    return all
  }

  private static func parse(_ files: [URL]) -> [MP3Parse]? {
    guard let bytes = read(files) else { return nil }
    let parses = bytes.map { MP3Frames.parse($0) }
    for (file, parse) in zip(files, parses) where parse.frames.isEmpty {
      say("No MP3 frames in \(file.lastPathComponent) (not an MP3 file, or a web page was saved).")
      return nil
    }
    return parses
  }

  // MARK: --shared

  static func run(_ first: URL, _ second: URL) -> Int32 {
    guard let parses = parse([first, second]) else { return 1 }
    let sides = [
      Side(title: "First", file: first, parse: parses[0], report: SeekDrift.report(parses[0])),
      Side(title: "Second", file: second, parse: parses[1], report: SeekDrift.report(parses[1])),
    ]
    let runs = SharedRuns.find(parses[0], parses[1])
    print("Frames that are the same bytes in two episodes")
    print("")
    for side in sides {
      print("\(side.title) episode: \(side.file.lastPathComponent)")
      print("  \(describe(side))")
    }
    print("")
    if runs.isEmpty {
      print("No stretch of 3 s or more is the same bytes in both episodes.")
    } else {
      print("Stretches of 3 s or more that are the same bytes in both episodes (\(runs.count)):")
    }
    for (number, run) in runs.enumerated() {
      print("")
      print("Run \(number + 1): \(String(format: "%.1f", sides[0].length(run.a))) s, \(run.a.count) frames")
      for (side, range) in [(sides[0], run.a), (sides[1], run.b)] {
        print("  In the \(side.title.lowercased()) episode: \(side.times(range))")
        print("    start: \(words(side.evidence(at: range.lowerBound)))")
        print("    end: \(words(side.evidence(at: range.upperBound)))")
      }
    }
    print("")
    summary(runs, sides)
    return 0
  }

  private static func describe(_ side: Side) -> String {
    let resets = side.report.reservoirResets.count
    let every = side.seconds / 60 / Double(max(1, resets))
    let often = resets == 0 ? "none" : "\(resets) (about one every \(String(format: "%.1f", every)) min)"
    return "\(Probe.seconds(side.seconds)) long, \(side.parse.frames.count) MP3 frames, "
      + "\(side.parse.bitrate / 1000) kbps at the start. Reservoir resets: \(often). "
      + "Changes of encoding: \(side.report.seams.count)."
  }

  private static func words(_ evidence: EdgeEvidence) -> String {
    var parts: [String] = []
    if let reset = evidence.reset {
      let frames = "\(abs(reset)) frame\(abs(reset) == 1 ? "" : "s")"
      switch reset {
      case 0: parts.append("a reservoir reset right at the edge")
      case 1...: parts.append("a reservoir reset \(frames) after it")
      default: parts.append("a reservoir reset \(frames) before it")
      }
    }
    if let seam = evidence.seam { parts.append("a change of encoding (\(seam))") }
    if parts.isEmpty { return "nothing within \(SharedRuns.edgeReach) frames" }
    return parts.joined(separator: " and ")
  }

  private static func summary(_ runs: [SharedRun], _ sides: [Side]) {
    let long = runs.filter { sides[0].length($0.a) >= 10 }
    let covered = runs.reduce(0) { $0 + $1.a.count }
    let shorter = min(sides[0].parse.frames.count, sides[1].parse.frames.count)
    print("Summary")
    print("  Stretches of 3 s or more: \(runs.count). Of 10 s or more: \(long.count).")
    if !long.isEmpty {
      let first = long.filter { sides[0].marksBothEnds($0.a) }.count
      let second = long.filter { sides[1].marksBothEnds($0.b) }.count
      print(
        "  Of those, a reservoir reset or a change of encoding sits at both ends: "
          + "\(first) in the first episode, \(second) in the second.")
      print(
        "  Resets also happen inside ordinary audio, so one at an edge proves little "
          + "where a file has many.")
    }
    print("")
    if Double(covered) >= 0.8 * Double(shorter) {
      print(
        "What it means: most of the two files is the same audio, so they look like two downloads of one episode, not two episodes. Choose two different episodes of the show."
      )
    } else if runs.isEmpty {
      print(
        "What it means: no spot is shared by these two episodes (or the host makes new bytes for each episode, so a repeated ad cannot be told by its bytes). Try two episodes that open with the same kind of ad."
      )
    } else if long.isEmpty {
      print(
        "What it means: only short stretches are shared (a jingle or a sting, most likely). A whole ad is not."
      )
    } else {
      let which = long.count == 1 ? "One stretch is" : "\(long.count) stretches are"
      print(
        "What it means: \(which) 10 s or more of the same bytes in both episodes. Listen at those times: if they are ads, the host copies an ad's frames as they are. Send this file along."
      )
    }
  }

  // MARK: --truth-from-copies

  static func truthFromCopies(_ first: URL, _ second: URL) -> Int32 {
    guard let parses = parse([first, second]) else { return 1 }
    let lines = CopyTruth.lines(parses[0], parses[1])
    let ads = lines.filter { !$0.hasPrefix("#") }
    lines.forEach { print($0) }
    guard !ads.isEmpty else {
      say("No stretch was marked, so no file was written.")
      return 1
    }
    let out = URL(fileURLWithPath: first.path + ".truth.txt")
    guard !FileManager.default.fileExists(atPath: out.path) else {
      say("\(out.path) is already there. Move or rename it first, so marks made by hand are kept.")
      return 1
    }
    do {
      try (lines.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
    } catch {
      say("Could not write \(out.path): \(error.localizedDescription)")
      return 1
    }
    let count = "\(ads.count) stretch\(ads.count == 1 ? "" : "es")"
    say("Marked \(count) in \(first.lastPathComponent). Saved: \(out.path)")
    return 0
  }
}
