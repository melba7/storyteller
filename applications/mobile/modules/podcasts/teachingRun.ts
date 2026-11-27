// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// Runs the exchange with the Mac where the Apple Podcasts list is read (the app's start and
// coming to the front): first the teaching files come in, then the Mac's prepared copies of
// episodes (preparedRun.ts), then the phone's notes go out. At most once in ten minutes, never waited for, and nothing here throws. Not imported
// by any test, because the native modules are not there; the rule for "once in ten minutes" is
// dueForTeaching in teaching.ts.
import { currentQueue, syncPhoneNotes } from "./phoneNotesSync"
import { runPrepared } from "./preparedRun"
import { dueForTeaching } from "./teaching"
import { sharedRead } from "./teachingAhead"
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
    // The table of episodes and the phone's list for the Mac both need the list of next episodes:
    // it is read once for the run, and only if one of them asks.
    const queue = sharedRead(currentQueue)
    try {
      watchTeachingShows()
      try {
        await syncTeaching(queue)
      } catch (cause) {
        console.warn("Couldn't read the teaching files from the Mac", cause)
      }
      await runPrepared(queue)
      await syncPhoneNotes(queue)
    } catch (cause) {
      console.warn("Couldn't exchange files with the Mac", cause)
    } finally {
      running = false
    }
  })()
}
