// LOFI-FORK: the podcasts section's player rules (see FORK.md).
//
// The pure rules of playing and how times read, with the same numbers as PodcastKit's
// PodcastPlayback. Nothing here touches the native player or the database.
import { type StoredEpisode, formatDuration } from "./library"

export const SKIP_BACK_SECONDS = 10
export const SKIP_AHEAD_SECONDS = 45
export const SAVE_EVERY_MS = 15_000
const PLAYED_WITHIN_SECONDS = 5

/** "0:05", "12:34", "1:02:03". Not a number or negative reads as "0:00". */
export function formatTime(seconds: number): string {
  const whole = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0
  const hours = Math.floor(whole / 3600)
  const minutes = Math.floor((whole % 3600) / 60)
  const rest = String(whole % 60).padStart(2, "0")
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${rest}`
    : `${minutes}:${rest}`
}

/** "-12:34", the time left as Pocket Casts shows it. "--:--" when the length is unknown. */
export function timeLeft(position: number, duration: number | null): string {
  if (duration === null || !Number.isFinite(duration) || duration <= 0) {
    return "--:--"
  }
  return `-${formatTime(Math.max(0, duration - position))}`
}

/** "1.0x", "1.5x". */
export function speedLabel(rate: number): string {
  return `${rate.toFixed(1)}x`
}

/** What VoiceOver reads for the mini player's open button: the title and the time left. */
export function miniPlayerLabel(
  title: string,
  position: number,
  duration: number | null,
): string {
  const left =
    duration === null ? "" : formatDuration(Math.max(0, duration - position))
  return left === ""
    ? `Open the player, ${title}`
    : `Open the player, ${title}, ${left} left`
}

/** The speed one step (0.1) up or down, kept inside 0.5x to 3.0x. */
export function stepSpeed(rate: number, direction: 1 | -1): number {
  return clampSpeed(rate + direction * 0.1)
}

export function clampSpeed(rate: number): number {
  if (!Number.isFinite(rate)) return 1
  return Math.min(3, Math.max(0.5, Math.round(rate * 10) / 10))
}

/**
 * 0 for a played episode or a place that is not a usable number; otherwise the saved place,
 * never later. The length does not decide: a feed's length is often shorter than the real
 * audio, and the listener's place past it must not be thrown away. The length stays in the
 * signature (unused), like Swift's `ResumeRule.start`, so no caller changes.
 */
export function resumeStart(
  saved: number,
  _duration: number | null,
  played: boolean,
): number {
  if (played || !Number.isFinite(saved) || saved <= 0) return 0
  return saved
}

/**
 * Played to its end, or stopped within 5 seconds of the end. `within` is the listener's
 * "mark played when this many seconds are left" (0 is off); it never shrinks the 5 seconds.
 */
export function isPlayed(
  position: number,
  duration: number | null,
  reachedEnd: boolean,
  within = 0,
): boolean {
  if (reachedEnd) return true
  if (duration === null || !(duration > 0)) return false
  return duration - position <= Math.max(within, PLAYED_WITHIN_SECONDS)
}

/** One save of the listener's place, as far as a list could show it. */
export type ListenSave = {
  episodeId: string
  position: number
  played: boolean
}

/**
 * Whether a save of the place tells the lists to read the library again. The lists show the
 * time left in whole minutes, so a timed save (every 15 seconds) inside the same minute
 * would only make every open screen load and draw again for nothing. Any other save (a
 * pause, a seek, a skip, another episode) always tells them, and so does a timed save that
 * changes the episode, the played mark, or whether the episode was started at all. `before` is the last save the
 * lists were told about, or null when they were told about none.
 */
export function shouldNotifyListen(
  before: ListenSave | null,
  after: ListenSave,
  timed: boolean,
): boolean {
  if (!timed || before === null) return true
  if (before.episodeId !== after.episodeId || before.played !== after.played) {
    return true
  }
  // An episode that was never started is told apart from one in progress ("Resume", the
  // Up Next shelf, a playlist of unplayed ones), so leaving place 0 tells the lists too.
  if (before.position > 0 !== after.position > 0) return true
  // A position that is not a number never equals itself, so it tells the lists too.
  return Math.floor(before.position / 60) !== Math.floor(after.position / 60)
}

/** The mini player shows when an episode is loaded or one was played before. */
export function showsMiniPlayer(
  loaded: StoredEpisode | null,
  lastPlayed: StoredEpisode | null,
): boolean {
  return loaded !== null || lastPlayed !== null
}

/** A position kept inside the episode (only 0 is a limit while the length is unknown). */
export function clampPosition(position: number, duration: number | null) {
  const floor = Math.max(0, Number.isFinite(position) ? position : 0)
  return duration !== null && duration > 0 ? Math.min(floor, duration) : floor
}
