import Foundation

/// One of the player's two music decks.
public enum Deck: Int, CaseIterable, Sendable, Hashable, Codable, CustomStringConvertible {
    case a = 0
    case b = 1

    public var other: Deck { self == .a ? .b : .a }

    public var description: String { self == .a ? "A" : "B" }
}

/// A two-deck crossfader.
///
/// Position 0 is deck A alone and 1 is deck B alone. The position moves in a straight line
/// over time and the gains follow `cos` and `sin` of it (``Gain/equalPower(_:)``), so the
/// summed power stays constant through every crossfade, including one that reverses halfway.
public struct Crossfader: Sendable, Hashable {
    public private(set) var ramp = Ramp(value: 0)

    public init() {}

    public func position(at time: TimeInterval) -> Double {
        ramp.value(at: time)
    }

    public func gain(of deck: Deck, at time: TimeInterval) -> Double {
        let gains = Gain.equalPower(position(at: time))
        return deck == .a ? gains.a : gains.b
    }

    /// The deck the fader rests on or is moving toward.
    public var targetDeck: Deck {
        ramp.target >= 0.5 ? .b : .a
    }

    public func isMoving(at time: TimeInterval) -> Bool {
        ramp.isRunning(at: time)
    }

    public var endTime: TimeInterval {
        ramp.endTime
    }

    /// Moves toward `deck`. A full sweep takes `fullDuration`; a partial one (a reversal
    /// halfway through, say) takes proportionally less, so the speed stays the same.
    public mutating func move(toward deck: Deck, fullDuration: TimeInterval, at time: TimeInterval) {
        let target: Double = deck == .a ? 0 : 1
        let distance = abs(target - position(at: time))
        ramp.go(to: target, over: fullDuration * distance, at: time, shape: .linear)
    }

    /// Jumps to `deck` at once. Only for when nothing is audible.
    public mutating func snap(to deck: Deck, at time: TimeInterval) {
        ramp.jump(to: deck == .a ? 0 : 1, at: time)
    }
}
