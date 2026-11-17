// LOFI-FORK: this whole file belongs to the Storyteller Lofi fork (see FORK.md). It lets a
// playing podcast own the lock screen and the headphone buttons. The audiobook player
// registers its lock-screen handlers once at launch, so each of them asks this file first
// (the LOFI-FORK lines in AudiobookPlayerActor.swift): while the podcast player has set a
// handler here, the command goes to the podcast and the book does nothing.
//
// It lives in the Readium module because `AudiobookPlayerActor.pause()` is internal to it.
// The podcasts module (modules/podcasts) sets and clears the handler.

import Foundation
import MediaPlayer

/// A lock-screen or headphone command, in the shape both players understand.
public enum LofiRemoteCommand: Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case skipForward(Double)
    case skipBackward(Double)
    case changePosition(Double)
}

/// Who handles the remote commands while a podcast is the active player.
public final class LofiRemoteHandoff: @unchecked Sendable {
    public static let shared = LofiRemoteHandoff()

    private let lock = NSLock()
    private var podcastHandler: (@Sendable (LofiRemoteCommand) -> MPRemoteCommandHandlerStatus)?

    /// The podcast player takes the lock screen. Replaces any earlier handler.
    public func setPodcastHandler(
        _ handler: @escaping @Sendable (LofiRemoteCommand) -> MPRemoteCommandHandlerStatus
    ) {
        lock.lock()
        podcastHandler = handler
        lock.unlock()
    }

    /// The book gets the lock screen back.
    public func clearPodcastHandler() {
        lock.lock()
        podcastHandler = nil
        lock.unlock()
    }

    /// The podcast handler's answer, or nil when no podcast is the active player and the
    /// book should handle the command itself.
    public func handle(_ command: LofiRemoteCommand) -> MPRemoteCommandHandlerStatus? {
        lock.lock()
        let handler = podcastHandler
        lock.unlock()
        return handler?(command)
    }
}

extension AudiobookPlayerActor {
    /// Pauses the book because a podcast started playing.
    public func lofiPauseForPodcast() {
        pause()
    }

    /// Whether the book is playing right now (a narration hold counts as playing).
    public func lofiIsPlaying() -> Bool {
        getIsPlaying()
    }
}
