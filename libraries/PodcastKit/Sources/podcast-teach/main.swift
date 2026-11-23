// LOFI-FORK: the Mac's teaching run, the parts that use the phone's own code (see FORK.md).
//
//   swift run -c release podcast-teach score <teaching folder> [options]
//   swift run -c release podcast-teach agree <teaching folder> [options]
//   swift run -c release podcast-teach sounds <teaching folder> [options]
//   swift run -c release podcast-teach meaning <teaching folder> [options]
//
// "score" replays the phone's ad finders on the marked episodes of the teaching folder and
// prints a scorecard (Score.swift). "sounds" makes the library of ad sounds from the marked
// episodes' audio (Sounds.swift). Both need only Foundation, so they also run on Linux.
// "meaning" trains the small model that reads what a line means (Meaning.swift); it needs a
// Mac, because the numbers for a line come from Apple's sentence embedding.
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "score": exit(ScoreCommand.run(Array(arguments.dropFirst())))
case "agree": exit(AgreeCommand.run(Array(arguments.dropFirst())))
case "sounds": exit(SoundsCommand.run(Array(arguments.dropFirst())))
case "meaning": exit(MeaningTool.run(Array(arguments.dropFirst())))
default:
  FileHandle.standardError.write(
    Data(
      """
      Usage: podcast-teach score <teaching folder> | podcast-teach agree <teaching folder> | podcast-teach sounds <teaching folder> | podcast-teach meaning <teaching folder>

      """.utf8))
  exit(2)
}
