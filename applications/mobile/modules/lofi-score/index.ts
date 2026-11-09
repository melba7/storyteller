// LOFI-FORK: the Storyteller Lofi fork's lofi music module (see FORK.md).
import { requireOptionalNativeModule } from "expo-modules-core"

export type LofiMood =
  | "calm"
  | "cozy"
  | "playful"
  | "hopeful"
  | "melancholy"
  | "mysterious"
  | "tense"
  | "somber"
  | "romantic"
  | "dreamy"
  | "adventurous"
  | (string & {})

/** A sound of the atmosphere, as the native module names it. */
export type LofiAmbientSound =
  | "rain"
  | "heavyRain"
  | "rainIndoors"
  | "thunder"
  | "wind"
  | "strongWind"
  | "snow"
  | "fireplace"
  | "campfire"
  | "seaShore"
  | "openSea"
  | "river"
  | "dripping"
  | "forest"
  | "birdsong"
  | "nightInsects"
  | "nightForest"
  | "swamp"
  | "crowd"
  | "city"
  | "oldTown"
  | "horses"
  | "train"
  | "ship"
  | "machinery"
  | "clock"
  | (string & {})

/** The atmosphere sounds' state: quiet sounds of the scene under the voice. */
export type LofiAtmosphereStatus = {
  enabled: boolean
  /** False when this build cannot play them. */
  available: boolean
  /** The level of a sound at full, in dB under the voice. */
  levelDB: number
  defaultLevelDB: number
  levelRange: number[]
  /** Imported recordings, synthesised stand-ins, both, or nothing. */
  source: "imported" | "standIns" | "mixed" | "none"
  preparing: boolean
  /** Sounds with a recording, of `totalSounds`. */
  sounds: number
  totalSounds: number
  /** More specific sounds (church bells, a waterfall) with recordings. */
  variants?: number
  /** "personal" in your own builds, which may play personal-use recordings; "publish" in an App Store build. */
  edition?: "personal" | "publish"
  /** Short narration pauses where the sound swells or hushes: the setting, and whether this app can pause its narrator. */
  pausesEnabled?: boolean
  pausesAvailable?: boolean
  /** One-off sounds (a knock, a clap of thunder): the setting (off by default), and how many of `totalOneShots` have a recording or stand-in. */
  oneShotsEnabled?: boolean
  oneShots?: number
  totalOneShots?: number
  /** The open book has an atmosphere track. */
  track: boolean
  trackOrigin?: string
  /** The place being narrated and its sounds. Only ever the present. */
  place?: string
  playing: LofiAmbientSound[]
  /** The music has faded out for a crowd. */
  musicYielding: boolean
  chapterDip: boolean
  missingSounds: LofiAmbientSound[]
  engineRunning: boolean
  lastError?: string
}

/** The music's state, as the native module reports it. */
export type LofiMusicStatus = {
  enabled: boolean
  mutedInCar: boolean
  /** The music's level under the voice, in dB (negative: quieter than the voice). */
  musicLevelDB: number
  defaultMusicLevelDB: number
  /** The slider's range, quietest first. */
  musicLevelRange: number[]
  library: {
    /** Imported music, synthesised stand-ins, or nothing yet. */
    source: "imported" | "placeholders" | "none"
    preparing: boolean
    importedFolderName?: string
    tracks: number
    moods: { mood: LofiMood; tracks: number }[]
  }
  /** The book the narrator has loaded, if any. */
  book?: {
    id: string
    text: "off" | "waiting" | "loading" | "ready" | "unavailable"
    detail?: string
    engine?: string
    /** Claude has scored this book; its mood track is playing. */
    moodTrack: boolean
  }
  playback: {
    narrating: boolean
    sentence?: number
    estimatedRate: number
    readings: number
    /** The mood playing now. Only ever the present, never what comes next. */
    musicMood?: LofiMood
    engineRunning: boolean
    routeMuted: boolean
    recentMoods: LofiMood[]
  }
  /** Missing from builds before the atmosphere sounds. */
  atmosphere?: LofiAtmosphereStatus
  recentEvents: string[]
  lastError?: string
}

export type LofiImportSummary = {
  folderName: string
  tracks: number
  moodTracks: number
  /** True when the folder held a mood model for the phone (embedding or Core ML). */
  hasClassifier: boolean
  /** Files that were still only in iCloud and were left out. */
  notDownloaded: number
  /** Recordings from the folder's Atmosphere folder, and atmosphere tracks. */
  atmosphereRecordings?: number
  atmosphereTracks?: number
}

type LofiScoreNativeModule = {
  getStatus(): Promise<LofiMusicStatus>
  setEnabled(enabled: boolean): Promise<LofiMusicStatus>
  setMutedInCar(muted: boolean): Promise<LofiMusicStatus>
  /** null goes back to the default level. */
  setMusicLevel(level: number | null): Promise<LofiMusicStatus>
  /** Shows the Files folder picker; null when the listener cancels. */
  importMusicFolder(): Promise<LofiImportSummary | null>
  removeImportedMusic(): Promise<LofiMusicStatus>
  /** The imported music's CREDITS.md, or null when it had none. */
  getMusicCredits(): Promise<string | null>
  setAtmosphereEnabled(enabled: boolean): Promise<LofiMusicStatus>
  /** null goes back to the default level. */
  setAtmosphereLevel(level: number | null): Promise<LofiMusicStatus>
  /** Short narration pauses where the sound swells (a crowded hall, a storm breaking) or hushes. */
  setAtmospherePauses(enabled: boolean): Promise<LofiMusicStatus>
  /** One-off sounds on the sentences that say they happen. Off by default. */
  setAtmosphereOneShots(enabled: boolean): Promise<LofiMusicStatus>
  /** The imported sounds' Atmosphere/CREDITS.md, or null when they had none. */
  getAtmosphereCredits(): Promise<string | null>
}

/**
 * The native module, or null where it does not exist (Android, the web, and
 * builds without the fork's native code).
 */
export const LofiScore =
  requireOptionalNativeModule<LofiScoreNativeModule>("LofiScore")
