import Foundation

/// Level conversions and crossfade curves.
public enum Gain {
    /// Linear amplitude for a level in decibels. -120 dB and below is silence.
    public static func linear(fromDB decibels: Double) -> Double {
        decibels <= -120 ? 0 : pow(10, decibels / 20)
    }

    /// Level in decibels for a linear amplitude. Silence is -infinity.
    public static func decibels(fromLinear amplitude: Double) -> Double {
        amplitude <= 0 ? -.infinity : 20 * log10(amplitude)
    }

    /// Equal-power crossfade gains for a fader position from 0 (all A) to 1 (all B).
    /// `a² + b²` is always 1, so the combined loudness of two similar tracks stays level.
    public static func equalPower(_ position: Double) -> (a: Double, b: Double) {
        let p = min(1, max(0, position))
        return (cos(p * .pi / 2), sin(p * .pi / 2))
    }
}

/// How a ``Ramp`` moves between its two values.
public enum RampShape: String, Sendable, Hashable, Codable {
    /// A straight line. Used for the crossfader position and for levels in decibels.
    case linear
    /// Sine-shaped: a fade-in rises like `sin`, a fade-out falls like `cos`.
    case equalPower
}

/// A value moving from one level to another over a set time.
public struct Ramp: Sendable, Hashable {
    public private(set) var from: Double
    public private(set) var to: Double
    public private(set) var start: TimeInterval
    public private(set) var duration: TimeInterval
    public private(set) var shape: RampShape

    public init(value: Double) {
        from = value
        to = value
        start = 0
        duration = 0
        shape = .linear
    }

    /// Where the ramp is heading (or resting).
    public var target: Double { to }

    /// When the ramp arrives.
    public var endTime: TimeInterval { start + duration }

    public func value(at time: TimeInterval) -> Double {
        guard duration > 0 else { return to }
        let x = (time - start) / duration
        if x <= 0 { return from }
        if x >= 1 { return to }
        switch shape {
        case .linear:
            return from + (to - from) * x
        case .equalPower:
            if to >= from {
                return from + (to - from) * sin(x * .pi / 2)
            }
            return to + (from - to) * cos(x * .pi / 2)
        }
    }

    public func isRunning(at time: TimeInterval) -> Bool {
        duration > 0 && time < start + duration
    }

    /// Starts moving to `target` from wherever the ramp is at `time`.
    public mutating func go(to target: Double, over duration: TimeInterval, at time: TimeInterval, shape: RampShape) {
        let current = value(at: time)
        from = current
        to = target
        start = time
        self.duration = max(0, duration)
        self.shape = shape
    }

    /// Jumps straight to `value`.
    public mutating func jump(to value: Double, at time: TimeInterval) {
        from = value
        to = value
        start = time
        duration = 0
    }
}
