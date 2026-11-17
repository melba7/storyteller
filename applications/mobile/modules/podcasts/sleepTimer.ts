// LOFI-FORK: the podcasts section's sleep timer (see FORK.md).
//
// The pure parts the screens need: reading what Swift says, how long is left, and the words
// on the button. The timer itself runs in Swift (PodcastPlayback's SleepTimer), so it works
// with the screen locked.
import type { SleepTimerState } from "./index"
import { formatTime } from "./playbackRules"

export const SLEEP_PRESET_MINUTES = [5, 10, 15, 30, 45, 60] as const
export const SLEEP_LONGEST_MINUTES = 720
/** The same five minutes as Swift's "Add 5 minutes". */
export const SLEEP_EXTRA_MINUTES = 5

export const NO_SLEEP_TIMER: SleepTimerState = { kind: "none" }

/** What Swift sent, or "none" for anything that is not a timer. */
export function readSleepState(value: unknown): SleepTimerState {
  if (typeof value !== "object" || value === null) return NO_SLEEP_TIMER
  const record = value as Record<string, unknown>
  if (record["kind"] === "endOfEpisode") return { kind: "endOfEpisode" }
  const chapterEnd = record["chapterEnd"]
  if (
    record["kind"] === "endOfChapter" &&
    typeof chapterEnd === "number" &&
    Number.isFinite(chapterEnd)
  ) {
    return { kind: "endOfChapter", chapterEnd }
  }
  const endsAt = record["endsAt"]
  if (
    record["kind"] === "countdown" &&
    typeof endsAt === "number" &&
    Number.isFinite(endsAt)
  ) {
    return { kind: "countdown", endsAt }
  }
  return NO_SLEEP_TIMER
}

/** Whole minutes from 1 to 720 typed by the listener, or null. */
export function parseCustomMinutes(text: string): number | null {
  const trimmed = text.trim()
  if (!/^\d{1,4}$/.test(trimmed)) return null
  const minutes = Number(trimmed)
  return minutes >= 1 && minutes <= SLEEP_LONGEST_MINUTES ? minutes : null
}

/**
 * Seconds of listening left on the timer, or null with no timer. For the end of the episode
 * it is what is left of the episode at the current speed (null while the length is unknown);
 * for the end of the chapter, what is left of the chapter.
 */
export function sleepSecondsLeft(
  state: SleepTimerState,
  now: number,
  position: number,
  duration: number | null,
  rate: number,
): number | null {
  if (state.kind === "countdown")
    return Math.max(0, (state.endsAt - now) / 1000)
  if (state.kind === "endOfEpisode") {
    if (duration === null || !(duration > 0) || !(rate > 0)) return null
    return Math.max(0, (duration - position) / rate)
  }
  if (state.kind === "endOfChapter") {
    if (!(rate > 0)) return null
    return Math.max(0, (state.chapterEnd - position) / rate)
  }
  return null
}

/** The short text on the moon button: the time left, "End" while that is unknown, or none. */
export function sleepButtonText(left: number | null, state: SleepTimerState) {
  if (state.kind === "none") return ""
  return left === null ? "End" : formatTime(left)
}

/** What VoiceOver says for the moon button. */
export function sleepButtonLabel(
  left: number | null,
  state: SleepTimerState,
): string {
  if (state.kind === "none") return "Sleep timer, off"
  if (state.kind === "endOfEpisode") {
    return left === null
      ? "Sleep timer, at the end of the episode"
      : `Sleep timer, at the end of the episode, ${formatTime(left)} left`
  }
  if (state.kind === "endOfChapter") {
    return `Sleep timer, at the end of the chapter, ${formatTime(left ?? 0)} left`
  }
  return `Sleep timer, ${formatTime(left ?? 0)} left`
}

/** "5 minutes", "1 hour", "90 minutes". */
export function minutesLabel(minutes: number): string {
  if (minutes === 60) return "1 hour"
  return minutes === 1 ? "1 minute" : `${minutes} minutes`
}
