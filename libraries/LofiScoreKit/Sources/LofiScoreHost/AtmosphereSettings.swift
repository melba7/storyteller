import Foundation
import LofiAudioCore

/// The atmosphere's settings, kept in `UserDefaults` under the `LofiScore.` prefix so they
/// never mix with the app's own preferences. The keys are the ones the app has always used,
/// so an update keeps the listener's choices and the linked folder.
public final class AtmosphereSettings: @unchecked Sendable {
    /// Matches `AtmosphereConfig.levelRange`.
    public static let atmosphereLevelRange: ClosedRange<Double> = -40 ... -14
    /// Matches `AtmosphereConfig.intensityRange`.
    public static let atmosphereIntensityRange: ClosedRange<Double> = 0 ... 1

    private let defaults: UserDefaults
    private let prefix = "LofiScore."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Quiet sounds of the scene (rain, a fire, a crowd) under the narration. On by default:
    /// installing the fork is opting in. They play only for books with an atmosphere track.
    public var atmosphereEnabled: Bool {
        get { defaults.object(forKey: prefix + "atmosphereEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "atmosphereEnabled") }
    }

    /// The sounds while the listener reads a readaloud book on screen with the narration
    /// stopped, following the pages. On by default.
    public var followsReading: Bool {
        get { defaults.object(forKey: prefix + "followsReading") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "followsReading") }
    }

    /// Keep the sounds off when the narration plays through CarPlay.
    public var mutedInCar: Bool {
        get { defaults.bool(forKey: prefix + "mutedInCar") }
        set { defaults.set(newValue, forKey: prefix + "mutedInCar") }
    }

    /// Short narration pauses (under a second) where the atmosphere swells or hushes: walking
    /// into a crowded hall, a storm breaking, a door shutting on a noisy room. On by default.
    public var atmospherePausesEnabled: Bool {
        get { defaults.object(forKey: prefix + "atmospherePausesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "atmospherePausesEnabled") }
    }

    /// One-off sounds (a knock at the door, a clap of thunder) on the sentence that says they
    /// happen. Off by default: sudden sounds are not for everyone.
    public var atmosphereOneShotsEnabled: Bool {
        get { defaults.object(forKey: prefix + "atmosphereOneShotsEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: prefix + "atmosphereOneShotsEnabled") }
    }

    /// The atmosphere's level under the voice, in dB, if the listener moved the slider. Nil
    /// means the player's default, which may change between versions.
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

    /// How much is going on in the atmosphere, 0 to 1 (how many of a scene's sounds play,
    /// how far the quieter ones sit back, how much the bed lifts in the narration's gaps),
    /// if the listener moved the dial. Nil means the player's default.
    public var atmosphereIntensity: Double? {
        get { defaults.object(forKey: prefix + "atmosphereIntensity") as? Double }
        set {
            if let newValue {
                let range = Self.atmosphereIntensityRange
                defaults.set(min(range.upperBound, max(range.lowerBound, newValue)), forKey: prefix + "atmosphereIntensity")
            } else {
                defaults.removeObject(forKey: prefix + "atmosphereIntensity")
            }
        }
    }

    /// The name of the folder the sounds were last imported from, for the settings screen.
    public var importedFolderName: String? {
        get { defaults.string(forKey: prefix + "importedFolderName") }
        set { defaults.set(newValue, forKey: prefix + "importedFolderName") }
    }

    /// The sounds folder the app keeps up to date with (a security-scoped bookmark of the
    /// folder picked in Files), or nil when none is linked. See
    /// ``LofiAtmosphereHost/syncSoundsFolder(reason:)``.
    public var linkedFolderBookmark: Data? {
        get { defaults.data(forKey: prefix + "linkedFolderBookmark") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: prefix + "linkedFolderBookmark")
            } else {
                defaults.removeObject(forKey: prefix + "linkedFolderBookmark")
            }
        }
    }

    public var linkedFolderName: String? {
        get { defaults.string(forKey: prefix + "linkedFolderName") }
        set { defaults.set(newValue, forKey: prefix + "linkedFolderName") }
    }

    /// When the linked folder was last looked at, and what that found, for the settings screen.
    public var lastSyncDate: Date? {
        get { defaults.object(forKey: prefix + "lastSyncDate") as? Date }
        set { defaults.set(newValue, forKey: prefix + "lastSyncDate") }
    }

    public var lastSyncResult: String? {
        get { defaults.string(forKey: prefix + "lastSyncResult") }
        set { defaults.set(newValue, forKey: prefix + "lastSyncResult") }
    }

    /// Routes where the sounds stay off.
    public var mutedRoutes: Set<OutputRoute> {
        mutedInCar ? [.carPlay] : []
    }
}
