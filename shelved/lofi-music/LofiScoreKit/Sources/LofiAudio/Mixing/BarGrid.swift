import Foundation

/// A track's bars, so crossfades can start on a bar line instead of mid-phrase.
public struct BarGrid: Sendable, Hashable {
    public var bpm: Double
    public var beatsPerBar: Int
    /// Seconds into the track of the first downbeat.
    public var downbeat: TimeInterval

    /// Returns nil when `bpm` is missing or implausible.
    public init?(bpm: Double?, beatsPerBar: Int = 4, downbeat: TimeInterval = 0) {
        guard let bpm, bpm.isFinite, bpm >= 30, bpm <= 300, beatsPerBar > 0 else { return nil }
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.downbeat = max(0, downbeat)
    }

    public var barLength: TimeInterval {
        Double(beatsPerBar) * 60 / bpm
    }

    /// Seconds from `position` to the next bar line; 0 when `position` is on one.
    public func delayToNextBar(from position: TimeInterval) -> TimeInterval {
        if position < downbeat { return downbeat - position }
        let bars = (position - downbeat) / barLength
        let next = (bars - 1e-6).rounded(.up)
        return max(0, downbeat + next * barLength - position)
    }

    /// The last bar line at or before `position` (the downbeat if `position` is earlier).
    public func barLine(atOrBefore position: TimeInterval) -> TimeInterval {
        guard position > downbeat else { return downbeat }
        let bars = ((position - downbeat) / barLength + 1e-6).rounded(.down)
        return downbeat + bars * barLength
    }
}
