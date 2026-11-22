// LOFI-FORK: `podcast-teach sounds` (see FORK.md).
import Foundation
import PodcastAudioMatch

enum SoundsCommand {
  /// Runs the command and returns its exit code.
  static func run(_ arguments: [String]) -> Int32 { AdSoundCommand.run(arguments) }
}
