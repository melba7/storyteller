// LOFI-FORK: `podcast-teach agree`: how often two markings of the same episodes agree to within
// the bar (see FORK.md and AdBar.swift). Foundation only.
import Foundation

public enum AdAgreeCommand {
  public static let usage =
    "Usage: podcast-teach agree <teaching folder> [--labels NAME] [--second NAME]"

  /// The bar of one marking read as skips against the other read as truth, over every episode
  /// that has both. Exam episodes are left out, as they are from a normal score.
  static func compare(
    first: [TeachingEpisode], second: [TeachingEpisode]
  ) -> (episodes: Int, forward: BarTotals, backward: BarTotals) {
    let others = Dictionary(second.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    var forward = BarTotals()
    var backward = BarTotals()
    var episodes = 0
    for one in first where !one.onExam {
      guard let two = others[one.id] else { continue }
      episodes += 1
      forward += AdBar.score(episode: one, found: skips(of: two))
      backward += AdBar.score(episode: two, found: skips(of: one))
    }
    return (episodes, forward, backward)
  }

  /// The counted stretches of a marking as sure found ads.
  private static func skips(of episode: TeachingEpisode) -> [FoundAd] {
    AdScore.counted(episode, AdSkipSettings()).compactMap { stretch in
      AdKind(sort: stretch.sort).map {
        FoundAd(
          start: stretch.start, end: stretch.end, kind: $0, advertiser: "", confidence: .sure,
          firstWords: "")
      }
    }
  }

  /// Runs the command. 0 it worked (also when no episode is marked twice), 2 a set-up problem.
  public static func run(
    _ arguments: [String], out: (String) -> Void, err: (String) -> Void
  ) -> Int32 {
    var folder = ""
    var labels = "labels"
    var second = "labels-second"
    var index = 0
    func problem(_ message: String) -> Int32 {
      err("\(message)\n\(usage)")
      return 2
    }
    while index < arguments.count {
      switch arguments[index] {
      case "--labels", "--second":
        let flag = arguments[index]
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else {
          return problem("\(flag) needs a folder name.")
        }
        if flag == "--labels" { labels = arguments[index] } else { second = arguments[index] }
      case let flag where flag.hasPrefix("--"):
        return problem("Unknown option \(flag).")
      case let path:
        guard folder.isEmpty else { return problem("Only one teaching folder can be named.") }
        folder = path
      }
      index += 1
    }
    guard !folder.isEmpty else { return problem("Name the teaching folder.") }
    let url = URL(fileURLWithPath: folder)
    var notes: [String] = []
    let first: [TeachingEpisode]
    let other: [TeachingEpisode]
    do {
      first = try TeachingFolder.episodes(in: url, labels: labels, notes: &notes)
      other = try TeachingFolder.episodes(in: url, labels: second, notes: &notes)
    } catch {
      err("\(error.localizedDescription)")
      return 2
    }
    for note in Set(notes).sorted() { err(note) }
    let result = compare(first: first, second: other)
    guard result.episodes > 0 else {
      out("No episode in \(url.path) is marked in both \(labels) and \(second) yet.")
      return 0
    }
    func line(_ name: String, _ bar: BarTotals) -> String {
      String(
        format: "%@: %d breaks, %d pass (%.1f%%).", name, bar.breaks, bar.passed, bar.rate * 100)
    }
    let mean = (result.forward.rate + result.backward.rate) / 2 * 100
    out(
      [
        "\(result.episodes) episodes are marked in both \(labels) and \(second).",
        line("\(labels) as truth, \(second) as the skips", result.forward),
        line("\(second) as truth, \(labels) as the skips", result.backward),
        String(format: "Mean of the two rates: %.1f%%.", mean),
        "This is how often two careful markings of the same episode agree to within the bar, so it is the most any finder can score on this test.",
      ].joined(separator: "\n"))
    return 0
  }
}
