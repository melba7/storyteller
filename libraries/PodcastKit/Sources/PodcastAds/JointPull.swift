// LOFI-FORK: which ads the pull-back of a late start may apply to (see FORK.md). Foundation only.
import Foundation

/// The one rule for the pull-back of `JointSnap`, which the scorecard and the phone both use, so
/// that the scorer measures exactly what the phone does. The pull is for the late start of an ad
/// found from the transcript's words, and only by a finder the rule knows by name: the repeated
/// words, the meaning model and the word model. It is never for Apple's model, chapters, the
/// memory of ads, a sound finder, a listener's "tap", or a source the rule does not know.
///
/// An ad with NO source is also left out. The older finders (the word rules, the trained model,
/// the library of known ads, Apple's model, chapters and the Mac's sound hits) all give ads with
/// no source, so the rule cannot tell the word finders among them. They get the pull only when
/// they are given a name of their own and that name is added to `names`.
public enum JointPull {
  /// The names of the finders whose ads may be pulled: the `source` of their ads.
  public static let names: Set<String> = [ShowTuning.repeatWords, ShowTuning.meaning, "word-model"]

  public static func allows(source: String?) -> Bool {
    guard let source else { return false }
    return names.contains(source)
  }
}
