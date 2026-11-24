// LOFI-FORK: the logic of `podcast-teach edges`, in the library so that tests can call it (see FORK.md
// and EdgeSound.swift). Foundation only: the decoder that turns an MP3 file into samples comes in as
// an `EdgeReader`, and only a Mac has one.
import Foundation

/// Reads a file as mono samples, handing them over in pieces, in order, at `sampleRate`.
public struct EdgeReader {
  public var sampleRate: Double
  public var read: (URL, ([Float]) -> Void) async throws -> Void

  public init(sampleRate: Double, read: @escaping (URL, ([Float]) -> Void) async throws -> Void) {
    self.sampleRate = sampleRate
    self.read = read
  }
}

public enum EdgeCommand {
  public static let usage = "Usage: podcast-teach edges <teaching folder>"
  public static let reportName = "edges-report.json"

  private struct Shares: Codable {
    var points: Int
    var within: [Int]
    var share: [Double]

    init(_ shares: EdgeShares) {
      points = shares.points
      within = shares.hits
      share = shares.hits.indices.map { shares.share($0) }
    }
  }

  private struct Report: Codable {
    var version = 1
    var finder = EdgeSound.version
    var writtenAt = Date().timeIntervalSince1970
    var rule = EdgeMeasure.rule
    var reaches = EdgeMeasure.reaches
    var episodes: Int
    var leftOut: Int
    var edges: Shares
    var random: Shares
    var verdict: String
  }

  /// For every shelf episode with an MP3 file in the teaching folder that `edges.json` does not hold
  /// yet, reads the sound and keeps its change peaks there (after each episode, so a run that is
  /// stopped carries on where it was). Then measures how well the strongest change within 10
  /// seconds lines up with the exactly placed edges of the ad spots in `labels-snapped`, against
  /// random points, and writes `edges-report.json`. 0 it worked, 1 some episodes could not be read,
  /// 2 a set-up problem (also no decoder, which `reader` being nil says).
  public static func run(
    _ arguments: [String], reader: EdgeReader?, out: (String) -> Void, err: (String) -> Void
  ) async -> Int32 {
    guard arguments.count == 1, !arguments[0].hasPrefix("--") else {
      err(usage)
      return 2
    }
    let folder = URL(fileURLWithPath: arguments[0], isDirectory: true)
    guard let reader else {
      err("This computer cannot read MP3 sound. Run this on the Mac, with Xcode's tools.")
      return 2
    }
    let plan: Plan
    switch Plan.make(folder) {
    case .failure(let problem):
      err(problem.message)
      return 2
    case .success(let made): plan = made
    }
    let loaded = EdgesFile.load(in: folder)
    if let problem = loaded.problem { err(problem) }
    var edges = loaded.file
    let todo = plan.audio.filter { edges.episodes[$0.id] == nil }
    out(
      "Sound at the edges: \(count(plan.audio.count, "shelf episode")) with an MP3 file; \(plan.audio.count - todo.count) done already, \(todo.count) to read."
    )
    if plan.wanted.count > plan.audio.count {
      let missing = plan.wanted.count - plan.audio.count
      out("\(count(missing, "shelf episode")) \(missing == 1 ? "has" : "have") no audio file.")
    }
    var failed = 0
    for (place, item) in todo.enumerated() {
      let started = Date()
      var meter = EdgeMeter(sampleRate: reader.sampleRate)
      do { try await reader.read(item.file) { meter.add($0) } } catch {
        err("\(item.id): could not be read (\(error.localizedDescription)).")
        failed += 1
        continue
      }
      let blocks = meter.finish()
      guard blocks.count > 0 else {
        err("\(item.id): could not be read (there is no sound in the file).")
        failed += 1
        continue
      }
      let analysis = EdgeSound.analyse(blocks)
      edges.episodes[item.id] = EdgesFile.Entry(seconds: analysis.seconds, peaks: analysis.peaks)
      do { try edges.write(in: folder) } catch {
        err(
          "\(EdgesFile.fileName) could not be written to \(folder.path): \(error.localizedDescription)"
        )
        return 2
      }
      out(
        String(
          format: "%d of %d: %@, %.1f minutes, %d changes kept, %.0f seconds.", place + 1,
          todo.count,
          item.id, analysis.seconds / 60, analysis.peaks.count, Date().timeIntervalSince(started)))
    }
    let episodes = plan.wanted.compactMap { id -> EdgeEpisode? in
      guard let entry = edges.episodes[id] else { return nil }
      let read = { (name: String) in
        try? Data(contentsOf: folder.appendingPathComponent("\(name)/\(id).json"))
      }
      return EdgeEpisode(
        id: id, seconds: entry.seconds, peaks: entry.edgePeaks,
        edges: EdgeMeasure.exactEdges(snapped: read("labels-snapped"), claude: read("labels")))
    }
    let result = EdgeMeasure.measure(episodes)
    do {
      let report = Report(
        episodes: result.episodes, leftOut: result.leftOut, edges: Shares(result.edges),
        random: Shares(result.random), verdict: result.verdict.rawValue)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
      try encoder.encode(report).write(
        to: folder.appendingPathComponent(reportName), options: .atomic)
    } catch {
      err("\(reportName) could not be written to \(folder.path): \(error.localizedDescription)")
      return 2
    }
    summary(result, out)
    return failed > 0 ? 1 : 0
  }

