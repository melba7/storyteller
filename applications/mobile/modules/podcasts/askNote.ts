// LOFI-FORK: the podcasts section's question note (see FORK.md).
//
// The phone is not sure that a stretch is an ad, so when the playhead enters it the player says
// so (`onAdAsk`) and the screen shows "Ad? Skip" with two answers. This is the rule of when the
// note is there and the store that holds it. Pure (the answer to the player is handed in), so it
// is tested without a screen or the native module.
import type { AdAsk } from "./index"

export const ASK_NOTE_TEXT = "Ad? Skip"
export const ASK_YES_LABEL = "Skip"
export const ASK_YES_ACCESSIBILITY = "Skip it, it is an ad"
export const ASK_NO_LABEL = "Not an ad"
export const ASK_NO_ACCESSIBILITY = "Not an ad, play it and do not ask again"

/**
 * The screen's clock may be a moment behind the player's, so a note is still shown this long
 * (seconds) before its stretch begins. A seek back further than that takes the note away; the
 * player asks again when the playhead gets in again.
 */
export const ASK_LEAD_SECONDS = 2

/** The question on the screen: the stretch of one episode, as `onAdAsk` sends it. */
export type AskNote = AdAsk

function isSeconds(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
}

/** The note for an `onAdAsk` event, or null when the event is not a stretch of an episode. */
export function askNoteFor(event: unknown): AskNote | null {
  if (typeof event !== "object" || event === null || Array.isArray(event)) {
    return null
  }
  const { episodeId, start, end, kind } = event as Record<string, unknown>
  if (typeof episodeId !== "string" || episodeId === "") return null
  if (!isSeconds(start) || !isSeconds(end) || end <= start) return null
  return { episodeId, start, end, kind: typeof kind === "string" ? kind : "" }
}

/**
 * Whether the note is to be shown now: the loaded episode is the one it was asked in, and the
 * playhead is in the stretch (from a moment before its start, up to but not including its end).
 */
export function askNoteShown(
  note: AskNote | null,
  loadedId: string | null,
  position: number,
): boolean {
  return (
    note !== null &&
    note.episodeId === loadedId &&
    Number.isFinite(position) &&
    position >= note.start - ASK_LEAD_SECONDS &&
    position < note.end
  )
}

/** Gives the player the listener's answer; true when an open question took it. */
export type AnswerQuestion = (
  episodeId: string,
  start: number,
  isAd: boolean,
) => Promise<boolean>

/** The one question on the screen, and what can happen to it. */
export function createAskNotes(
  answerQuestion: AnswerQuestion,
  warn: (message: string, cause: unknown) => void,
) {
  let current: AskNote | null = null
  const listeners = new Set<() => void>()

  function publish(next: AskNote | null) {
    if (next === current) return
    current = next
    for (const listener of [...listeners]) listener()
  }

  return {
    /** The question to show, before it is checked against the loaded episode and the place. */
    note: () => current,

    subscribe(listener: () => void): () => void {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },

    /** The phone asked (`onAdAsk`). The newest question is the one shown. */
    asked(event: unknown) {
      const next = askNoteFor(event)
      if (next !== null) publish(next)
    },

    /** An ad was skipped: a skip that covers the question (the Skip ad button) answers it. */
    skipped(event: { episodeId: string; start: number; end: number }) {
      if (
        current !== null &&
        event.episodeId === current.episodeId &&
        event.start < current.end &&
        current.start < event.end
      ) {
        publish(null)
      }
    },

    /** Takes `note` away (its stretch is over, or another episode is loaded), if it is still the one. */
    hide(note: AskNote) {
      if (current === note) publish(null)
    },

    /** Skip (`isAd`) or Not an ad. The note goes at once, so a second tap answers nothing. */
    answer(isAd: boolean) {
      const note = current
      if (note === null) return
      publish(null)
      answerQuestion(note.episodeId, note.start, isAd).catch((cause: unknown) =>
        warn("Couldn't answer the question about the ad", cause),
      )
    },
  }
}
