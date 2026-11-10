import Foundation

/// How the sound changes when the story moves from one place to the next: not a plain
/// crossfade but the way it would sound to someone there. Leaving a party, the door
/// opens, the room's noise follows them out, the door shuts and it is a muffled thump
/// behind them, fading as they walk away, while the street outside has already begun.
/// Boarding a train: the carriage door, the engine, and the platform left behind.
///
/// The scorer names the transition when the passage's last sentence is the move
/// (``StoryScene/transition``). When it names none, the player infers a plain one from
/// the two scenes' settings (``inferred(from:to:)``). Each transition is a ``Timeline``
/// for the old sounds, the new ones and the ones that stay, and a few one-off sounds
/// timed to it (a door, an engine), which play when one-off sounds are on.
///
/// New cases go at the end, so saved tracks keep their meaning.
public enum SceneTransition: String, CaseIterable, Codable, Sendable, Hashable {
    /// Out of a room full of sound through a door: the door opens, the room follows them
    /// out, the door shuts on it and it fades, muffled, as they walk away.
    case leaveThroughDoor
    /// Into a room full of sound: the door opens and the room floods in, the door shuts
    /// behind them on the place they came from.
    case enterThroughDoor
    /// Out of a quiet house into the open: a door, and the outdoors is there.
    case stepOutside
    /// In from the open: a door, and the outdoors drops to a muffle behind it.
    case stepInside
    /// The same place: a door or shutter closes on a nearby noise, which goes muffled.
    case doorClosesOnNoise
    /// A window opens and the outside comes in.
    case windowOpens
    /// A window closes and the outside goes muffled.
    case windowCloses
    /// The old sound is left behind on foot, no door: a field, a beach, a long corridor,
    /// a market square crossed and gone.
    case walkAway
    /// The new sound grows nearer as they walk towards it.
    case approach
    /// Into a vehicle: a door, the engine or the horses, and the ride begins.
    case boardVehicle
    /// Out of a vehicle: the ride stops, a door, and the place outside.
    case leaveVehicle
    /// They stay where they are as a train, coach, car or ship pulls away.
    case vehicleDeparts
    /// A vehicle pulls up beside them.
    case vehicleArrives
    /// Under water: everything above is a muffled rumble.
    case diveUnder
    /// Up out of the water into the air.
    case surface
    /// The world sinks away as they fall asleep, faint, or lose consciousness.
    case fallAsleep
    /// The world comes back as they wake or come round.
    case wakeUp
    /// The crowd around them breaks up and drifts away.
    case crowdDisperses
    /// A crowd gathers around them.
    case crowdGathers
    /// A storm breaks overhead.
    case stormBreaks
    /// The rain stops and the world is suddenly quiet.
    case rainStops
    /// Everything stops at once: a shock, a spell, an engine cut.
    case suddenSilence
    /// A hard cut to the new scene: a chapter break, a jump in time.
    case quickCut

    /// When to use it, for the scorer.
    public var guidance: String {
        switch self {
        case .leaveThroughDoor: "they leave a room full of sound (a party, a hall, a tavern, a busy shop) through a door: the door opens, the noise follows them out, the door shuts on it and it fades behind them"
        case .enterThroughDoor: "they go in through a door to a room full of sound: the door opens and it floods in"
        case .stepOutside: "they step out of a quiet building into the open"
        case .stepInside: "they come in from the open into a quiet building; the outdoors drops away behind the door"
        case .doorClosesOnNoise: "in the same place, a door, shutter or hatch closes on a noise nearby, which goes muffled"
        case .windowOpens: "a window opens and the outside comes in"
        case .windowCloses: "a window closes and the outside goes muffled"
        case .walkAway: "they walk away from the old sound with no door between: across a field, down a beach, along a corridor, out of a square"
        case .approach: "they walk towards the new sound, which grows nearer"
        case .boardVehicle: "they get into or onto a vehicle (a car, a carriage, a train, a boat, a plane) and it sets off"
        case .leaveVehicle: "they get out of a vehicle that has stopped"
        case .vehicleDeparts: "they stay as a train, coach, car or ship pulls away from them"
        case .vehicleArrives: "a vehicle pulls up beside them"
        case .diveUnder: "they go under water"
        case .surface: "they come up out of the water"
        case .fallAsleep: "they fall asleep, faint or lose consciousness; the world sinks away"
        case .wakeUp: "they wake or come round; the world comes back"
        case .crowdDisperses: "the crowd around them breaks up and drifts away"
        case .crowdGathers: "a crowd gathers around them"
        case .stormBreaks: "a storm breaks overhead"
        case .rainStops: "the rain stops and the world is suddenly quiet"
        case .suddenSilence: "everything stops at once: a shock, a spell, an engine cut, a blow"
        case .quickCut: "a hard cut: a chapter break or a jump in time to somewhere else"
        }
    }

