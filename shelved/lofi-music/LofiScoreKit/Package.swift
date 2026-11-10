// swift-tools-version: 6.0
//
// The LofiScoreKit manifest with the shelved music back in. It is the manifest
// in libraries/LofiScoreKit/Package.swift plus the music targets, and it is what
// a restore copies over that file (see ../README.md, "Bringing the music back").
//
// The "text side" reads the narrated sentences out of an EPUB 3 media-overlay
// book, builds causal windows that never look past the sentence being narrated,
// and turns a window into a mood reading (LofiText, LofiMood). The "music side"
// smooths those readings into calm music decisions and plays them on a two-deck
// engine under the narration (LofiDirector, LofiAudio). The atmosphere side
// scores each book's scenes ahead of time with Claude and plays the scene's
// sounds under the voice (LofiAtmosphere). LofiScoreHost ties them to the app.
// The sound players share the small audio utilities in LofiAudioCore.

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
        .library(name: "LofiDirector", targets: ["LofiDirector"]),
        .library(name: "LofiAudio", targets: ["LofiAudio"]),
        .library(name: "LofiPlaceholders", targets: ["LofiPlaceholders"]),
        .library(name: "LofiDemoKit", targets: ["LofiDemoKit"]),
        .library(name: "LofiAtmosphere", targets: ["LofiAtmosphere"]),
        .library(name: "LofiScoreHost", targets: ["LofiScoreHost"]),
        .executable(name: "lofi-eval", targets: ["LofiEvalCLI"]),
        .executable(name: "lofi-train", targets: ["LofiTrainCLI"]),
        .executable(name: "lofi-replay", targets: ["lofi-replay"]),
        .executable(name: "lofi-placeholders", targets: ["lofi-placeholders"]),
        .executable(name: "lofi-demo", targets: ["lofi-demo"]),
        .executable(name: "lofi-render", targets: ["lofi-render"]),
        .executable(name: "lofi-import", targets: ["lofi-import"]),
        .executable(name: "lofi-atmosphere", targets: ["lofi-atmosphere"]),
    ],
    targets: [
        // Shared value types: MoodBucket, MoodReading, MoodObservation.
        .target(name: "LofiScoreCore"),

        // MARK: Text side

        // EPUB media-overlay parsing, SpoilerGuard, CausalWindow, ReadingCadence.
        // Pure Swift + Foundation so it builds and tests on Linux too.
        .target(name: "LofiText", dependencies: ["LofiScoreCore"]),

        // Mood engines, the Claude transport and the per-book mood tracks.
        // Apple-only engines are compiled behind `canImport`.
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

        // MARK: Music side

        // Pure decision logic: turns noisy mood readings into calm music changes. No audio, no UI.
        .target(name: "LofiDirector", dependencies: ["LofiScoreCore", "LofiAudioCore"], swiftSettings: swift5),

        // The two-deck music player: mixer automation, ducking, track rotation, library.json,
        // and the AVAudioEngine backend (Apple platforms only).
        .target(
            name: "LofiAudio",
            dependencies: ["LofiScoreCore", "LofiAudioCore", "LofiDirector"],
            swiftSettings: swift5
        ),

        // Synthesised placeholder tracks, one set per mood, so the demo works before real music exists.
        .target(
            name: "LofiPlaceholders",
            dependencies: ["LofiScoreCore", "LofiAudioCore", "LofiDirector", "LofiAudio"],
            swiftSettings: swift5
        ),

        // The demo: story, scripted mood source and narrator everywhere; SwiftUI app on Apple platforms.
        .target(
            name: "LofiDemoKit",
            dependencies: ["LofiScoreCore", "LofiAudioCore", "LofiDirector", "LofiAudio", "LofiPlaceholders"],
            swiftSettings: swift5
        ),

        .executableTarget(name: "lofi-replay", dependencies: ["LofiDirector"], swiftSettings: swift5),
        .executableTarget(
            name: "lofi-placeholders",
            dependencies: ["LofiPlaceholders", "LofiScoreCore"],
            swiftSettings: swift5
        ),
        .executableTarget(name: "lofi-demo", dependencies: ["LofiDemoKit"], swiftSettings: swift5),
        // The demo story read by the Mac's voice with the music underneath, rendered to a file (macOS).
        .executableTarget(
            name: "lofi-render",
            dependencies: ["LofiDemoKit", "LofiAudio", "LofiDirector", "LofiPlaceholders", "LofiScoreCore"],
            swiftSettings: swift5
        ),
        // Measures a music folder and writes its library.json (loudness, true peak, length, provenance).
        .executableTarget(
            name: "lofi-import",
            dependencies: ["LofiDemoKit", "LofiAudio", "LofiPlaceholders", "LofiScoreCore"],
            swiftSettings: swift5
        ),

        // MARK: Atmosphere

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
        // opens each book's text, imports the sounds folder, keeps the settings. With the
        // music back it also depends on the music targets (see the README's restore steps).
        .target(
            name: "LofiScoreHost",
            dependencies: [
                "LofiScoreCore", "LofiText", "LofiMood", "LofiAudioCore", "LofiAtmosphere",
                "LofiDirector", "LofiAudio", "LofiPlaceholders",
            ],
            swiftSettings: swift5
        ),

        // MARK: Tests

        .testTarget(name: "LofiTextTests", dependencies: ["LofiText", "LofiScoreCore"], exclude: ["Fixtures"]),
        .testTarget(name: "LofiMoodTests", dependencies: ["LofiMood", "LofiText", "LofiScoreCore"]),
        .testTarget(name: "LofiAudioCoreTests", dependencies: ["LofiAudioCore"], swiftSettings: swift5),
        .testTarget(
            name: "LofiDirectorTests",
            dependencies: ["LofiDirector"],
            resources: [.copy("Replays")],
            swiftSettings: swift5
        ),
        .testTarget(name: "LofiAudioTests", dependencies: ["LofiAudio", "LofiAudioCore"], swiftSettings: swift5),
        .testTarget(name: "LofiPlaceholdersTests", dependencies: ["LofiPlaceholders"], swiftSettings: swift5),
        .testTarget(
            name: "LofiDemoKitTests",
            dependencies: ["LofiDemoKit", "LofiAudio", "LofiDirector", "LofiScoreCore"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "LofiAtmosphereTests",
            dependencies: ["LofiAtmosphere", "LofiAudioCore", "LofiMood", "LofiText"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "LofiScoreHostTests",
            dependencies: [
                "LofiScoreHost", "LofiAudioCore", "LofiText", "LofiScoreCore", "LofiAtmosphere",
                "LofiAudio", "LofiDirector",
            ],
            swiftSettings: swift5
        ),
    ]
)
