// LOFI-FORK: runs the sound check: jumps the narration to each stop, plays it,
// asks, and puts the narration back. The player and storage are passed in, so
// the steps can be tested without a phone (see FORK.md).
import type {
  LofiSoundCheckReading,
  LofiSoundCheckStop,
  LofiStatus,
} from "./index"
import {
  SOUND_CHECK_LISTEN_MS,
  type SoundCheckAnswer,
  type SoundCheckResult,
} from "./soundCheck"

export type SoundCheckPlayer = {
  getCurrentTrack(): Promise<{ relativeUri: string } | null>
  getPosition(): Promise<number>
  getIsPlaying(): Promise<boolean>
  seekTo(relativeUri: string, position: number): Promise<void>
  play(automaticRewind?: boolean): Promise<void>
  pause(): Promise<void>
}

export type SoundCheckStorage = {
  getItem(key: string): Promise<string | null>
  setItem(key: string, value: string): Promise<void>
  removeItem(key: string): Promise<void>
}

export type SoundCheckDeps = {
  player: SoundCheckPlayer
  storage: SoundCheckStorage
  getStatus(): Promise<LofiStatus>
  getStops(count: number): Promise<LofiSoundCheckStop[]>
  getReading(): Promise<LofiSoundCheckReading | null>
  /** Tells the sounds the narration is about to be moved to this sentence. */
  willJump(globalIndex: number): Promise<void>
  wait(ms: number): Promise<void>
  now(): number
}

export type SoundCheckState = {
  phase:
    | "idle"
    | "starting"
    | "jumping"
    | "listening"
    | "asking"
    | "restoring"
    | "done"
  stops: LofiSoundCheckStop[]
  results: SoundCheckResult[]
  /** The stop playing or asked about. */
  index: number
  secondsLeft: number
  message?: string | undefined
}

/** Where the narration was before the check, kept on the phone until it is put back. */
type SavedPlace = {
  bookID: string
  relativeUri: string
  position: number
  wasPlaying: boolean
}

export const SAVED_PLACE_KEY = "lofi.soundCheck.place"
/** Each book keeps its own place, so a check in one book never drops another's. */
export function savedPlaceKey(bookID: string) {
  return `${SAVED_PLACE_KEY}.${bookID}`
}
export const RESULTS_KEY = "lofi.soundCheck.results"
/** How many runs' results the phone keeps. */
export const KEPT_RUNS = 5
const POLL_MS = 500
/** How long a jump may take to land before the stop counts as "could not play". */
const LAND_MS = 4_000
/** When to read what is playing, after the stop lands. */
const READ_AFTER_MS = 3_000
/**
 * A one-off stop plays until the sentence after its sound ends. That can pass
 * the 20 s of a scene stop (a long lead-in sentence, then the sound late in its
 * own), so only this cap ends it early.
 */
export const ONE_OFF_LISTEN_MS = 45_000

const idle: SoundCheckState = {
  phase: "idle",
  stops: [],
  results: [],
  index: 0,
  secondsLeft: 0,
}

/** Why the check can't start now, or null when it can. */
export function cannotStartReason(status: LofiStatus | null): string | null {
  const sounds = status?.atmosphere
  if (!sounds?.enabled) return "Turn the atmosphere sounds on first."
  if (sounds.routeMuted)
    return "The sounds are off while the narration plays through the car."
  if (sounds.preparing) return "The sounds are still getting ready."
  if (!sounds.track) return "This book has no sounds to check yet."
  return null
}

/**
 * The narration is in the stop. One sentence of slack before it: a seek may
 * land a moment early, in the tail of the sentence before.
 */
function landedIn(stop: LofiSoundCheckStop, sentence: number | undefined) {
  if (sentence === undefined) return false
  return sentence >= stop.globalIndex - 1 && sentence <= stop.lastIndex
}

/** How many checks hold a place in memory: they put it back themselves. */
let checksRunning = 0

/**
 * Puts back a place a check left behind (the app closed mid-check), without
 * starting or stopping the narration. The place stays on the phone until the
 * player is really back in its file: the player ignores a file it has not
 * loaded yet.
 */