    // MARK: - Timeline

    /// What happens to the old sounds, the new ones and the ones both scenes have, in
    /// seconds from the moment the scene changes.
    public struct Timeline: Sendable, Hashable {
        public enum Leaving: Sendable, Hashable {
            /// The plain scene fade.
            case crossfade
            /// A fade of its own length.
            case fade(seconds: TimeInterval)
            /// Gone fast.
            case cut(seconds: TimeInterval)
            /// Fades over `seconds` while growing muffled (to `muffle`, 0 to 1), as a
            /// sound does with distance.
            case walkAway(seconds: TimeInterval, muffle: Double)
            /// Stays as it was until the door shuts at `closeAt`, then is muffled at once
            /// and fades over `tail`.
            case throughDoor(closeAt: TimeInterval, tail: TimeInterval)
            /// Muffled first, over `muffleOver`, then fades over `tail`.
            case muffleThenFade(muffleOver: TimeInterval, tail: TimeInterval)
        }

        public enum Arriving: Sendable, Hashable {
            /// The plain scene fade.
            case crossfade
            /// Starts after `delay`, rising over `over`.
            case after(delay: TimeInterval, over: TimeInterval)
            /// Heard muffled through the door at once, then clear and full from `openAt`
            /// over `over`.
            case throughDoor(openAt: TimeInterval, over: TimeInterval)
            /// Grows from nothing over `seconds`, as a sound does when walked towards.
            case creepIn(seconds: TimeInterval)
            /// Up fast.
            case burst(over: TimeInterval)
        }

        /// The sounds both scenes have (rain carried from street to street, the fire of a
        /// room they stay in).
        public enum Kept: Sendable, Hashable {
            case asIs
            /// Muffled from `at`, over `over`, and kept that way: the noise behind a shut
            /// door, the world from under water.
            case muffle(at: TimeInterval, over: TimeInterval)
            /// Unmuffled from `at`, over `over`.
            case unmuffle(at: TimeInterval, over: TimeInterval)
        }

        public var leaving: Leaving
        public var arriving: Arriving
        public var kept: Kept

        public init(leaving: Leaving, arriving: Arriving, kept: Kept = .asIs) {
            self.leaving = leaving
            self.arriving = arriving
            self.kept = kept
        }

        /// When the last thing in it has finished, so the player knows how long it runs.
        public var seconds: TimeInterval {
            var end: TimeInterval = 0
            switch leaving {
            case .crossfade: break
            case let .fade(seconds), let .cut(seconds): end = max(end, seconds)
            case let .walkAway(seconds, _): end = max(end, seconds)
            case let .throughDoor(closeAt, tail), let .muffleThenFade(closeAt, tail): end = max(end, closeAt + tail)
            }
            switch arriving {
            case .crossfade: break
            case let .after(delay, over), let .throughDoor(delay, over): end = max(end, delay + over)
            case let .creepIn(seconds): end = max(end, seconds)
            case let .burst(over): end = max(end, over)
            }
            switch kept {
            case .asIs: break
            case let .muffle(at, over), let .unmuffle(at, over): end = max(end, at + over)
            }
            return end
        }
    }

