// swift-tools-version: 6.0
//
// PodcastKit: what the Storyteller Lofi fork's podcasts section needs that is not
// screens. That is the feed reader (PodcastFeed), which turns an RSS feed into a
// show and its episodes, the player's rules (PodcastPlayback), and the downloads' files
// and bookkeeping (PodcastDownloads), and the transcripts of downloaded episodes
// (PodcastTranscripts) and finding the ads in them (PodcastAds). Pure Swift and Foundation, so
// it builds and tests on Linux too. The exceptions are PodcastSpeech and podcast-transcribe,
// which use Apple's Speech framework, and PodcastAdsOnDevice and podcast-ads, which use
// Apple's Foundation Models framework; all four are empty on Linux.

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
        .library(name: "PodcastAds", targets: ["PodcastAds"]),
        .library(name: "PodcastChapters", targets: ["PodcastChapters"]),
        .library(name: "PodcastAdsOnDevice", targets: ["PodcastAdsOnDevice"]),
        .library(name: "PodcastAudioMatch", targets: ["PodcastAudioMatch"]),
        .executable(name: "podcast-transcribe", targets: ["podcast-transcribe"]),
        .executable(name: "podcast-ads", targets: ["podcast-ads"]),
        .executable(name: "podcast-teach", targets: ["podcast-teach"]),
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
            // Ads: the detector interface, the chunker, the clean-up rules and the `.ads.` files.
        // Foundation only (and the transcript's values), so it tests on Linux with a fake
        // detector.
        .target(name: "PodcastAds", dependencies: ["PodcastTranscripts"]),
        .testTarget(name: "PodcastAdsTests", dependencies: ["PodcastAds"]),
        // Chapters: the feed's JSON chapters, the ID3 chapter frames of an MP3 file, which
        // chapter is playing, the previous and next chapter and the chapters to skip. Foundation
        // only, so it tests on Linux with hand-built bytes.
        .target(name: "PodcastChapters"),
        .testTarget(name: "PodcastChaptersTests", dependencies: ["PodcastChapters"]),
        // Audio matching without decoding: cuts an MP3 file into frames (skipping the ID3 tag) and
        // lines up two downloads of one episode by frame hashes, to find what differs (inserted
        // ads). Foundation only, so it tests on Linux with hand-built bytes.
        .target(name: "PodcastAudioMatch"),
        .testTarget(name: "PodcastAudioMatchTests", dependencies: ["PodcastAudioMatch"]),
        // The detector made of Apple's on-device model (Foundation Models, iOS 26 and macOS 26).
        // Empty where there is no such framework. Swift 5 mode for the same reason as
        // PodcastSpeech: it cannot be compiled here.
        .target(
            name: "PodcastAdsOnDevice", dependencies: ["PodcastAds"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // `swift run podcast-ads <transcript or audio file>`: prints the ads in an episode.
        .executableTarget(
            name: "podcast-ads",
            dependencies: [
                "PodcastAds", "PodcastAdsOnDevice", "PodcastSpeech", "PodcastTranscripts",
                "PodcastDownloads", "PodcastAudioMatch",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // `swift run podcast-teach score|sounds <teaching folder>`: the Mac teaching run's
        // scorecard and its library of ad sounds, made with the phone's own code. Foundation
        // only, so it builds and runs on Linux too.
        .executableTarget(
            name: "podcast-teach",
            dependencies: ["PodcastAds", "PodcastAudioMatch", "PodcastTranscripts"]),
    ]
)
