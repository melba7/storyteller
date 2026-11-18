// LOFI-FORK: turns any error the on-device model throws into one of ours (see FORK.md).
import Foundation

/// What to make of an error that came from the on-device model. The model's error types change
/// between system versions (iOS 27 brings new ones), so this reads an error by its type name,
/// its case name and its text instead of naming the types. That keeps the package compiling on
/// every Swift 6.2 toolchain, and an error that nobody planned for still ends as one of
/// `AdDetectorError`, so the runner can carry on with the next piece.
///
/// A refused piece has no answer, so it can only lead to fewer skips than a full answer.
public enum AdModelFailure {
  /// The words in an error's text that mean the model would not read the lines. Short on
  /// purpose: a wider list would turn a real fault into a "refusal" and hide it.
  static let refusalWords = ["refus", "guardrail", "sensitive"]

  /// The error as one of ours. An `AdDetectorError` comes back unchanged.
  public static func classify(_ error: Error) -> AdDetectorError {
    if let ours = error as? AdDetectorError { return ours }
    let found = names(of: error)
    return classify(
      typeName: found.typeName, caseName: found.caseName, text: error.localizedDescription)
  }

  /// The error from its names. The case name decides when it is one of the known cases. The
  /// text decides only for an error of the model's own types, and only for a case that is not
  /// known, so a word in the text of a timeout or of a file error is never a refusal.
  public static func classify(typeName: String, caseName: String, text: String) -> AdDetectorError {
    switch caseName.lowercased() {
    // The model refused the lines, or could not put its answer in the asked shape. The answer
    // is the same every time (the sampling is greedy), so asking again is no use.
    case "guardrailviolation", "refusal", "decodingfailure":
      return .refused
    case "contextsizeexceeded", "exceededcontextwindowsize":
      return .tooLong
    case "unsupportedlanguageorlocale":
      return .failed("The on-device model does not support this language")
    // These pass, so the piece is asked again later.
    case "ratelimited", "timeout", "concurrentrequests", "assetsunavailable":
      return .failed(text)
    default:
      break
    }
    let ofTheModel = typeName.contains("FoundationModels") || typeName.contains("LanguageModel")
    let lowered = text.lowercased()
    if ofTheModel, refusalWords.contains(where: { lowered.contains($0) }) { return .refused }
    return .failed(text)
  }

  /// The type name and the case name of an error, for `classify` and for the ad finder's diary.
  /// The case name is the enum case when the error is one, and "unknown" when the error has
  /// nothing that looks like a name, so a diary line never holds an error's whole text.
  public static func names(of error: Error) -> (typeName: String, caseName: String) {
    let typeName = String(reflecting: type(of: error))
    let label = Mirror(reflecting: error).children.first?.label ?? String(describing: error)
    let simple = !label.isEmpty && label.count <= 60
      && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    return (typeName, simple ? label : "unknown")
  }
}
