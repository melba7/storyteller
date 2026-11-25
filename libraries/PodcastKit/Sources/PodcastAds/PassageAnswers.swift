// LOFI-FORK: the passage model's answers for the teaching episodes, made on the Mac
// (`Tools/mac/teach_passage.py`) and read by the scorecard (see FORK.md). For every line of a shelf
// episode it holds five chances, one for each of the word model's classes, and never any transcript
// text. Foundation only.
import Foundation

/// `passage-model.json` in the teaching folder:
/// `{"version": 1, "model", "decoder": 2, "classes", "thresholds", "trained", "episodes":
/// {"<id>": {"lines": N, "rows": [[five numbers], ...]}}}`. A row is the chances of the classes of
/// `AdWordModel.classes` ("none" first) for one line, in the order of the episode's transcript
/// lines. The scorecard reads the rows with the word model's decoder of version 2, the one named by
/// `decoder` (`AdWordModel.decodeTwo`, which `teach_spans.py` repeats), with the cut-offs of the file.
struct PassageAnswers: Equatable {
  static let fileName = "passage-model.json"
  static let currentVersion = 1
  /// The version of the word model's decoder the rows are read with. A file made for another one
  /// is refused, because its rows would be read by rules it was not checked with.
  static let decoder = 2

  struct Answer: Equatable {
    var lines: Int
    var rows: [[Double]]
  }

  /// What made the answers, as the Mac named it.
  var model: String
  var thresholds: AdWordModel.Thresholds
  var episodes: [String: Answer]

  private struct File: Decodable {
    var version: Int
    var model: String
    var decoder: Int
    var classes: [String]
    var thresholds: [String: Double]?
    var episodes: [String: FileAnswer]
  }

  private struct FileAnswer: Decodable {
    var lines: Int
    var rows: [[Double]]
  }

  /// The file in `folder`: nil when there is none, a plain sentence when it cannot be used. It is
  /// only read, never changed.
  static func load(in folder: URL) -> Result<PassageAnswers?, TeachingFolderError> {
    let url = folder.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return .success(nil) }
    func refuse(_ reason: String) -> Result<PassageAnswers?, TeachingFolderError> {
      .failure(
        TeachingFolderError(
          message:
            "\(fileName) in \(folder.path) could not be read: \(reason). \"Teach the passage model\" makes it again; nothing was changed."
        ))
    }
    guard let data = try? Data(contentsOf: url),
      let file = try? JSONDecoder().decode(File.self, from: data)
    else { return refuse("it is damaged") }
    guard file.version == currentVersion else {
      return refuse("it is version \(file.version) and this build reads version \(currentVersion)")
    }
    guard file.decoder == decoder else {
      return refuse("it was made for decoder \(file.decoder) and this build has decoder \(decoder)")
    }
    guard file.classes == AdWordModel.classes else {
      return refuse("its classes are not the word model's")
    }
    guard let thresholds = AdWordModel.thresholds(from: file.thresholds) else {
      return refuse("its cut-offs are not numbers from 0 to 1 with a start of at least 0.5")
    }
    for (id, answer) in file.episodes {
      let fits =
        answer.rows.count == answer.lines
        && answer.rows.allSatisfy { row in
          row.count == AdWordModel.classes.count && row.allSatisfy { $0.isFinite && (0.0...1.0).contains($0) }
        }
      guard fits else {
        return refuse(
          "the answers for episode \(id) are not one row of five chances for each of its \(answer.lines) lines"
        )
      }
    }
    return .success(
      PassageAnswers(
        model: file.model, thresholds: thresholds,
        episodes: file.episodes.mapValues { Answer(lines: $0.lines, rows: $0.rows) }))
  }
}
