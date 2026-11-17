// LOFI-FORK: the podcasts section's per-show settings (see FORK.md).
//
// What a show can be set to, as plain values: the columns they live in (schema versions 6 and
// 7), what each one may hold, and the small mirror the Swift player reads with the screen
// locked. Nothing here touches the database (dbSettings.ts does) or the native module.
import { clampSpeed } from "./playbackRules"
import {
  type BoostStrength,
  type TrimStrength,
  parseShowBoost,
  parseShowTrim,
} from "./sound"

export type AutoUpNext = "off" | "top" | "bottom"
export type AfterPlayed = "never" | "now" | "day" | "week"
export type EpisodeSort = "newest" | "oldest" | "shortest" | "longest"

export type ShowSettings = {
  /** Seconds skipped at the start of every episode, 0 to 120 in steps of 5. */
  skipIntro: number
  /** Seconds left off the end of every episode, 0 to 120 in steps of 5. */
  skipOutro: number
  /** The show's own speed, or null to follow the player's. */
  speed: number | null
  /** New episodes download by themselves (when the global switch is on too). */
  autoDownload: boolean
  /** Where a new episode goes in Up Next, if anywhere. */
  autoUpNext: AutoUpNext
  /** Notify about new episodes (the global switch is separate). */
  notify: boolean
  /** Skip ads and the hosts' own plugs: null follows the global switch. */
  skipAds: boolean | null
  skipPlugs: boolean | null
  /** Archive an episode after it was played. */
  archiveAfterPlayed: AfterPlayed
  /** Archive an unplayed episode this many days after it came out; null never. */
  archiveAfterDays: number | null
  /** Keep only the newest this many episodes; null keeps all. */
  keepNewest: number | null
  /** The show page's view. */
  sort: EpisodeSort
  groupBySeason: boolean
  showArchived: boolean
  /** The show's own voice boost and silence trimming: null follows the main setting. */
  voiceBoost: BoostStrength | null
  trimSilence: TrimStrength | null
}

export const DEFAULT_SHOW_SETTINGS: ShowSettings = {
  skipIntro: 0,
  skipOutro: 0,
  speed: null,
  autoDownload: true,
  autoUpNext: "off",
  notify: true,
  skipAds: null,
  skipPlugs: null,
  archiveAfterPlayed: "never",
  archiveAfterDays: null,
  keepNewest: null,
  sort: "newest",
  groupBySeason: false,
  showArchived: false,
  voiceBoost: null,
  trimSilence: null,
}

export const SKIP_STEP = 5
export const SKIP_MAX = 120

/** A skip length as 0 to 120 seconds in steps of 5 (anything else is rounded to one). */
export function clampSkip(seconds: number): number {
  if (!Number.isFinite(seconds)) return 0
  const stepped = Math.round(seconds / SKIP_STEP) * SKIP_STEP
  return Math.min(SKIP_MAX, Math.max(0, stepped))
}

/** The skip after one step up or down. */
export function stepSkip(seconds: number, direction: 1 | -1): number {
  return clampSkip(clampSkip(seconds) + direction * SKIP_STEP)
}

export const WEEK_DAYS = 7
/** The choices for "archive after N unplayed", in days: 1, 2, 4 and 8 weeks. */
export const UNPLAYED_DAYS = [7, 14, 28, 56] as const
/** The choices for "keep only the newest N". */
export const KEEP_NEWEST = [1, 2, 5, 10] as const

function oneOf<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fallback: T,
): T {
  return typeof value === "string" &&
    (allowed as readonly string[]).includes(value)
    ? (value as T)
    : fallback
}

function flag(value: unknown, fallback: boolean): boolean {
  if (value === null || value === undefined) return fallback
  return value === 1 || value === true
}

function nullableFlag(value: unknown): boolean | null {
  if (value === null || value === undefined) return null
  return value === 1 || value === true
}

function numberIn(value: unknown, allowed: readonly number[]): number | null {
  return typeof value === "number" && allowed.includes(value) ? value : null
}

/** A show's settings from its database row. Missing or odd values are the defaults. */
export function showSettingsFromRow(
  row: Record<string, unknown>,
): ShowSettings {
  const d = DEFAULT_SHOW_SETTINGS
  const speed = row["speed"]
  return {
    skipIntro: clampSkip(Number(row["skip_intro"] ?? 0)),
    skipOutro: clampSkip(Number(row["skip_outro"] ?? 0)),
    speed:
      typeof speed === "number" && Number.isFinite(speed)
        ? clampSpeed(speed)
        : null,
    autoDownload: flag(row["auto_download"], d.autoDownload),
    autoUpNext: oneOf(
      row["auto_up_next"],
      ["off", "top", "bottom"],
      d.autoUpNext,
    ),
    notify: flag(row["notify"], d.notify),
    skipAds: nullableFlag(row["skip_ads"]),
    skipPlugs: nullableFlag(row["skip_plugs"]),
    archiveAfterPlayed: oneOf(
      row["archive_after_played"],
      ["never", "now", "day", "week"],
      d.archiveAfterPlayed,
    ),
    archiveAfterDays: numberIn(row["archive_after_days"], UNPLAYED_DAYS),
    keepNewest: numberIn(row["keep_newest"], KEEP_NEWEST),
    sort: oneOf(
      row["episode_sort"],
      ["newest", "oldest", "shortest", "longest"],
      d.sort,
    ),
    groupBySeason: flag(row["group_by_season"], d.groupBySeason),
    showArchived: flag(row["show_archived"], d.showArchived),
    voiceBoost: parseShowBoost(row["voice_boost"]),
    trimSilence: parseShowTrim(row["trim_silence"]),
  }
}

