import Foundation
import LofiAudio

/// The music's settings, kept in `UserDefaults` under the `LofiScore.` prefix so they never
/// mix with the app's own preferences.
public final class MusicSettings: @unchecked Sendable {
    public static let musicLevelRange: ClosedRange<Double> = -30 ... -4
    /// Matches `AtmosphereConfig.levelRange`.
    public static let atmosphereLevelRange: ClosedRange<Double> = -40 ... -16

    private let defaults: UserDefaults
    private let prefix = "LofiScore."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Music under the narration. On by default: installing the fork is opting in.
    public var enabled: Bool {
        get { defaults.object(forKey: prefix + "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    /// Music (and the atmosphere) while the listener reads a readaloud book on screen with
    /// the narration stopped, following the pages. On by default.
    public var followsReading: Bool {
        get { defaults.object(forKey: prefix + "followsReading") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "followsReading") }
    }

    /// Keep the music off when the narration plays through CarPlay.
    public var mutedInCar: Bool {
        get { defaults.bool(forKey: prefix + "mutedInCar") }
        set { defaults.set(newValue, forKey: prefix + "mutedInCar") }
    }

    /// The music's level under the voice, in dB, if the listener moved the slider. Nil
    /// means the player's default, which may change between versions.
    public var musicLevelDB: Double? {
        get { defaults.object(forKey: prefix + "musicLevelDB") as? Double }
        set {
            if let newValue {
                let clamped = min(Self.musicLevelRange.upperBound, max(Self.musicLevelRange.lowerBound, newValue))
                defaults.set(clamped, forKey: prefix + "musicLevelDB")
            } else {
                defaults.removeObject(forKey: prefix + "musicLevelDB")
            }
        }
    }

    /// Quiet sounds of the scene (rain, a fire, a crowd) under the narration. On by default,
    /// like the music; it plays only for books with an atmosphere track.
    public var atmosphereEnabled: Bool {
        get { defaults.object(forKey: prefix + "atmosphereEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "atmosphereEnabled") }
    }

    /// Short narration pauses (under a second) where the atmosphere swells or hushes: walking
    /// into a crowded hall, a storm breaking, a door shutting on a noisy room. On by default.
    public var atmospherePausesEnabled: Bool {
        get { defaults.object(forKey: prefix + "atmospherePausesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "atmospherePausesEnabled") }
    }

    /// The atmosphere's level under the voice, in dB, if the listener moved the slider. Nil
    /// means the player's default.
    public var atmosphereLevelDB: Double? {
        get { defaults.object(forKey: prefix + "atmosphereLevelDB") as? Double }
        set {
            if let newValue {
                let range = Self.atmosphereLevelRange
                defaults.set(min(range.upperBound, max(range.lowerBound, newValue)), forKey: prefix + "atmosphereLevelDB")
            } else {
                defaults.removeObject(forKey: prefix + "atmosphereLevelDB")
            }
        }
    }

    /// The name of the folder the music was last imported from, for the settings screen.
    public var importedFolderName: String? {
        get { defaults.string(forKey: prefix + "importedFolderName") }
        set { defaults.set(newValue, forKey: prefix + "importedFolderName") }
    }

    /// The player's ducking with the listener's level applied.
    public func ducking(base: DuckingSettings = DuckingSettings()) -> DuckingSettings {
        var ducking = base
        if let musicLevelDB { ducking.bedLevelDB = musicLevelDB }
        return ducking
    }

    /// Routes where the music stays off.
    public var mutedRoutes: Set<OutputRoute> {
        mutedInCar ? [.carPlay] : []
    }
}
