// swift-tools-version: 6.0
//
// LofiScoreKit: spoiler-safe, tone-matched background music for readaloud books.
//
// This package holds the "text side": reading the narrated sentences out of an
// EPUB 3 media-overlay book, building causal windows that never look past the
// sentence being narrated, and turning a window into a mood reading.
// The audio engine and the director live in sibling targets added by the
// audio thread; they share only the value types in `LofiScoreCore`.

import PackageDescription

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
        .executable(name: "lofi-eval", targets: ["LofiEvalCLI"]),
        .executable(name: "lofi-train", targets: ["LofiTrainCLI"]),
    ],
    targets: [
        // Shared value types: MoodBucket, MoodReading, MoodObservation.
        .target(name: "LofiScoreCore"),

        // EPUB media-overlay parsing, SpoilerGuard, CausalWindow, ReadingCadence.
        // Pure Swift + Foundation so it builds and tests on Linux too.
        .target(name: "LofiText", dependencies: ["LofiScoreCore"]),

        // Mood engines. Apple-only engines are compiled behind `canImport`.
        .target(name: "LofiMood", dependencies: ["LofiScoreCore", "LofiText"]),

        // Eval harness: windows from real books, engine runs, timings.
        .executableTarget(name: "LofiEvalCLI", dependencies: ["LofiScoreCore", "LofiText", "LofiMood"]),

        // Create ML trainer for the Fast engine (macOS only; a stub elsewhere).
        .executableTarget(name: "LofiTrainCLI", dependencies: ["LofiScoreCore", "LofiMood"]),

        .testTarget(name: "LofiTextTests", dependencies: ["LofiText", "LofiScoreCore"], exclude: ["Fixtures"]),
        .testTarget(name: "LofiMoodTests", dependencies: ["LofiMood", "LofiText", "LofiScoreCore"]),
    ]
)
