// swift-tools-version: 6.0
//
// LofiScoreKit: spoiler-safe atmosphere sounds under the narration of readaloud books.
//
// The "text side" reads the narrated sentences out of an EPUB 3 media-overlay
// book, builds causal windows that never look past the sentence being narrated,
// and turns a window into a mood reading (LofiText, LofiMood). The atmosphere
// side scores each book's scenes ahead of time with Claude and plays the scene's
// sounds under the voice (LofiAtmosphere). LofiScoreHost ties them to the app.
//
// The lofi music that used to play alongside (its director, two-deck player,
// placeholder library and demo) is shelved, not deleted: see
// shelved/lofi-music/README.md at the repository root for what it was and how
// to bring it back. The small audio utilities the music and the atmosphere
// share (the clock, the scheduler, gain maths, the loudness meter, WAV files)
// stayed behind in LofiAudioCore.

import PackageDescription

// The sound targets build in the Swift 5 language mode for now, because
// AVFoundation's callbacks are not yet annotated for strict concurrency. The
// players confine all of their state to one serial queue instead (LofiScheduler).
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "LofiScoreKit",
    platforms: [
        // The Storyteller Expo app supports iOS 16.4+. Engines that need newer
        // OS features (NLContextualEmbedding, Foundation Models) check
        // availability at runtime.
        .iOS("16.4"),
        .macOS(.v13),
    ],
    products: [
        .library(name: "LofiScoreCore", targets: ["LofiScoreCore"]),
        .library(name: "LofiText", targets: ["LofiText"]),
        .library(name: "LofiMood", targets: ["LofiMood"]),
        .library(name: "LofiAudioCore", targets: ["LofiAudioCore"]),
        .library(name: "LofiAtmosphere", targets: ["LofiAtmosphere"]),
        .library(name: "LofiScoreHost", targets: ["LofiScoreHost"]),
        .executable(name: "lofi-eval", targets: ["LofiEvalCLI"]),
        .executable(name: "lofi-train", targets: ["LofiTrainCLI"]),
        .executable(name: "lofi-atmosphere", targets: ["lofi-atmosphere"]),
    ],
    targets: [
        // Shared value types: MoodBucket, MoodReading, MoodObservation.
        .target(name: "LofiScoreCore"),

        // MARK: Text side

        // EPUB media-overlay parsing, SpoilerGuard, CausalWindow, ReadingCadence.
        // Pure Swift + Foundation so it builds and tests on Linux too.
        .target(name: "LofiText", dependencies: ["LofiScoreCore"]),

        // Mood engines, the Claude transport and the per-book mood tracks. The
        // atmosphere's scorer shares the transport; the mood tracks themselves
        // wait for the music's return. Apple-only engines are compiled behind `canImport`.
        .target(name: "LofiMood", dependencies: ["LofiScoreCore", "LofiText"]),

        // Eval harness: windows from real books, engine runs, timings.
        .executableTarget(name: "LofiEvalCLI", dependencies: ["LofiScoreCore", "LofiText", "LofiMood"]),

        // Create ML trainer for the Fast engine (macOS only; a stub elsewhere).
        .executableTarget(name: "LofiTrainCLI", dependencies: ["LofiScoreCore", "LofiMood"]),

        // MARK: Sound

        // What any sound player under the narration needs: a clock, a serial scheduler
        // that is also the player's lock, gain and ramp maths, the output route, a stereo
        // buffer with a loudness meter and a WAV writer, and a seedable random generator.
        .target(name: "LofiAudioCore", swiftSettings: swift5),

        // Ambient sounds under the voice: the scene at each sentence (scored ahead of time
        // by Claude into a per-book atmosphere track, with a memory of the places met so
        // far), a director that holds a scene until the story moves on, and a layered
        // player that loops recordings seamlessly under the voice. Synthesised stand-ins
        // until real recordings are imported.
        .target(
            name: "LofiAtmosphere",
            dependencies: ["LofiScoreCore", "LofiText", "LofiMood", "LofiAudioCore"],
            swiftSettings: swift5
        ),
        // Scores a book's atmosphere track with Claude, prints a track's scenes, writes
        // the synthesised stand-in sounds.
        .executableTarget(
            name: "lofi-atmosphere",
            dependencies: ["LofiAtmosphere", "LofiText", "LofiMood"],
            swiftSettings: swift5
        ),

        // MARK: App integration

        // What the Storyteller app's native module drives: follows the narrator's events,
        // opens each book's text, imports the sounds folder, keeps the settings. LofiMood
        // only for the sentence digests that match a track to its book.
        .target(
            name: "LofiScoreHost",
            dependencies: ["LofiScoreCore", "LofiText", "LofiMood", "LofiAudioCore", "LofiAtmosphere"],
            swiftSettings: swift5
        ),

        // MARK: Tests

        .testTarget(name: "LofiTextTests", dependencies: ["LofiText", "LofiScoreCore"], exclude: ["Fixtures"]),
        .testTarget(name: "LofiMoodTests", dependencies: ["LofiMood", "LofiText", "LofiScoreCore"]),
        .testTarget(name: "LofiAudioCoreTests", dependencies: ["LofiAudioCore"], swiftSettings: swift5),
        .testTarget(
            name: "LofiAtmosphereTests",
            dependencies: ["LofiAtmosphere", "LofiAudioCore", "LofiMood", "LofiText"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "LofiScoreHostTests",
            dependencies: ["LofiScoreHost", "LofiAudioCore", "LofiText", "LofiScoreCore", "LofiAtmosphere"],
            swiftSettings: swift5
        ),
    ]
)
