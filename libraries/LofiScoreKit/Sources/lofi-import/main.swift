import Foundation
import LofiAudio
import LofiPlaceholders
import LofiScoreCore
#if canImport(AVFoundation)
import LofiDemoKit
#endif

// Measures a music folder (one subfolder per mood) and writes its library.json: each
// track's loudness, true peak and length, plus its source and license from SOURCES.csv
// when the folder has one. The player then sets every track's bed level from its real
// loudness. Run it again after adding music; until then new files play at an assumed
// −16 LUFS.
//
//   swift run -c release lofi-import <music folder> [--dry-run]
//
// The previous library.json, if any, is kept as library.json.bak. Nothing here touches git.

func usage() -> Never {
    print("""
    usage: lofi-import <music folder> [--dry-run]

      music folder   a folder with Calm/, Cozy/, ... Somber/ subfolders (and optionally library.json)
      --dry-run      measure and print, but do not write library.json
    """)
    exit(2)
}

var folderPath: String?
var dryRun = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--dry-run":
        dryRun = true
    case "-h", "--help":
        usage()
    default:
        if argument.hasPrefix("-") || folderPath != nil { usage() }
        folderPath = argument
    }
}
guard let folderPath else { usage() }
let folder = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)

func decode(_ url: URL) throws -> StereoBuffer {
    #if canImport(AVFoundation)
    return try AudioFileIO.readStereo(url)
    #else
    guard url.pathExtension.lowercased() == "wav" else {
        throw NSError(domain: "lofi-import", code: 1, userInfo: [NSLocalizedDescriptionKey: "only WAV can be read on this platform"])
    }
    return try WAVFile.read(Data(contentsOf: url))
    #endif
}

do {
    let started = Date()
    let library = try MusicLibrary.load(from: folder)
    let sourcesURL = folder.appendingPathComponent("SOURCES.csv")
    let provenance = (try? String(contentsOf: sourcesURL, encoding: .utf8)).map(LibraryImporter.provenance(csv:)) ?? [:]
    print("\(library.tracks.count) tracks in \(folder.path)" + (provenance.isEmpty ? "" : ", \(provenance.count) rows in SOURCES.csv"))

    let outcome = LibraryImporter.importLibrary(library, provenance: provenance, decode: decode) { done, total, track, measured in
        let name = (track.file as NSString).lastPathComponent
        if let measured {
            print(String(
                format: "[%2d/%d] %-10@ %6.1f LUFS  peak %5.1f dBTP  %5.0f s  %@",
                done, total, track.bucket.rawValue as NSString, measured.loudness, measured.truePeak, measured.duration, name as NSString
            ))
        } else {
            print(String(format: "[%2d/%d] %-10@ not measured  %@", done, total, track.bucket.rawValue as NSString, name as NSString))
        }
    }
    for failure in outcome.failures {
        print("  could not read \(failure.file): \(failure.reason)")
    }

    let loudness = outcome.manifest.tracks.compactMap(\.loudness)
    if let quietest = loudness.min(), let loudest = loudness.max() {
        let mean = loudness.reduce(0, +) / Double(loudness.count)
        print(String(format: "Loudness %.1f to %.1f LUFS (mean %.1f); the player assumed -16.", quietest, loudest, mean))
    }
    let unlicensed = outcome.manifest.tracks.filter { $0.license == nil }.count
    if unlicensed > 0 {
        print("\(unlicensed) tracks have no license recorded.")
    }

    if dryRun {
        print("Dry run: library.json not written.")
    } else {
        let manifestURL = folder.appendingPathComponent(LibraryManifest.fileName)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: manifestURL.path) {
            let backup = folder.appendingPathComponent(LibraryManifest.fileName + ".bak")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: manifestURL, to: backup)
        }
        try outcome.manifest.jsonData().write(to: manifestURL, options: .atomic)
        // Check that the player reads it back.
        let reloaded = try MusicLibrary.load(from: folder)
        print(String(format: "Wrote %@ (%d tracks) in %.1f s.", manifestURL.path, reloaded.tracks.count, Date().timeIntervalSince(started)))
    }
} catch {
    print("lofi-import: \(error)")
    exit(1)
}
