// LOFI-FORK: the podcasts section's player rules (see FORK.md).
//
// The pure rules of playing and how times read, with the same numbers as PodcastKit's
// PodcastPlayback. Nothing here touches the native player or the database.
import type { StoredEpisode } from "./library"

export const SKIP_BACK_SECONDS = 10
export const SKIP_AHEAD_SECONDS = 45
export const SAVE_EVERY_MS = 15_000
const PLAYED_WITHIN_SECONDS = 5
const RESTART_WITHIN_SECONDS = 10

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

/** The speed one step (0.1) up or down, kept inside 0.5x to 3.0x. */
export function stepSpeed(rate: number, direction: 1 | -1): number {
  return clampSpeed(rate + direction * 0.1)
}

export function clampSpeed(rate: number): number {
  if (!Number.isFinite(rate)) return 1
  return Math.min(3, Math.max(0.5, Math.round(rate * 10) / 10))
}

/** 0 for a played episode or one with under 10 seconds left; otherwise the saved place. */
export function resumeStart(
  saved: number,
  duration: number | null,
  played: boolean,
): number {
  if (played || !Number.isFinite(saved) || saved <= 0) return 0
  if (duration !== null && duration > 0) {
    if (saved >= duration || duration - saved < RESTART_WITHIN_SECONDS) return 0
  }
  return saved
}

/** Played to its end, or stopped within 5 seconds of the end. */
export function isPlayed(
  position: number,
  duration: number | null,
  reachedEnd: boolean,
): boolean {
  if (reachedEnd) return true
  if (duration === null || !(duration > 0)) return false
  return duration - position <= PLAYED_WITHIN_SECONDS
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
