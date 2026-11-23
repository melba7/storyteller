// LOFI-FORK: `podcast-teach meaning` (see FORK.md). The work is in MeaningCommand (PodcastAds), so
// tests can call it; this file only picks the embedder. With no NaturalLanguage framework
// (Linux), or a Mac that has no English sentence embedding, the command says it needs a Mac and
// exits with 2.
import Foundation
import PodcastAds

#if canImport(NaturalLanguage)
  import PodcastAdsOnDevice
#endif

enum MeaningTool {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) -> Int32 {
    #if canImport(NaturalLanguage)
      let embedder: LineEmbedder? = AppleLineEmbedder()
    #else
      let embedder: LineEmbedder? = nil
    #endif
    return MeaningCommand.run(
      arguments, embedder: embedder,
      out: { print($0) },
      err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
  }
}
