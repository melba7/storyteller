// swift-tools-version: 6.0
//
// PodcastKit: what the Storyteller Lofi fork's podcasts section needs that is not
// screens. That is the feed reader (PodcastFeed), which turns an RSS feed into a
// show and its episodes, the player's rules (PodcastPlayback), and the downloads' files
// and bookkeeping (PodcastDownloads). Pure Swift and Foundation, so it builds and tests
// on Linux too.

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
    ]
)
