// LOFI-FORK: this whole file belongs to the Storyteller Lofi fork (see FORK.md). It adds
// hooks to the audiobook player so the lofi music module (modules/lofi-score) can follow
// the narration: more observers, using the player's own observer lists, and reads of its
// current state. The one thing it does to playback is the narration hold at the end of
// this file, which the atmosphere asks for and which the few LOFI-FORK lines in
// AudiobookPlayerActor.swift keep invisible to the rest of the app.
//
// It lives in the Readium module because `Track` and most observer methods are internal
// to it. Upstream code refers only to the hold's hooks.

import AVFoundation
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

// MARK: - Narration hold

/// What a narration hold reports to whoever asked for it.
public enum LofiNarrationHoldEvent: Sendable {
    /// The narrator stopped at the end of the clip: the atmosphere can swell.
    case began
    /// The narrator carries on, or the listener paused during the hold.
    case ended
    /// The hold never started: a pause, a seek past the clip's end, a call.
    case dropped
}

/// The one hold there can be at a time. Touched only from the player actor's methods.
final class LofiNarrationHold: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        /// Waiting for the narrator to reach the end of the clip.
        case armed(Int)
        /// The narrator is stopped; everyone else still sees it playing.
        case holding(Int)
        /// The rate is restored; waiting for the player to report playing again.
        case resuming(Int)
    }

    static let shared = LofiNarrationHold()

    var phase = Phase.idle
    var token = 0
    var seconds = 0.5
    var boundary: Any?
    weak var boundaryPlayer: AVPlayer?
    var onEvent: (@Sendable (LofiNarrationHoldEvent) -> Void)?
    var watchingInterruptions = false
}

