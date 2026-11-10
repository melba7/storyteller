import Foundation

/// Where the sound is going.
public enum OutputRoute: String, Sendable, Hashable, Codable, CaseIterable {
    case builtIn
    case wired
    case bluetooth
    case airPlay
    case carPlay
    case other
}

/// Why an audio backend wants its player to restart it.
public enum BackendRestartReason: String, Sendable, Hashable {
    /// The output hardware changed (sample rate, channels) and the engine stopped itself.
    case configurationChange
    /// An interruption (a call, Siri) ended.
    case interruptionEnded
    /// The system's media services were reset; every audio object must be rebuilt.
    case mediaServicesReset
}
