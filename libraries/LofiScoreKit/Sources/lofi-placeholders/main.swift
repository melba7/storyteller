import Foundation
import LofiPlaceholders
import LofiScoreCore

// Writes the placeholder music library: one folder per mood, synthesised WAV tracks
// normalised to −16 LUFS, and a library.json describing them.
//
//   swift run -c release lofi-placeholders [folder] [--per-mood N] [--sample-rate HZ] [--list]
//
// The default folder is ./PlaceholderLibrary, which git ignores. Never commit the output.

func usage() -> Never {
    print("""
    usage: lofi-placeholders [folder] [--per-mood N] [--sample-rate HZ] [--list]

      folder          where to write (default: PlaceholderLibrary)
      --per-mood N    tracks per mood (default 2; more than 2 are transposed variations)
      --sample-rate   output sample rate in Hz (default 44100)
      --list          print the recipes without rendering
    """)
    exit(2)
}

var folderPath = "PlaceholderLibrary"
var perMood = 2
var sampleRate = 44_100.0
var listOnly = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--per-mood":
        guard let value = arguments.popFirst().flatMap(Int.init), value > 0 else { usage() }
        perMood = value
    case "--sample-rate":
        guard let value = arguments.popFirst().flatMap(Double.init), value >= 8000 else { usage() }
        sampleRate = value
    case "--list":
        listOnly = true
    case "-h", "--help":
        usage()
    default:
        if argument.hasPrefix("-") { usage() }
        folderPath = argument
    }
}

let recipes = PlaceholderRecipe.defaults(perMood: perMood)
if listOnly {
    for recipe in recipes {
        print(String(format: "%-14@ %5.1fs  %@", recipe.id as NSString, recipe.duration, recipe.summary as NSString))
    }
    exit(0)
}

let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
let started = Date()
do {
    let manifest = try PlaceholderLibrary.write(to: folder, recipes: recipes, sampleRate: sampleRate) { done, total, track in
        print(String(
            format: "[%2d/%d] %-14@ %5.1fs  %6.1f LUFS  peak %5.1f dBFS",
            done, total, track.recipe.id as NSString, track.audio.duration, track.loudness, track.truePeak
        ))
    }
    let seconds = Date().timeIntervalSince(started)
    print("Wrote \(manifest.tracks.count) tracks and library.json to \(folder.path) in \(String(format: "%.1f", seconds)) s")
} catch {
    FileHandle.standardError.write(Data("lofi-placeholders: \(error)\n".utf8))
    exit(1)
}