export async function restoreLeftoverPlace(
  player: Pick<SoundCheckPlayer, "getCurrentTrack" | "seekTo">,
  storage: SoundCheckStorage,
  bookID: string,
) {
  if (checksRunning > 0) return
  const key = savedPlaceKey(bookID)
  const raw = await storage.getItem(key)
  if (!raw) return
  let place: Partial<SavedPlace> | null = null
  try {
    place = JSON.parse(raw) as Partial<SavedPlace> | null
  } catch {
    place = null
  }
  if (
    typeof place?.relativeUri !== "string" ||
    typeof place.position !== "number"
  ) {
    await storage.removeItem(key)
    return
  }
  await player.seekTo(place.relativeUri, place.position)
  const track = await player.getCurrentTrack()
  if (track?.relativeUri === place.relativeUri) await storage.removeItem(key)
}

export class SoundCheckRunner {
  private state: SoundCheckState = idle
  /** Bumped by every start and stop; a step from an older run sees it changed and gives up. */
  private run = 0
  private saved: SavedPlace | null = null

  constructor(
    private deps: SoundCheckDeps,
    private onChange: (state: SoundCheckState) => void,
  ) {}

  get current() {
    return this.state
  }

  private set(change: Partial<SoundCheckState>) {
    this.state = { ...this.state, ...change }
    this.onChange(this.state)
  }

  private get answered() {
    return this.state.results.some((r) => r.answer || r.couldNotPlay)
  }

  async start(bookID: string, count = 6) {
    if (this.state.phase !== "idle" && this.state.phase !== "done") return
    const run = ++this.run
    this.set({ ...idle, phase: "starting" })
    const fail = (message: string) => {
      if (run === this.run) this.set({ ...idle, message })
    }
    try {
      const reason = cannotStartReason(await this.deps.getStatus())
      if (run !== this.run) return
      if (reason) return fail(reason)
      const track = await this.deps.player.getCurrentTrack()
      if (run !== this.run) return
      if (!track) return fail("Play the book for a moment first.")
      const stops = await this.deps.getStops(count)
      if (run !== this.run) return
      if (stops.length === 0) {
        return fail(
          "No spots to check yet. Listen a little further into the book first.",
        )
      }
      const position = await this.deps.player.getPosition()
      const wasPlaying = await this.deps.player.getIsPlaying()
      if (run !== this.run) return
      this.saved = {
        bookID,
        relativeUri: track.relativeUri,
        position,
        wasPlaying,
      }
      checksRunning += 1
      await this.deps.storage.setItem(
        savedPlaceKey(bookID),
        JSON.stringify(this.saved),
      )
      if (run !== this.run) return this.putBack(true)
      this.set({ stops, results: stops.map(() => ({})), index: 0 })
      await this.playStop(run, 0)
    } catch (error) {
      await this.giveUp(run, error)
    }
  }

  /** Plays stop `index`; asks when it ends, or moves on when the jump does not land. */
  private async playStop(run: number, index: number): Promise<void> {
    const stop = this.state.stops[index]
    if (!stop) return this.finish(run)
    const oneOff = stop.cueIndex !== undefined
    const listenMs = oneOff ? ONE_OFF_LISTEN_MS : SOUND_CHECK_LISTEN_MS
    this.set({
      phase: "jumping",
      index,
      secondsLeft: SOUND_CHECK_LISTEN_MS / 1000,
    })
    const { player } = this.deps
    await this.deps.willJump(stop.globalIndex)
    if (run !== this.run) return
    await player.seekTo(stop.relativeUrl, stop.start)
    if (run !== this.run) return
    await player.play(false)
    if (run !== this.run) return

    let landed = false
    for (let waited = 0; waited < LAND_MS && !landed; waited += POLL_MS) {
      await this.deps.wait(POLL_MS)
      if (run !== this.run) return
      landed = landedIn(stop, (await this.deps.getStatus()).playback.sentence)
      if (run !== this.run) return
    }
    if (!landed) {
      await player.pause()
      if (run !== this.run) return
      this.setResult(index, { couldNotPlay: true })
      return this.playStop(run, index + 1)
    }

    const startedAt = this.deps.now()
    this.set({ phase: "listening" })
    // A one-off is counted before and after, to tell "too quiet" from "never played".
    const playedBefore = oneOff
      ? (await this.deps.getReading())?.oneShotsPlayed
      : undefined
    if (run !== this.run) return
    let read = false
    for (;;) {
      await this.deps.wait(POLL_MS)
      if (run !== this.run) return
      const elapsed = this.deps.now() - startedAt
      const sentence = (await this.deps.getStatus()).playback.sentence
      if (run !== this.run) return
      const left = Math.max(0, listenMs - elapsed)
      const over =
        left === 0 || (sentence !== undefined && sentence > stop.lastIndex)
      // What plays is read once the jump's fade-in is over, or at the end of a
      // stop shorter than that.
      if (!read && (over || elapsed >= READ_AFTER_MS)) {
        read = true
        const reading = await this.deps.getReading()
        if (run !== this.run) return
        this.setResult(index, { reading })
      }
      if (over) break
      if (!oneOff) this.set({ secondsLeft: Math.ceil(left / 1000) })
    }
    if (oneOff) {
      const playedAfter = (await this.deps.getReading())?.oneShotsPlayed
      if (run !== this.run) return
      if (playedBefore !== undefined && playedAfter !== undefined) {
        this.setResult(index, { oneOffPlayed: playedAfter > playedBefore })
      }
    }
    await player.pause()
    if (run !== this.run) return
    this.set({ phase: "asking", secondsLeft: 0 })
  }

