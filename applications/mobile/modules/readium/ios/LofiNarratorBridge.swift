// LOFI-FORK: this whole file belongs to the Storyteller Lofi fork (see FORK.md). It adds
// read-only hooks to the audiobook player so the lofi music module (modules/lofi-score)
// can follow the narration. It changes nothing the player does: it only registers more
// observers, using the player's own observer lists, and reads its current state.
//
// It lives in the Readium module because `Track` and most observer methods are internal
// to it. Upstream code never refers to anything here.

import Foundation
import ReadiumShared

/// One media-overlay clip, as the lofi module needs it.
public struct LofiNarratorClip: Sendable {
    /// The content document (`OverlayPar.textResource`).
    public let textResource: String
    public let fragmentId: String
    /// The audio file, relative to the book (`OverlayPar.relativeUrl`).
    public let audioResource: String
    /// The clip's start and end in that file, in seconds.
    public let start: Double
    public let end: Double
    /// Where playback is inside the clip, when it was read from the player's position
    /// rather than from a clip boundary (resuming in the middle of a sentence).
    public let playbackPosition: Double?

    init(_ clip: OverlayPar, playbackPosition: Double? = nil) {
        textResource = clip.textResource
        fragmentId = clip.fragmentId
        audioResource = clip.relativeUrl.relativeString
        start = clip.start
        end = clip.end
        self.playbackPosition = playbackPosition
    }
}

/// The book file the narrator just loaded.
public struct LofiNarratorTrack: Sendable {
    public let bookUuid: String
    /// The audio file on disk.
    public let fileURL: URL
}

/// What the narrator is doing right now.
public struct LofiNarratorState: Sendable {
    public let track: LofiNarratorTrack
    public let isPlaying: Bool
    public let clip: LofiNarratorClip?
}

extension AudiobookPlayerActor {
    /// Registers the lofi module's observers. Callbacks run on this actor, in the order the
    /// player emits its events; keep them quick (the lofi module hands them to its own queue).
    public func lofiObserve(
        track trackLoaded: @escaping @Sendable (LofiNarratorTrack) -> Void,
        playing playingChanged: @escaping @Sendable (_ isPlaying: Bool, _ clip: LofiNarratorClip?) -> Void,
        clip clipStarted: @escaping @Sendable (LofiNarratorClip) -> Void
    ) {
        observeTrackChanged { track, _, _ in
            trackLoaded(LofiNarratorTrack(bookUuid: track.bookUuid, fileURL: track.uri.url))
        }
        observeIsPlayingChanged { isPlaying in
            // Playing again does not emit a clip change unless the player rewound, so pass
            // where it is now, inside the current clip.
            let clip = isPlaying ? self.getCurrentClip().map { LofiNarratorClip($0, playbackPosition: self.getPosition()) } : nil
            playingChanged(isPlaying, clip)
        }
        observeClipChanged { clip, _ in
            clipStarted(LofiNarratorClip(clip))
        }
    }

    /// The narrator's current book, play state and clip, if a book is loaded. For a module
    /// that starts after playback has begun.
    public func lofiState() -> LofiNarratorState? {
        guard let track = getCurrentTrack() else { return nil }
        return LofiNarratorState(
            track: LofiNarratorTrack(bookUuid: track.bookUuid, fileURL: track.uri.url),
            isPlaying: getIsPlaying(),
            clip: getCurrentClip().map { LofiNarratorClip($0, playbackPosition: getPosition()) }
        )
    }
}
