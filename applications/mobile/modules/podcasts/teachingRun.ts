// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// Runs the exchange with the Mac where the Apple Podcasts list is read (the app's start and
// coming to the front): first the teaching files come in, then the phone's notes go out, then
// the Mac's prepared copies of episodes are taken (preparedRun.ts), so a slow copy never delays
// the notes. At most once in ten minutes, never waited for, and nothing here throws. Not imported
// by any test, because the native modules are not there; the rule for "once in ten minutes" is
// dueForTeaching in teaching.ts.
import { LofiScore } from "@/modules/lofi-score"

import { MAP_LOOK_MS } from "./episodeMap"
import { lookForEpisodeMap } from "./episodeMapRun"
import { Podcasts } from "./index"
import {
  type Came,
  NOTHING_CAME,
  type Went,
  countAheadMarks,
} from "./macExchange"
import { recordExchange } from "./macExchangeStore"
import { DIARY_FILE, NOTES_FILE } from "./phoneNotes"
import { currentQueue, syncPhoneNotes } from "./phoneNotesSync"
import { QUEUE_FILE } from "./phoneQueue"
import { runPrepared } from "./preparedRun"
import { dueForPlay, dueForTeaching, parseTeachingState } from "./teaching"
import { sharedRead } from "./teachingAhead"
import { syncTeaching, watchTeachingShows } from "./teachingSync"

const AHEAD_FILE = "ahead-ads.json"

let lastRun: number | null = null
let running = false
let current: Promise<void> = Promise.resolve()
let watchingPlay = false

/** The checksums of the teaching files the phone has installed, by name. */
async function installedFiles(): Promise<Record<string, string>> {
  return parseTeachingState((await Podcasts?.getTeachingState()) ?? null)
    .installed
}

/** What came in the teaching files: how many changed, and how many episodes the new marks are for. */
async function cameFrom(
  before: Record<string, string>,
  after: Record<string, string>,
): Promise<Pick<Came, "files" | "marks">> {
  const changed = Object.keys(after).filter(
    (name) => after[name] !== before[name],
  )
  let marks = 0
  if (changed.includes(AHEAD_FILE) && LofiScore) {
    const read = await LofiScore.readLinkedFolderFileStatus(
      `Podcasts/${AHEAD_FILE}`,
    )
    if (read.status === "found")
      marks = countAheadMarks(read.text, Date.now() / 1000)
  }
  return { files: changed.filter((name) => name !== AHEAD_FILE).length, marks }
}

/** What the Mac can see from the phone in the linked folder: the list, the notes and the diary. */
async function wentNow(): Promise<Went> {
  const there = async (path: string) =>
    (await LofiScore?.readLinkedFolderFileStatus(path))?.status === "found"
  return {
    list: await there(QUEUE_FILE),
    notes: await there(NOTES_FILE),
    diary: await there(DIARY_FILE),
  }
}

/**
 * The run that is going, or one that is done: for a caller that must not end before the exchange
 * does (the background task). It never rejects.
 */
export function teachingSyncDone(): Promise<void> {
  return current
}

/**
 * Also runs the exchange when Play is pressed (at most once a minute), never delaying the start.
 * Starts once.
 */
function watchPlay(): void {
  if (watchingPlay) return
  watchingPlay = true
  void import("./playerInstance")
    .then(({ player }) => {
      let wasPlaying = false
      let episodeId: string | null = null
      // The Mac's map of the playing episode is looked for once the exchange has brought the
      // Mac's marks (see episodeMapRun.ts).
      const lookForMap = (id: string | null) =>
        void teachingSyncDone().then(() => lookForEpisodeMap(id))
      player.subscribe(() => {
        const view = player.getView()
        const id = view.episode?.id ?? null
        if (view.isPlaying && (!wasPlaying || id !== episodeId)) {
          runTeachingSync(true)
          lookForMap(id)
        }
        wasPlaying = view.isPlaying
        episodeId = id
      })
      // While an episode plays, the Mac's files are looked at again, so marks and a map the Mac
      // finishes in the middle of the episode are used for the rest of it.
      setInterval(() => {
        if (!wasPlaying || episodeId === null) return
        runTeachingSync()
        lookForMap(episodeId)
      }, MAP_LOOK_MS)
    })
    .catch((cause: unknown) =>
      console.warn("Couldn't watch for Play to look for the Mac's work", cause),
    )
}

/**
 * Starts the exchange when it is due, and returns at once. `atPlay` is for a Play: due a minute
 * after the last run instead of ten.
 */
export function runTeachingSync(atPlay = false): void {
  const now = Date.now()
  watchPlay()
  if (running || !(atPlay ? dueForPlay : dueForTeaching)(lastRun, now)) return
  running = true
  lastRun = now
  current = (async () => {
    // The table of episodes and the phone's list for the Mac both need the list of next episodes:
    // it is read once for the run, and only if one of them asks.
    const queue = sharedRead(currentQueue)
    try {
      watchTeachingShows()
      const before = await installedFiles().catch(
        (): Record<string, string> => ({}),
      )
      let came: Came = NOTHING_CAME
      try {
        await syncTeaching(queue)
        came = {
          ...NOTHING_CAME,
          ...(await cameFrom(before, await installedFiles())),
        }
      } catch (cause) {
        console.warn("Couldn't read the teaching files from the Mac", cause)
      }
      await syncPhoneNotes(queue)
      // The number of copies taken, when the run says it (see runPrepared); else none counted.
      const taken: unknown = await runPrepared(queue)
      if (typeof taken === "number" && taken > 0)
        came = { ...came, copies: taken }
      await recordExchange(Date.now(), came, await wentNow())
    } catch (cause) {
      console.warn("Couldn't exchange files with the Mac", cause)
    } finally {
      running = false
    }
  })()
}
