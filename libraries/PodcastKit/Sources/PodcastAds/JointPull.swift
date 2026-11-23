// LOFI-FORK: which ads the pull-back of a late start may apply to (see FORK.md). Foundation only.
import Foundation

/// The one rule for the pull-back of `JointSnap`, which the scorecard and the phone both use, so
/// that the scorer measures exactly what the phone does. The pull is for a start that a word
/// finder gave: the repeated words, the meaning model, the word model, the word rules.
///
/// An ad that has a source name is pulled only when the name is in `names`. An ad with no source
/// is given by an older finder (the word rules, the trained word model, the library of known ads,
/// Apple's model, chapters, the memory of ads or the Mac's sound hits), and the ad does not say
/// which. So the start tells it: the ad may be pulled only when the list of ads that the word
/// rules and the word model gave for the whole transcript holds an ad of the same kind that
/// starts at the same moment. `AdJoin` keeps the earliest part's start, so a joined ad whose
/// start came from a word finder still matches, and one whose start came from Apple's model, a
/// chapter, the memory of ads or a sound does not. A caller with no such list gets no pull for
/// an ad with no source.
public enum JointPull {
  /// The names of the finders whose ads may be pulled: the `source` of their ads.
  public static let names: Set<String> = [ShowTuning.repeatWords, ShowTuning.meaning, "word-model"]

  public static func allows(source: String?) -> Bool {
    guard let source else { return false }
    return names.contains(source)
  }

  /// Whether `ad` may be pulled, given `words`: the ads the word rules and the word model gave for
  /// the whole transcript, before any join. See the rule above.
  public static func allows(_ ad: FoundAd, words: [FoundAd]) -> Bool {
    guard ad.source == nil else { return allows(source: ad.source) }
    return words.contains { $0.kind == ad.kind && abs($0.start - ad.start) < 1e-6 }
  }
}