extension AudiobookPlayerActor {
    /// Stops the narration for `seconds` (0.3 to 1.5) at the end of the clip playing now,
    /// then carries on, so the atmosphere can swell in the gap. The rest of the app never
    /// sees a pause: no isPlaying change, no lock-screen change, no automatic rewind.
    ///
    /// Returns false, and does nothing, when the narrator is not playing, a hold is already
    /// pending, the clip is the last of its audio file (no hold across files) or it ends
    /// too soon. A hold that was accepted can still be dropped before it starts (`.dropped`).
    /// A pause, the sleep timer or a call during the hold ends it (`.ended`) and the app then
    /// sees the pause; play ends it early; a seek or a file change during it carries on when
    /// it ends.
    public func lofiHoldAfterCurrentClip(
        seconds: Double,
        onEvent: @escaping @Sendable (LofiNarrationHoldEvent) -> Void
    ) -> Bool {
        let hold = LofiNarrationHold.shared
        let player = lofiPlayer
        guard hold.phase == .idle, player.timeControlStatus == .playing,
              let track = getCurrentTrack(), let clip = getCurrentClip(),
              let last = lofiClips(relativeUri: track.relativeUri.string).last, last.start > clip.start
        else { return false }
        let now = getPosition()
        // Just inside the clip's end, in the silence after the sentence.
        let at = clip.end - 0.03
        guard now.isFinite, at - now >= 0.15 else { return false }

        hold.token += 1
        let token = hold.token
        hold.seconds = min(1.5, max(0.3, seconds))
        hold.onEvent = onEvent
        hold.phase = .armed(token)
        hold.boundaryPlayer = player
        hold.boundary = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: at, preferredTimescale: 1000))],
            queue: .main
        ) {
            Task { await AudiobookPlayerActor.shared.lofiBeginHold(token) }
        }
        lofiWatchInterruptions()
        // A hold the narrator never reaches (a seek past it) lapses.
        let wait = (at - now) / max(0.5, lofiPlaybackRate) + 2
        Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await AudiobookPlayerActor.shared.lofiDropArmedHold(token)
        }
        return true
    }

    /// For `play`: carries on at once when a hold has stopped the narrator (a double tap on
    /// a sentence, or play from another app), without the automatic rewind a real pause
    /// would get. Returns false, doing nothing, when there is no hold.
    func lofiResumeHeldNarration() -> Bool {
        guard case let .holding(token) = LofiNarrationHold.shared.phase else { return false }
        lofiFinishHold(token)
        return true
    }

    /// The narrator is stopped by a hold or not yet playing again after one: for
    /// `getIsPlaying()`, which reports it as playing.
    var lofiHoldIsActive: Bool {
        switch LofiNarrationHold.shared.phase {
        case .holding, .resuming: return true
        case .idle, .armed: return false
        }
    }

    /// For the player's isPlaying observer: true when this change of the player's state is
    /// the hold's own (stopping, or starting again), which the app must not see.
    func lofiHoldOwnsPlayerState() -> Bool {
        let hold = LofiNarrationHold.shared
        switch hold.phase {
        case .holding:
            return true
        case .resuming:
            switch lofiPlayer.timeControlStatus {
            case .playing:
                hold.phase = .idle
                return true
            case .waitingToPlayAtSpecifiedRate:
                return true
            default:
                // Starting again failed; let the app see the pause.
                hold.phase = .idle
                return false
            }
        case .idle, .armed:
            return false
        }
    }

    /// Ends a hold without starting the narrator again. Returns true when the narrator was
    /// held, so the caller reports the pause the app has not seen yet.
    func lofiEndHold() -> Bool {
        let hold = LofiNarrationHold.shared
        switch hold.phase {
        case .idle:
            return false
        case .armed:
            lofiRemoveHoldBoundary()
            hold.phase = .idle
            hold.onEvent?(.dropped)
            return false
        case .holding:
            hold.phase = .idle
            hold.onEvent?(.ended)
            return true
        case .resuming:
            hold.phase = .idle
            return false
        }
    }

    func lofiBeginHold(_ token: Int) {
        let hold = LofiNarrationHold.shared
        guard hold.phase == .armed(token) else { return }
        lofiRemoveHoldBoundary()
        let player = lofiPlayer
        guard player.timeControlStatus == .playing else {
            hold.phase = .idle
            hold.onEvent?(.dropped)
            return
        }
        hold.phase = .holding(token)
        player.rate = 0
        hold.onEvent?(.began)
        let seconds = hold.seconds
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await AudiobookPlayerActor.shared.lofiFinishHold(token)
        }
    }

    func lofiFinishHold(_ token: Int) {
        let hold = LofiNarrationHold.shared
        guard hold.phase == .holding(token) else { return }
        // The current player: a file change during the hold made a new one, still stopped.
        let player = lofiPlayer
        if player.currentItem != nil {
            hold.phase = .resuming(token)
            player.rate = Float(lofiPlaybackRate)
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await AudiobookPlayerActor.shared.lofiSettleHold(token)
            }
        } else {
            hold.phase = .idle
            lofiReportPaused()
        }
        hold.onEvent?(.ended)
    }

    func lofiSettleHold(_ token: Int) {
        let hold = LofiNarrationHold.shared
        if hold.phase == .resuming(token) { hold.phase = .idle }
    }

    func lofiDropArmedHold(_ token: Int) {
        let hold = LofiNarrationHold.shared
        guard hold.phase == .armed(token) else { return }
        lofiRemoveHoldBoundary()
        hold.phase = .idle
        hold.onEvent?(.dropped)
    }

    private func lofiRemoveHoldBoundary() {
        let hold = LofiNarrationHold.shared
        if let boundary = hold.boundary {
            hold.boundaryPlayer?.removeTimeObserver(boundary)
        }
        hold.boundary = nil
        hold.boundaryPlayer = nil
    }

    /// A call or another app's audio during a hold: the system would have paused the
    /// narrator, but it is already stopped, so the app hears of the pause from here.
    private func lofiWatchInterruptions() {
        let hold = LofiNarrationHold.shared
        guard !hold.watchingInterruptions else { return }
        hold.watchingInterruptions = true
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            Task {
                let player = AudiobookPlayerActor.shared
                if await player.lofiEndHold() { await player.lofiReportPaused() }
            }
        }
    }
}