    public var timeline: Timeline {
        switch self {
        case .leaveThroughDoor:
            Timeline(leaving: .throughDoor(closeAt: 3, tail: 10), arriving: .after(delay: 1.5, over: 6))
        case .enterThroughDoor:
            Timeline(leaving: .throughDoor(closeAt: 3.5, tail: 3), arriving: .throughDoor(openAt: 0.3, over: 2.5))
        case .stepOutside:
            Timeline(leaving: .throughDoor(closeAt: 2.5, tail: 4), arriving: .throughDoor(openAt: 0.3, over: 3))
        case .stepInside:
            Timeline(leaving: .throughDoor(closeAt: 2.5, tail: 6), arriving: .after(delay: 0.5, over: 4))
        case .doorClosesOnNoise:
            Timeline(leaving: .throughDoor(closeAt: 0.5, tail: 4), arriving: .crossfade, kept: .muffle(at: 0.5, over: 0.4))
        case .windowOpens:
            Timeline(leaving: .crossfade, arriving: .after(delay: 0.3, over: 1.5), kept: .unmuffle(at: 0.3, over: 1.5))
        case .windowCloses:
            Timeline(leaving: .muffleThenFade(muffleOver: 0.5, tail: 4), arriving: .crossfade, kept: .muffle(at: 0.3, over: 0.5))
        case .walkAway:
            Timeline(leaving: .walkAway(seconds: 14, muffle: 0.7), arriving: .creepIn(seconds: 8))
        case .approach:
            Timeline(leaving: .fade(seconds: 10), arriving: .creepIn(seconds: 12))
        case .boardVehicle:
            Timeline(leaving: .throughDoor(closeAt: 1.5, tail: 6), arriving: .after(delay: 2, over: 6))
        case .leaveVehicle:
            Timeline(leaving: .cut(seconds: 1.5), arriving: .throughDoor(openAt: 0.5, over: 3))
        case .vehicleDeparts:
            Timeline(leaving: .fade(seconds: 12), arriving: .crossfade)
        case .vehicleArrives:
            Timeline(leaving: .crossfade, arriving: .creepIn(seconds: 5))
        case .diveUnder:
            Timeline(leaving: .muffleThenFade(muffleOver: 0.3, tail: 3), arriving: .after(delay: 0.3, over: 1.5), kept: .muffle(at: 0, over: 0.3))
        case .surface:
            Timeline(leaving: .cut(seconds: 0.8), arriving: .burst(over: 0.6), kept: .unmuffle(at: 0, over: 0.5))
        case .fallAsleep:
            Timeline(leaving: .walkAway(seconds: 12, muffle: 0.9), arriving: .after(delay: 6, over: 10), kept: .muffle(at: 0, over: 10))
        case .wakeUp:
            Timeline(leaving: .fade(seconds: 3), arriving: .creepIn(seconds: 6), kept: .unmuffle(at: 0, over: 5))
        case .crowdDisperses:
            Timeline(leaving: .walkAway(seconds: 16, muffle: 0.5), arriving: .after(delay: 4, over: 8))
        case .crowdGathers:
            Timeline(leaving: .fade(seconds: 8), arriving: .creepIn(seconds: 10))
        case .stormBreaks:
            Timeline(leaving: .fade(seconds: 3), arriving: .burst(over: 2))
        case .rainStops:
            Timeline(leaving: .fade(seconds: 5), arriving: .after(delay: 2, over: 6))
        case .suddenSilence:
            Timeline(leaving: .cut(seconds: 0.4), arriving: .after(delay: 2.5, over: 4))
        case .quickCut:
            Timeline(leaving: .cut(seconds: 1), arriving: .burst(over: 1.5))
        }
    }

    // MARK: - One-off sounds

    /// One-off sound at a time in the transition, in seconds from the change.
    public struct TimedSound: Sendable, Hashable {
        public var sound: OneShotSound
        public var at: TimeInterval

        public init(_ sound: OneShotSound, at: TimeInterval) {
            self.sound = sound
            self.at = at
        }
    }

