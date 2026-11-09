import Foundation

/// A monotonic clock in seconds.
///
/// Everything time-dependent in LofiScoreKit reads time through this protocol, so tests
/// and replays can drive time by hand (see ``ManualClock``) and run a whole book's
/// readings in milliseconds.
public protocol LofiClock: AnyObject {
    /// Seconds since a fixed, arbitrary origin. Never goes backwards.
    var now: TimeInterval { get }
}

/// Wall-clock time that keeps counting while the device sleeps.
public final class SystemClock: LofiClock, @unchecked Sendable {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: TimeInterval {
        let elapsed = origin.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }
}

/// A clock that only moves when told to. Use it in tests and replays.
public final class ManualClock: LofiClock {
    public private(set) var now: TimeInterval

    public init(now: TimeInterval = 0) {
        self.now = now
    }

    public func advance(by seconds: TimeInterval) {
        precondition(seconds >= 0, "ManualClock cannot go backwards")
        now += seconds
    }

    public func advance(to time: TimeInterval) {
        precondition(time >= now, "ManualClock cannot go backwards")
        now = time
    }
}
