// swift-tools-version: 6.0
//
// PodcastKit: what the Storyteller Lofi fork's podcasts section needs that is not
// screens. That is the feed reader (PodcastFeed), which turns an RSS feed into a
// show and its episodes, the player's rules (PodcastPlayback), and the downloads' files
// and bookkeeping (PodcastDownloads), and the transcripts of downloaded episodes
// (PodcastTranscripts). Pure Swift and Foundation, so it builds and tests on Linux too. The
// exceptions are PodcastSpeech and podcast-transcribe, which use Apple's Speech framework
// and are empty on Linux.

import PackageDescription

let package = Package(
    name: "PodcastKit",
    platforms: [
        // The Storyteller Expo app supports iOS 16.4+.
        .iOS("16.4"),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PodcastFeed", targets: ["PodcastFeed"]),
        .library(name: "PodcastPlayback", targets: ["PodcastPlayback"]),
        .library(name: "PodcastDownloads", targets: ["PodcastDownloads"]),
        .library(name: "PodcastTranscripts", targets: ["PodcastTranscripts"]),
        .library(name: "PodcastSpeech", targets: ["PodcastSpeech"]),
        .executable(name: "podcast-transcribe", targets: ["podcast-transcribe"]),
    ],
    targets: [
        // RSS 2.0 with the iTunes tags: the show, its episodes, durations, dates and notes.
        .target(name: "PodcastFeed"),
        .testTarget(name: "PodcastFeedTests", dependencies: ["PodcastFeed"]),
        // The player's rules as plain values: speed, skips, where to resume, when an episode
        // counts as played and who owns the lock screen. No AVFoundation, so they test on Linux.
        .target(name: "PodcastPlayback"),
        .testTarget(name: "PodcastPlaybackTests", dependencies: ["PodcastPlayback"]),
        // Downloaded episodes: where the files live, the index of each episode's state, the
        // file's SHA-256 and the rules for a restart. Foundation only, so it tests on Linux.
        .target(name: "PodcastDownloads"),
        .testTarget(name: "PodcastDownloadsTests", dependencies: ["PodcastDownloads"]),
        // Transcripts: the model, the file names and storage, the line rule, the pieces and
        // the resume rules, and the run that goes through them with any recogniser. Foundation
        // only, so it tests on Linux with a fake recogniser.
        .target(name: "PodcastTranscripts"),
        .testTarget(name: "PodcastTranscriptsTests", dependencies: ["PodcastTranscripts"]),
        // The recogniser made of Apple's SpeechAnalyzer (iOS 26 and macOS 26). Empty where
        // there is no Speech framework, so the package still builds on Linux. Swift 5 mode:
        // it cannot be compiled here, and Apple's async APIs are the part most likely to
        // object to Swift 6's strict concurrency.
        .target(
            name: "PodcastSpeech", dependencies: ["PodcastTranscripts"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // `swift run podcast-transcribe <audio file>`: prints a file's transcript with times.
        .executableTarget(
            name: "podcast-transcribe", dependencies: ["PodcastSpeech", "PodcastTranscripts", "PodcastDownloads"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