  /// What a run works on: the shelf episodes that may be read (the exam never is), and the MP3 file
  /// of each that has one.
  private struct Plan {
    var wanted: [String]
    var audio: [(id: String, file: URL)]

    struct Problem: Error { var message: String }

    /// The plan for `folder`, or the plain sentence that says what is missing. Nothing is read yet.
    static func make(_ folder: URL) -> Result<Plan, Problem> {
      var isFolder: ObjCBool = false
      guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder),
        isFolder.boolValue
      else { return .failure(Problem(message: "There is no teaching folder at \(folder.path).")) }
      guard let shelf = EdgeCommand.ids("shelf.json", in: folder) else {
        return .failure(
          Problem(
            message:
              "There is no usable shelf.json in \(folder.path). \"Teach the phone again\" makes it."
          ))
      }
      var exam: [String] = []
      if FileManager.default.fileExists(atPath: folder.appendingPathComponent("exam.json").path) {
        guard let listed = EdgeCommand.ids("exam.json", in: folder) else {
          return .failure(
            Problem(
              message:
                "exam.json in \(folder.path) is not in the expected shape, so nothing was read."))
        }
        exam = listed
      }
      var isSnapped: ObjCBool = false
      guard
        FileManager.default.fileExists(
          atPath: folder.appendingPathComponent("labels-snapped").path, isDirectory: &isSnapped),
        isSnapped.boolValue
      else {
        return .failure(
          Problem(
            message:
              "There is no labels-snapped folder in \(folder.path), so no ad spot has exact edges yet. Double-click \"Check ads with a second download\" first."
          ))
      }
      let wanted = shelf.filter { !exam.contains($0) && EdgeCommand.plain($0) }.sorted()
      let files = EdgeCommand.audio(in: folder)
      return .success(
        Plan(
          wanted: wanted, audio: wanted.compactMap { id in files[id].map { (id: id, file: $0) } }))
    }
  }

  private static func summary(_ result: EdgeResult, _ out: (String) -> Void) {
    guard result.edges.points > 0 else {
      out(
        "No exact edge could be measured: no shelf episode has an ad spot that a second download placed."
      )
      out("Verdict: \(result.verdict.rawValue).")
      return
    }
    out(
      "\(count(result.edges.points, "exact edge")) in \(count(result.episodes, "episode")) (\(result.leftOut) left out for lying within 3 seconds of the start or end of the episode), and as many random points (seed \(EdgeMeasure.seed))."
    )
    out("Exact edges: " + reaches(result.edges))
    out("Random points: " + reaches(result.random))
    // A strongest change that fell anywhere in the 20 seconds would be within 1 second 1 time in 10.
    let chance = EdgeMeasure.reaches.map {
      String(format: "%.0f%%", $0 / EdgeSound.searchSeconds * 100)
    }
    out(
      "By chance alone, with the strongest change anywhere in those 20 seconds, the shares would be about \(chance.joined(separator: ", "))."
    )
    let verdict = result.verdict == .go ? "Go." : "No go."
    out("Verdict: \(verdict) The plan's rule is that \(EdgeMeasure.rule).")
    out("Written: \(EdgesFile.fileName) (the peaks) and \(reportName).")
  }

  /// "the strongest change is within 1 second of 3 of 4 (75%), within 2 seconds of ...".
  private static func reaches(_ shares: EdgeShares) -> String {
    let parts = EdgeMeasure.reaches.enumerated().map { index, reach in
      let percent = String(format: "%.0f%%", shares.share(index) * 100)
      return
        "within \(Int(reach)) second\(reach == 1 ? "" : "s") of \(shares.hits[index]) of \(shares.points) (\(percent))"
    }
    return "the strongest change is " + parts.joined(separator: ", ") + "."
  }

  private static func count(_ number: Int, _ noun: String) -> String {
    "\(number) \(noun)\(number == 1 ? "" : "s")"
  }

  /// Whether an id is one plain name: no slash and no `..`.
  private static func plain(_ id: String) -> Bool { !id.isEmpty && !id.contains("/") && id != ".." }

  /// The ids in a file of the folder (`{"episodes": ["id", ...]}`), or nil when it is missing or not
  /// in that shape.
  private static func ids(_ name: String, in folder: URL) -> [String]? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let list = root["episodes"] as? [Any], list.allSatisfy({ $0 is String })
    else { return nil }
    return list.compactMap { $0 as? String }
  }

  /// The MP3 file of each episode of `episodes.json` that has one in the folder: a name that stays
  /// inside the folder, ends in `.mp3` and is a regular file.
  private static func audio(in folder: URL) -> [String: URL] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("episodes.json")),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let list = root["episodes"] as? [Any]
    else { return [:] }
    var found: [String: URL] = [:]
    for case let entry as [String: Any] in list {
      guard let id = entry["id"] as? String, plain(id), let file = entry["file"] as? String,
        !file.hasPrefix("/"), !file.split(separator: "/").contains(".."),
        file.lowercased().hasSuffix(".mp3")
      else { continue }
      let url = folder.appendingPathComponent(file)
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        found[id] = url
      }
    }
    return found
  }
}