  private setResult(index: number, change: SoundCheckResult) {
    const results = this.state.results.map((result, i) =>
      i === index ? { ...result, ...change } : result,
    )
    this.set({ results })
  }

  /** Answers the stop being asked about and plays the next. Ignored at any other time. */
  async answer(value: SoundCheckAnswer) {
    if (this.state.phase !== "asking") return
    const run = this.run
    const index = this.state.index
    this.setResult(index, { answer: value })
    try {
      await this.playStop(run, index + 1)
    } catch (error) {
      await this.giveUp(run, error)
    }
  }

  /** Plays the stop being asked about again. */
  async playAgain() {
    if (this.state.phase !== "asking") return
    const run = this.run
    try {
      await this.playStop(run, this.state.index)
    } catch (error) {
      await this.giveUp(run, error)
    }
  }

  /**
   * Stops the check: the Stop button, closing the panel, or the app going to
   * the background. `resume` false leaves the narration paused at the
   * listener's place: nobody is listening when the phone locks.
   */
  async stop(resume = true) {
    if (
      !["starting", "jumping", "listening", "asking"].includes(this.state.phase)
    )
      return
    const run = ++this.run
    const answered = this.answered
    this.set({ phase: "restoring", message: undefined })
    let message: string | undefined
    try {
      await this.putBack(resume)
    } catch (error) {
      message = error instanceof Error ? error.message : String(error)
    }
    if (run !== this.run) return
    this.set({ phase: answered ? "done" : "idle", message })
  }

  private async finish(run: number) {
    this.set({ phase: "restoring" })
    await this.putBack(true)
    if (run !== this.run) return
    this.set({ phase: "done" })
  }

  /** A step failed: puts the narration back and says why. */
  private async giveUp(run: number, error: unknown) {
    if (run !== this.run) return
    const mine = ++this.run
    const message = error instanceof Error ? error.message : String(error)
    const answered = this.answered
    this.set({ phase: "restoring" })
    try {
      await this.putBack(true)
    } catch {
      // The place stays on the phone and is put back when the book next opens.
    }
    if (mine !== this.run) return
    this.set(answered ? { phase: "done", message } : { ...idle, message })
  }

  /** Puts the narration back where it was, once. */
  private async putBack(resume: boolean) {
    const saved = this.saved
    this.saved = null
    if (!saved) return
    checksRunning -= 1
    const { player, storage } = this.deps
    await player.pause()
    await player.seekTo(saved.relativeUri, saved.position)
    if (resume && saved.wasPlaying) await player.play(false)
    await storage.removeItem(savedPlaceKey(saved.bookID))
  }
}

/** Keeps a run's results text, newest first, and drops the oldest past `KEPT_RUNS`. */
export async function keepResults(storage: SoundCheckStorage, text: string) {
  const runs = await keptResults(storage)
  await storage.setItem(
    RESULTS_KEY,
    JSON.stringify([text, ...runs].slice(0, KEPT_RUNS)),
  )
}

/** The kept runs' results, newest first. */
export async function keptResults(
  storage: SoundCheckStorage,
): Promise<string[]> {
  try {
    const parsed: unknown = JSON.parse(
      (await storage.getItem(RESULTS_KEY)) ?? "[]",
    )
    return Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === "string")
      : []
  } catch {
    return []
  }
}
