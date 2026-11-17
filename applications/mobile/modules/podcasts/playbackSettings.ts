// LOFI-FORK: the podcasts section's playback settings (see FORK.md).
//
// The pure parts: what the settings are, the choices, and how stored values are read. The
// settings live in Swift (PodcastPlayback's PlaybackSettings, kept in UserDefaults) because the
// player uses them with the screen locked; playbackSettingsStore.ts talks to it.

export type HeadphoneNext = "skip" | "nextEpisode"

export type PlaybackSettings = {
  /** Seconds the back button jumps. */
  skipBack: number
  /** Seconds the forward button jumps. */
  skipForward: number
  /** What the headphones' next button does. Previous always skips back. */
  headphoneNext: HeadphoneNext
  /** Mark an episode played when this many seconds are left; 0 is off. */
  markPlayedWhenLeft: number
  /** Go back 3 seconds after a 5-minute pause and 10 after an hour. */
  rewindAfterPause: boolean
}

export const SKIP_CHOICES = [5, 10, 15, 30, 45, 60] as const
export const MARK_PLAYED_CHOICES = [0, 10, 30, 60] as const

/** What the player used before there were settings. */
export const DEFAULT_PLAYBACK_SETTINGS: PlaybackSettings = {
  skipBack: 10,
  skipForward: 45,
  headphoneNext: "skip",
  markPlayedWhenLeft: 0,
  rewindAfterPause: false,
}

function oneOf<T extends number>(
  value: unknown,
  choices: readonly T[],
  fallback: T,
): T {
  return choices.find((choice) => choice === value) ?? fallback
}

/** Stored values; anything missing or not one of the choices keeps its default. */
export function parsePlaybackSettings(value: unknown): PlaybackSettings {
  const defaults = DEFAULT_PLAYBACK_SETTINGS
  if (typeof value !== "object" || value === null) return defaults
  const record = value as Record<string, unknown>
  return {
    skipBack: oneOf(record["skipBack"], SKIP_CHOICES, defaults.skipBack),
    skipForward: oneOf(
      record["skipForward"],
      SKIP_CHOICES,
      defaults.skipForward,
    ),
    headphoneNext:
      record["headphoneNext"] === "nextEpisode" ? "nextEpisode" : "skip",
    markPlayedWhenLeft: oneOf(
      record["markPlayedWhenLeft"],
      MARK_PLAYED_CHOICES,
      defaults.markPlayedWhenLeft,
    ),
    rewindAfterPause: record["rewindAfterPause"] === true,
  }
}

/** "5 s", "1 min". */
export function secondsLabel(seconds: number): string {
  return seconds === 60 ? "1 min" : `${seconds} s`
}

/** "Off", "10 s". */
export function markPlayedLabel(seconds: number): string {
  return seconds === 0 ? "Off" : secondsLabel(seconds)
}

/** The words under the settings: what a skip button does, for VoiceOver. */
export function skipLabel(direction: "back" | "ahead", seconds: number) {
  return `${direction === "back" ? "Back" : "Ahead"} ${seconds} seconds`
}
