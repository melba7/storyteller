// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// Runs the two sides of the exchange with the Mac where the Apple Podcasts list is read (the
// app's start and coming to the front): first the teaching files come in, then the phone's notes
// go out. At most once in ten minutes, never waited for, and nothing here throws. Not imported
// by any test, because the native modules are not there; the rule for "once in ten minutes" is
// dueForTeaching in teaching.ts.
import { syncPhoneNotes } from "./phoneNotesSync"
import { dueForTeaching } from "./teaching"
import { syncTeaching, watchTeachingShows } from "./teachingSync"

let lastRun: number | null = null
let running = false

/** Starts the exchange when it is due, and returns at once. */
export function runTeachingSync(): void {
  const now = Date.now()
  if (running || !dueForTeaching(lastRun, now)) return
  running = true
  lastRun = now
  void (async () => {
    try {
      watchTeachingShows()
      try {
        await syncTeaching()
      } catch (cause) {
        console.warn("Couldn't read the teaching files from the Mac", cause)
      }
      await syncPhoneNotes()
    } catch (cause) {
      console.warn("Couldn't exchange files with the Mac", cause)
    } finally {
      running = false
    }
  })()
}
