// LOFI-FORK: the Storyteller Lofi fork's atmosphere module (see FORK.md).
import { requireOptionalNativeModule } from "expo-modules-core"

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
  | "roomTone"
  | "hushedRoom"
  | "murmur"
  | "emptyHall"
  | "electricHum"
  | "kitchen"
  | "workshop"
  | "farmyard"
  | "motorVehicle"
  | "aircraft"
  | "spaceship"
  | "deepDrone"
  | (string & {})

/** The atmosphere sounds' state: quiet sounds of the scene under the voice. */
export type LofiAtmosphereStatus = {
  enabled: boolean
  /** False when this build cannot play them. */
  available: boolean
  /** The level of a sound at full, in dB under the voice. */
  levelDB: number
  defaultLevelDB: number
  /** The slider's range, quietest first. */
  levelRange: number[]
  /** How much is going on, 0 to 1: how many of a scene's sounds play, how far the quieter ones sit back, how much it lifts in the gaps between sentences. */
  intensity: number
  defaultIntensity: number
  /** Imported recordings, synthesised stand-ins, both, or nothing. */
  source: "imported" | "standIns" | "mixed" | "none"
  preparing: boolean
  /** Sounds with a recording, of `totalSounds`. */
  sounds: number
  totalSounds: number
  /** More specific sounds (church bells, a waterfall) with recordings. */
  variants: number
  /** "personal" in your own builds, which may play personal-use recordings; "publish" in an App Store build. */
  edition: "personal" | "publish"
  /** Short narration pauses where the sound swells or hushes: the setting, and whether this app can pause its narrator. */
  pausesEnabled: boolean
  pausesAvailable: boolean
  /** One-off sounds (a knock, a clap of thunder): the setting (off by default), and how many of `totalOneShots` have a recording or stand-in. */
  oneShotsEnabled: boolean
  oneShots: number
  totalOneShots: number
  /** The open book has an atmosphere track, and where it came from. */
  track: boolean
  trackOrigin?: string
  /** The place being narrated and its sounds. Only ever the present. */
  place?: string
  playing: LofiAmbientSound[]
  chapterDip: boolean
  /** Off because the narration plays through the car. */
  routeMuted: boolean
  missingSounds: LofiAmbientSound[]
  engineRunning: boolean
  lastError?: string
}

export type LofiLinkedFolder = {
  name: string
  /** Seconds since 1970, when the folder was last looked at. */
  lastSync?: number
  /** What the last look found, or why it failed. */
  lastResult?: string
  syncing: boolean
}

/** The atmosphere's state, as the native module reports it. */
export type LofiStatus = {
  mutedInCar: boolean
  /** The sounds while reading on screen with the narration stopped. */
  followsReading: boolean
  /** The imported sounds folder. */
  folder: {
    /** A folder has been imported. */
    imported: boolean
    importedFolderName?: string
    /**
     * The sounds folder the app keeps up to date with: whatever is added to it
     * (scores from the Mac, new sounds or tracks) is copied when the app opens,
     * comes back to the foreground, or opens a book without a score. Missing
     * when no folder is linked.
     */
    linkedFolder?: LofiLinkedFolder
  }
  /** The book the narrator has loaded, if any. */
  book?: {
    id: string
    text: "off" | "waiting" | "loading" | "ready" | "unavailable"
    detail?: string
  }
  playback: {
    narrating: boolean
    /** Following the pages you read on screen, with the narration stopped. */
    reading: boolean
    sentence?: number
    estimatedRate: number
  }
  atmosphere: LofiAtmosphereStatus
  recentEvents: string[]
  lastError?: string
}

/** What a look at the linked folder copied. */
export type LofiSyncSummary = {
  folderName: string
  added: number
  updated: number
  notDownloaded: number
  scores: number
  atmosphereTracks: number
  recordings: number
  /** The whole folder was imported afresh. */
  fresh: boolean
  /** One line: "New: 2 book scores, 1 sound". */
  description: string
}

export type LofiImportSummary = {
  folderName: string
  /** Recordings from the folder's Atmosphere folder. */
  recordings: number
  /** Book scores and plain atmosphere tracks. */
  scores: number
  atmosphereTracks: number
  /** Files that were still only in iCloud and were left out. */
  notDownloaded: number
}

type LofiScoreNativeModule = {
  getStatus(): Promise<LofiStatus>
  setMutedInCar(muted: boolean): Promise<LofiStatus>
  /**
   * Shows the Files folder picker, copies the sounds and keeps a link to the
   * folder; null when the listener cancels.
   */
  importSoundsFolder(): Promise<LofiImportSummary | null>
  /** Copies what is new in the linked folder now; null when none is linked. */
  syncSoundsFolder(): Promise<LofiSyncSummary | null>
  /** Forgets the linked folder; the sounds already copied stay. */
  unlinkSoundsFolder(): Promise<LofiStatus>
  /**
   * Keeps a score fetched from the server (the text of
   * `GET /api/v2/books/<id>/lofi-score`) with its book, and reads the book
   * again with it when it is the one open. Rejects when the text is not a
   * score or the book is not on the device.
   */
  installBookScore(bookUuid: string, score: string): Promise<LofiStatus>
  /** Deletes the imported sounds and forgets the linked folder. */
  removeImportedSounds(): Promise<LofiStatus>
  setAtmosphereEnabled(enabled: boolean): Promise<LofiStatus>
  /** null goes back to the default level. */
  setAtmosphereLevel(level: number | null): Promise<LofiStatus>
  /** How much is going on, 0 to 1; null goes back to the default. */
  setAtmosphereIntensity(intensity: number | null): Promise<LofiStatus>
  /** Short narration pauses where the sound swells (a crowded hall, a storm breaking) or hushes. */
  setAtmospherePauses(enabled: boolean): Promise<LofiStatus>
  /** One-off sounds on the sentences that say they happen. Off by default. */
  setAtmosphereOneShots(enabled: boolean): Promise<LofiStatus>
  /** The imported sounds' Atmosphere/CREDITS.md, or null when they had none. */
  getAtmosphereCredits(): Promise<string | null>
  /** The sounds while reading on screen with the narration stopped. */
  setFollowsReading(enabled: boolean): Promise<LofiStatus>
  /** The page you are reading now starts at this clip (as `getClip` finds it). */
  readerReached(
    bookUuid: string,
    relativeUrl: string,
    start: number,
  ): Promise<void>
  /** You stopped reading on screen (left the app or the book). */
  readerStopped(): Promise<void>
}

/**
 * The native module, or null where it does not exist (Android, the web, and
 * builds without the fork's native code).
 */
export const LofiScore =
  requireOptionalNativeModule<LofiScoreNativeModule>("LofiScore")
