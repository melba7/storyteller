// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useSyncExternalStore } from "react"

import { answerAdQuestion } from "@/modules/podcasts/adsNative"
import {
  type AskNote,
  askNoteShown,
  createAskNotes,
} from "@/modules/podcasts/askNote"
import { Podcasts } from "@/modules/podcasts/index"
import { usePlayerValue } from "@/modules/podcasts/playerInstance"

// The "Ad? Skip" question: set by Swift's onAdAsk, gone when its stretch ends, when another
// episode is loaded or when it is answered. One copy is shared by every screen that shows it.
const notes = createAskNotes(answerAdQuestion, (message, cause) =>
  console.warn(message, cause),
)
let started = false

function start() {
  if (started || Podcasts === null) return
  started = true
  Podcasts.addListener("onAdAsk", (event) => notes.asked(event))
  // Skip ad inside a question answers it with a yes, and Swift reports that as a skip.
  Podcasts.addListener("onAdSkipped", (event) => notes.skipped(event))
}

function subscribe(listener: () => void): () => void {
  start()
  return notes.subscribe(listener)
}

// Listens from the moment the app loads this file, not when the full player first opens: an
// event that comes while nothing listens is dropped, and a question can be asked before then.
start()

/**
 * The question to show now, or null: only while the playhead is in its stretch of the loaded
 * episode. A note that is over stays out of the store too, so a seek back to it later does not
 * bring back a question the phone asks again by itself.
 */
export function useAskNote(): AskNote | null {
  const note = useSyncExternalStore(subscribe, notes.note)
  const shown = usePlayerValue((view) =>
    askNoteShown(note, view.episode?.id ?? null, view.position),
  )
  useEffect(() => {
    if (note !== null && !shown) notes.hide(note)
  }, [note, shown])
  return note !== null && shown ? note : null
}

/** Skip (`true`) or Not an ad (`false`): Swift does the rest and says so with its own events. */
export function pressAskAnswer(isAd: boolean) {
  notes.answer(isAd)
}