    /// The one-off sounds that mark the transition, chosen for the scenes it goes
    /// between: a car door for a car, a carriage door for a coach, a whistle for a train.
    public func sounds(from old: StoryScene?, to new: StoryScene) -> [TimedSound] {
        let oldSounds = old?.sounds ?? []
        let newSounds = new.sounds
        func vehicle(in sounds: Set<AmbientSound>) -> AmbientSound? {
            for candidate in [AmbientSound.train, .motorVehicle, .ship, .horses, .aircraft, .spaceship] where sounds.contains(candidate) {
                return candidate
            }
            return nil
        }
        switch self {
        case .leaveThroughDoor, .enterThroughDoor, .stepOutside, .stepInside:
            let closeAt: TimeInterval
            switch self {
            case .leaveThroughDoor: closeAt = 3
            case .enterThroughDoor: closeAt = 3.5
            default: closeAt = 2.5
            }
            return [TimedSound(.doorOpen, at: 0), TimedSound(.doorClose, at: closeAt)]
        case .doorClosesOnNoise:
            return [TimedSound(.doorClose, at: 0.5)]
        case .windowOpens, .windowCloses:
            return [TimedSound(.windowSlide, at: 0.3)]
        case .boardVehicle:
            switch vehicle(in: newSounds) {
            case .motorVehicle: return [TimedSound(.carDoor, at: 0), TimedSound(.engineStart, at: 1.5)]
            case .aircraft: return [TimedSound(.engineStart, at: 1)]
            case .train: return [TimedSound(.doorClose, at: 1.5), TimedSound(.trainWhistle, at: 2.5)]
            case .ship: return [TimedSound(.shipHorn, at: 2)]
            case .spaceship: return []
            default: return [TimedSound(.doorClose, at: 1.5)]
            }
        case .leaveVehicle:
            switch vehicle(in: oldSounds) {
            case .motorVehicle: return [TimedSound(.engineStop, at: 0), TimedSound(.carDoor, at: 1.5)]
            case .spaceship: return [TimedSound(.doorOpen, at: 0.5)]
            default: return [TimedSound(.doorOpen, at: 0.5)]
            }
        case .vehicleDeparts:
            // The vehicle is usually in neither scene (they stand on the platform); the
            // place's era says what left.
            switch vehicle(in: oldSounds) ?? vehicle(in: newSounds) {
            case .train: return [TimedSound(.trainWhistle, at: 0), TimedSound(.trainPullsAway, at: 1)]
            case .motorVehicle: return [TimedSound(.carDrivesOff, at: 0.5)]
            case .ship: return [TimedSound(.shipHorn, at: 0.5)]
            case .horses: return [TimedSound(.hoovesAway, at: 0.5)]
            case .aircraft: return [TimedSound(.engineStart, at: 0.5)]
            default:
                if newSounds.contains(.oldTown) || oldSounds.contains(.oldTown) { return [TimedSound(.hoovesAway, at: 0.5)] }
                if newSounds.contains(.city) || oldSounds.contains(.city) { return [TimedSound(.carDrivesOff, at: 0.5)] }
                return []
            }
        case .vehicleArrives:
            switch vehicle(in: newSounds) ?? vehicle(in: oldSounds) {
            case .train: return [TimedSound(.trainWhistle, at: 0)]
            case .horses: return [TimedSound(.horseNeigh, at: 3)]
            case .ship: return [TimedSound(.shipHorn, at: 0)]
            default:
                if newSounds.contains(.oldTown) || oldSounds.contains(.oldTown) { return [TimedSound(.horseNeigh, at: 3)] }
                return [TimedSound(.engineStop, at: 3.5), TimedSound(.carDoor, at: 5)]
            }
        case .diveUnder, .surface:
            return [TimedSound(.splash, at: 0)]
        case .stormBreaks:
            return [TimedSound(.thunderClap, at: 0.5)]
        case .walkAway, .approach, .fallAsleep, .wakeUp, .crowdDisperses, .crowdGathers, .rainStops, .suddenSilence, .quickCut:
            return []
        }
    }

    // MARK: - Inference

    /// A plain transition for a change of place the scorer did not describe, from the
    /// two scenes' settings: a door between indoors and out (the old room's voices make
    /// it a party left, the new room's a party joined), a vehicle boarded or left, a
    /// crowd walked away from. Nil when a plain crossfade is right.
    public static func inferred(from old: StoryScene, to new: StoryScene) -> SceneTransition? {
        guard old.placeID != nil, old.placeID != new.placeID, !old.isSilent, !new.isSilent else { return nil }
        func voices(_ scene: StoryScene) -> Bool {
            scene.layers.contains { $0.sound.isVoices && $0.level >= .soft }
        }
        switch (old.setting, new.setting) {
        case (.vehicle, .vehicle): return nil
        case (.vehicle, _): return .leaveVehicle
        case (_, .vehicle): return .boardVehicle
        case (.indoors, .outdoors): return voices(old) ? .leaveThroughDoor : .stepOutside
        case (.outdoors, .indoors): return voices(new) ? .enterThroughDoor : .stepInside
        case (.indoors, .indoors):
            if voices(new) { return .enterThroughDoor }
            if voices(old) { return .leaveThroughDoor }
            return nil
        case (.outdoors, .outdoors):
            if voices(old) { return .walkAway }
            if voices(new) { return .approach }
            return nil
        default: return nil
        }
    }

    /// Accepts "leave through door", "LeaveThroughDoor" or "leave_through_door" as well as the raw value.
    public init?(lenient text: String) {
        let squashed = text.lowercased().filter { $0.isLetter }
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == squashed }) else { return nil }
        self = match
    }
}
