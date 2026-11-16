// swift-tools-version: 6.0
//
// PodcastKit: what the Storyteller Lofi fork's podcasts section needs that is not
// screens. For now that is the feed reader (PodcastFeed): it turns an RSS feed
// into a show and its episodes. Pure Swift and Foundation, so it builds and
// tests on Linux too.

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
    ],
    targets: [
        // RSS 2.0 with the iTunes tags: the show, its episodes, durations, dates and notes.
        .target(name: "PodcastFeed"),
        .testTarget(name: "PodcastFeedTests", dependencies: ["PodcastFeed"]),
    ]
)