/** The values for the shows table's setting columns, in `SETTING_COLUMNS` order. */
export function showSettingsToValues(
  settings: ShowSettings,
): (string | number | null)[] {
  const bit = (value: boolean | null) => (value === null ? null : value ? 1 : 0)
  return [
    clampSkip(settings.skipIntro),
    clampSkip(settings.skipOutro),
    settings.speed === null ? null : clampSpeed(settings.speed),
    bit(settings.autoDownload),
    settings.autoUpNext,
    bit(settings.notify),
    bit(settings.skipAds),
    bit(settings.skipPlugs),
    settings.archiveAfterPlayed,
    settings.archiveAfterDays,
    settings.keepNewest,
    settings.sort,
    bit(settings.groupBySeason),
    bit(settings.showArchived),
    settings.voiceBoost,
    settings.trimSilence,
  ]
}

export const SETTING_COLUMNS = [
  "skip_intro",
  "skip_outro",
  "speed",
  "auto_download",
  "auto_up_next",
  "notify",
  "skip_ads",
  "skip_plugs",
  "archive_after_played",
  "archive_after_days",
  "keep_newest",
  "episode_sort",
  "group_by_season",
  "show_archived",
  "voice_boost",
  "trim_silence",
] as const

/** What the Swift player reads with the screen locked (PodcastPlayback's ShowPlaybackSettings). */
export type MirroredSettings = {
  introSeconds: number
  outroSeconds: number
  speed?: number
  skipAds?: boolean
  skipPlugs?: boolean
  voiceBoost?: BoostStrength
  trimSilence?: TrimStrength
}

/**
 * The mirror of every show's playback settings, keyed by show id. A show with nothing set is
 * left out, so a reset drops it from the file.
 */
export function settingsMirror(
  shows: readonly { id: string; settings: ShowSettings }[],
): Record<string, MirroredSettings> {
  const mirror: Record<string, MirroredSettings> = {}
  for (const { id, settings } of shows) {
    const entry: MirroredSettings = {
      introSeconds: clampSkip(settings.skipIntro),
      outroSeconds: clampSkip(settings.skipOutro),
    }
    if (settings.speed !== null) entry.speed = clampSpeed(settings.speed)
    if (settings.skipAds !== null) entry.skipAds = settings.skipAds
    if (settings.skipPlugs !== null) entry.skipPlugs = settings.skipPlugs
    if (settings.voiceBoost !== null) entry.voiceBoost = settings.voiceBoost
    if (settings.trimSilence !== null) entry.trimSilence = settings.trimSilence
    const plain =
      entry.introSeconds === 0 &&
      entry.outroSeconds === 0 &&
      entry.speed === undefined &&
      entry.skipAds === undefined &&
      entry.skipPlugs === undefined &&
      entry.voiceBoost === undefined &&
      entry.trimSilence === undefined
    if (!plain) mirror[id] = entry
  }
  return mirror
}

// MARK: Reading the settings

const MINUTE = 60

/** "Off", "30 seconds", "1 minute 30 seconds"... for a skip length. */
export function skipLabel(seconds: number): string {
  if (seconds <= 0) return "Off"
  const minutes = Math.floor(seconds / MINUTE)
  const rest = seconds % MINUTE
  const parts = []
  if (minutes > 0) parts.push(minutes === 1 ? "1 minute" : `${minutes} minutes`)
  if (rest > 0) parts.push(`${rest} seconds`)
  return parts.join(" ")
}

export function upNextLabel(mode: AutoUpNext): string {
  return mode === "top" ? "Top" : mode === "bottom" ? "Bottom" : "Off"
}

export function followLabel(value: boolean | null): string {
  return value === null ? "Follow the main setting" : value ? "On" : "Off"
}

export function afterPlayedLabel(value: AfterPlayed): string {
  switch (value) {
    case "never":
      return "Never"
    case "now":
      return "Right away"
    case "day":
      return "After a day"
    case "week":
      return "After a week"
  }
}

export function afterDaysLabel(days: number | null): string {
  if (days === null) return "Never"
  const weeks = days / WEEK_DAYS
  return weeks === 1 ? "After 1 week" : `After ${weeks} weeks`
}

export function keepNewestLabel(count: number | null): string {
  return count === null ? "All episodes" : `The newest ${count}`
}
