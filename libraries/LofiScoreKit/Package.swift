// swift-tools-version: 6.0
//
// LofiScoreKit: spoiler-safe, tone-matched background music for readaloud books.
//
// The "text side" reads the narrated sentences out of an EPUB 3 media-overlay
// book, builds causal windows that never look past the sentence being narrated,
// and turns a window into a mood reading (LofiText, LofiMood).
// The "music side" smooths those readings into calm music decisions and plays
// them on a two-deck engine under the narration (LofiDirector, LofiAudio).
// The two halves share only the value types in `LofiScoreCore`.

import PackageDescription

// The music targets build in the Swift 5 language mode for now, because
// AVFoundation's callbacks are not yet annotated for strict concurrency. The
// player confines all of its state to one serial queue instead (LofiScheduler).
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
        .library(name: "LofiDirector", targets: ["LofiDirector"]),
        .library(name: "LofiAudio", targets: ["LofiAudio"]),
        .library(name: "LofiPlaceholders", targets: ["LofiPlaceholders"]),
        .library(name: "LofiDemoKit", targets: ["LofiDemoKit"]),
        .executable(name: "lofi-eval", targets: ["LofiEvalCLI"]),
        .executable(name: "lofi-train", targets: ["LofiTrainCLI"]),
        .executable(name: "lofi-replay", targets: ["lofi-replay"]),
        .executable(name: "lofi-placeholders", targets: ["lofi-placeholders"]),
        .executable(name: "lofi-demo", targets: ["lofi-demo"]),
    ],
    targets: [
        // Shared value types: MoodBucket, MoodReading, MoodObservation.
        .target(name: "LofiScoreCore"),

        // MARK: Text side

        // EPUB media-overlay parsing, SpoilerGuard, CausalWindow, ReadingCadence.
        // Pure Swift + Foundation so it builds and tests on Linux too.
        .target(name: "LofiText", dependencies: ["LofiScoreCore"]),

        // Mood engines. Apple-only engines are compiled behind `canImport`.
        .target(name: "LofiMood", dependencies: ["LofiScoreCore", "LofiText"]),

        // Eval harness: windows from real books, engine runs, timings.
        .executableTarget(name: "LofiEvalCLI", dependencies: ["LofiScoreCore", "LofiText", "LofiMood"]),

        // Create ML trainer for the Fast engine (macOS only; a stub elsewhere).
        .executableTarget(name: "LofiTrainCLI", dependencies: ["LofiScoreCore", "LofiMood"]),

        // MARK: Music side

        // Pure decision logic: turns noisy mood readings into calm music changes. No audio, no UI.
        .target(name: "LofiDirector", dependencies: ["LofiScoreCore"], swiftSettings: swift5),

        // The two-deck music player: mixer automation, ducking, track rotation, library.json,
        // and the AVAudioEngine backend (Apple platforms only).
        .target(name: "LofiAudio", dependencies: ["LofiScoreCore", "LofiDirector"], swiftSettings: swift5),

        // Synthesised placeholder tracks, one set per mood, so the demo works before real music exists.
        .target(
            name: "LofiPlaceholders",
            dependencies: ["LofiScoreCore", "LofiDirector", "LofiAudio"],
            swiftSettings: swift5
        ),

        // The demo: story, scripted mood source and narrator everywhere; SwiftUI app on Apple platforms.
        .target(
            name: "LofiDemoKit",
            dependencies: ["LofiScoreCore", "LofiDirector", "LofiAudio", "LofiPlaceholders"],
            swiftSettings: swift5
        ),

        .executableTarget(name: "lofi-replay", dependencies: ["LofiDirector"], swiftSettings: swift5),
        .executableTarget(
            name: "lofi-placeholders",
            dependencies: ["LofiPlaceholders", "LofiScoreCore"],
            swiftSettings: swift5
        ),
        .executableTarget(name: "lofi-demo", dependencies: ["LofiDemoKit"], swiftSettings: swift5),

        // MARK: Tests

        .testTarget(name: "LofiTextTests", dependencies: ["LofiText", "LofiScoreCore"], exclude: ["Fixtures"]),
        .testTarget(name: "LofiMoodTests", dependencies: ["LofiMood", "LofiText", "LofiScoreCore"]),
        .testTarget(
            name: "LofiDirectorTests",
            dependencies: ["LofiDirector"],
            resources: [.copy("Replays")],
            swiftSettings: swift5
        ),
        .testTarget(name: "LofiAudioTests", dependencies: ["LofiAudio"], swiftSettings: swift5),
        .testTarget(name: "LofiPlaceholdersTests", dependencies: ["LofiPlaceholders"], swiftSettings: swift5),
        .testTarget(
            name: "LofiDemoKitTests",
            dependencies: ["LofiDemoKit", "LofiAudio", "LofiDirector", "LofiScoreCore"],
            swiftSettings: swift5
        ),
    ]
)
