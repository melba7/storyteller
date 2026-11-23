// LOFI-FORK: `podcast-teach apple`: asks Apple's on-device model about the teaching episodes and
// keeps its answers in `apple-model.json` (see FORK.md and AppleAnswers.swift). The loop takes any
// `AdDetector`, so tests run it with a fake one; only the tool hands in the real one. Foundation
// only.
import Foundation
import PodcastTranscripts

public enum AppleCommand {
  public struct Options: Equatable {
    public var folder: String
    public var exam = false
    public var limit: Int?
  }

  public static let usage = "Usage: podcast-teach apple <teaching folder> [--exam] [--limit N]"

  public static func parse(_ arguments: [String]) -> Result<Options, TeachingFolderError> {
    var options = Options(folder: "")
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--exam": options.exam = true
      case "--limit":
        index += 1
        guard index < arguments.count, let number = Int(arguments[index]), number > 0 else {
          return .failure(TeachingFolderError(message: "--limit needs a number above zero."))
        }
        options.limit = number
      case let flag where flag.hasPrefix("--"):
        return .failure(TeachingFolderError(message: "Unknown option \(flag)."))
      case let path:
        guard options.folder.isEmpty else {
          return .failure(TeachingFolderError(message: "Only one teaching folder can be named."))
        }
        options.folder = path
      }
      index += 1
    }
    guard !options.folder.isEmpty else {
      return .failure(TeachingFolderError(message: "Name the teaching folder."))
    }
    return .success(options)
  }

  /// Runs the command. 0 it worked, 1 some episodes could not be asked, 2 a set-up problem
  /// (also no model on this system, which `detector` being nil says).
  public static func run(
    _ arguments: [String], detector: AdDetector?, osVersion: String = "",
    out: (String) -> Void, err: (String) -> Void
  ) async -> Int32 {
    let options: Options
    switch parse(arguments) {
    case .failure(let problem):
      err("\(problem.message)\n\(usage)")
      return 2
    case .success(let parsed): options = parsed
    }
    guard let detector else {
      err("Apple's model is not available here (it needs a Mac with macOS 26 and Apple Intelligence on). Nothing was asked.")
      return 2
    }
    let folder = URL(fileURLWithPath: options.folder)
    var notes: [String] = []
    let episodes: [TeachingEpisode]
    do {
      episodes = try TeachingFolder.episodes(in: folder, notes: &notes)
    } catch {
      err("\(error.localizedDescription)")
      return 2
    }
    for note in notes { err(note) }
    let chosen = scored(episodes, exam: options.exam)
    guard !chosen.isEmpty else {
      out("No episode in \(folder.path) is to be scored yet.")
      return 0
    }
    let model = "\(detector.name) \(detector.version)"
    var answers: AppleAnswers
    switch AppleAnswers.load(in: folder) {
    case .failure(let problem):
      err(problem.message)
      return 2
    case .success(let saved):
      answers = saved ?? AppleAnswers(model: model)
    }
    guard answers.model == model else {
      err(
        "\(AppleAnswers.fileName) holds the answers of \(answers.model), and this Mac asks \(model). Move the file away to ask again; nothing was changed."
      )
      return 2
    }
    let failed = await ask(
      chosen, into: &answers, detector: detector, osVersion: osVersion, limit: options.limit,
      save: { try $0.save(in: folder) }, out: out, err: err)
    switch failed {
    case .unavailable: return 2
    case .episodes(let count):
      let have = chosen.filter { answers.episodes[$0.id] != nil }.count
      out("\(have) of \(chosen.count) episodes have answers from \(model).")
      return count > 0 ? 1 : 0
    }
  }

  /// The episodes a plain `score` run scores: the exam's with `exam`, else the shelf (or all
  /// labelled episodes when there is no shelf).
  static func scored(_ episodes: [TeachingEpisode], exam: Bool) -> [TeachingEpisode] {
    if exam { return episodes.filter(\.onExam) }
    let labelled = episodes.filter { !$0.onExam }
    let shelf = labelled.filter(\.onShelf)
    return shelf.isEmpty ? labelled : shelf
  }

  enum Outcome: Equatable {
    case episodes(failed: Int)
    /// The model said it cannot be used; the rest would fail the same way.
    case unavailable
  }

  /// Asks the model about each episode that has no answer yet (the first `limit` of them), and
  /// saves the answers after each one.
  static func ask(
    _ episodes: [TeachingEpisode], into answers: inout AppleAnswers, detector: AdDetector,
    osVersion: String, limit: Int?, save: (AppleAnswers) throws -> Void, out: (String) -> Void,
    err: (String) -> Void
  ) async -> Outcome {
    var failed = 0
    var asked = 0
    for episode in episodes where answers.episodes[episode.id] == nil {
      if let limit, asked >= limit { break }
      asked += 1
      let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
        "apple-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: scratch) }
      let started = Date()
      do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let outcome = try await AdsRunner.run(
          transcript: episode.transcript, detector: detector,
          store: AdsStore(folder: scratch, sha256: "apple"), osVersion: osVersion)
        guard case .finished(let file) = outcome else { continue }
        let seconds = Date().timeIntervalSince(started)
        answers.episodes[episode.id] = AppleAnswers.Answer(
          ads: file.ads.map {
            AppleAnswers.Ad(start: $0.start, end: $0.end, kind: $0.kind, confidence: $0.confidence)
          }, refusedPieces: file.refusedPieces ?? 0, seconds: seconds)
        try save(answers)
        out(String(format: "%@: %d ads, %.1f s", episode.id, file.ads.count, seconds))
      } catch AdDetectorError.unavailable(let reason) {
        err("Apple's model cannot be used now: \(reason.reason). Run this again when it can.")
        return .unavailable
      } catch {
        failed += 1
        err("\(episode.id): not asked (\(error.localizedDescription))")
      }
    }
    return .episodes(failed: failed)
  }
}
