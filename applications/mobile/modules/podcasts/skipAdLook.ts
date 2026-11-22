// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
//
// The words and numbers of the player's Skip ad button and the note it may leave. Pure, so they
// are tested without a screen.
import { SKIP_NOTE_MS } from "./ads"

export const SKIP_AD_LABEL = "Skip ad"

/** What a screen reader says for the button. */
export const SKIP_AD_ACCESSIBILITY =
  "Skip ad. Jumps past the ad that is playing."

/** The button is a capsule with a word in it, in the player's bottom row beside the icons. */
export const SKIP_AD_BUTTON = {
  height: 44,
  minWidth: 76,
  paddingX: 14,
} as const

/** What the note says when the phone knew no ad there and jumped ahead by itself. */
export const MISSED_AD_NOTE = "Jumped 30 seconds. Noted as a missed ad."

/** The note on the screen. */
export type MissedAdNote = { text: string; shownAt: number }

/**
 * The note for the answer to a tap on Skip ad (`skipAdNow`): nothing when the phone knew the
 * ad or when nothing is loaded. For a known ad the player skips it like any other skip and
 * sends `onAdSkipped`, so the usual "Skipped ad" note and its Undo come from that event, and no
 * second note is made here.
 */
export function missedAdNote(
  answer: { to: number; known: boolean } | null,
  now: number,
): MissedAdNote | null {
  if (answer === null || answer.known) return null
  return { text: MISSED_AD_NOTE, shownAt: now }
}

/** Whether the note is still to be shown at `now`: as long as the skipped-ad note stays. */
export function missedAdNoteShown(
  note: MissedAdNote | null,
  now: number,
): boolean {
  return note !== null && now - note.shownAt < SKIP_NOTE_MS
}
