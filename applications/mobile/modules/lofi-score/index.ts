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
  recentEvents: string[]
  lastError?: string
}

export type LofiImportSummary = {
  folderName: string
  tracks: number
  moodTracks: number
  hasClassifier: boolean
  /** Files that were still only in iCloud and were left out. */
  notDownloaded: number
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
}

/**
 * The native module, or null where it does not exist (Android, the web, and
 * builds without the fork's native code).
 */
export const LofiScore =
  requireOptionalNativeModule<LofiScoreNativeModule>("LofiScore")
