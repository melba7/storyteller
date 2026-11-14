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
  wait(ms: number): Promise<void>
  now(): number
}

export type SoundCheckState = {
  phase: "idle" | "starting" | "jumping" | "listening" | "asking" | "done"
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
export const RESULTS_KEY = "lofi.soundCheck.results"
/** How many runs' results the phone keeps. */
export const KEPT_RUNS = 5
const POLL_MS = 500
/** How long a jump may take to land before the stop counts as "could not play". */
const LAND_MS = 4_000
/** When to read what is playing, after the stop lands. */
const READ_AFTER_MS = 3_000
/** A one-off stop starts up to 20 sentences before its cue (the host's lead-in). */
const ONE_OFF_LEAD_SENTENCES = 20

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

/** The stop's sentences, with room before a one-off for its lead-in. */
function landedIn(stop: LofiSoundCheckStop, sentence: number | undefined) {
  if (sentence === undefined) return false
  const first =
    stop.cueIndex === undefined
      ? stop.globalIndex
      : stop.globalIndex - ONE_OFF_LEAD_SENTENCES
  return sentence >= first && sentence <= stop.lastIndex
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

  /** Puts back a place a check left behind (the app closed mid-check). */
  async restoreLeftover(bookID: string) {
    const raw = await this.deps.storage.getItem(SAVED_PLACE_KEY)
    if (!raw) return
    let place: SavedPlace | null = null
    try {
      place = JSON.parse(raw) as SavedPlace
    } catch {
      place = null
    }
    if (!place || place.bookID !== bookID) {
      if (!place) await this.deps.storage.removeItem(SAVED_PLACE_KEY)
      return
    }
    await this.deps.storage.removeItem(SAVED_PLACE_KEY)
    await this.deps.player.pause()
    await this.deps.player.seekTo(place.relativeUri, place.position)
  }

  async start(bookID: string, count = 6) {
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
      await this.deps.storage.setItem(
        SAVED_PLACE_KEY,
        JSON.stringify(this.saved),
      )
      if (run !== this.run) return this.putBack()
      this.set({ stops, results: stops.map(() => ({})), index: 0 })
      await this.playStop(run, 0)
    } catch (error) {
      await this.putBack()
      fail(error instanceof Error ? error.message : String(error))
    }
  }

  /** Plays stop `index`; asks when it ends, or moves on when the jump does not land. */
  private async playStop(run: number, index: number): Promise<void> {
    const stop = this.state.stops[index]
    if (!stop) return this.finish(run)
    this.set({
      phase: "jumping",
      index,
      secondsLeft: SOUND_CHECK_LISTEN_MS / 1000,
    })
    const { player } = this.deps
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
    let read = false
    for (;;) {
      await this.deps.wait(POLL_MS)
      if (run !== this.run) return
      const elapsed = this.deps.now() - startedAt
      if (!read && elapsed >= READ_AFTER_MS) {
        read = true
        const reading = await this.deps.getReading()
        if (run !== this.run) return
        this.setResult(index, { reading })
      }
      const sentence = (await this.deps.getStatus()).playback.sentence
      if (run !== this.run) return
      const left = Math.max(0, SOUND_CHECK_LISTEN_MS - elapsed)
      if (left === 0 || (sentence !== undefined && sentence > stop.lastIndex))
        break
      this.set({ secondsLeft: Math.ceil(left / 1000) })
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
    const index = this.state.index
    this.setResult(index, { answer: value })
    await this.playStop(this.run, index + 1)
  }

  /** Plays the stop being asked about again. */
  async playAgain() {
    if (this.state.phase !== "asking") return
    await this.playStop(this.run, this.state.index)
  }

  /** Stops the check (the Stop button, closing the panel, the app going to the background). */
  async stop() {
    if (this.state.phase === "idle" || this.state.phase === "done") return
    const run = ++this.run
    await this.putBack()
    if (run !== this.run) return
    const answered = this.state.results.some((r) => r.answer || r.couldNotPlay)
    this.set({ phase: answered ? "done" : "idle", message: undefined })
  }

  private async finish(run: number) {
    await this.putBack()
    if (run !== this.run) return
    this.set({ phase: "done" })
  }

  /** Puts the narration back where it was, once. */
  private async putBack() {
    const saved = this.saved
    this.saved = null
    if (!saved) return
    const { player, storage } = this.deps
    await player.pause()
    await player.seekTo(saved.relativeUri, saved.position)
    if (saved.wasPlaying) await player.play(false)
    await storage.removeItem(SAVED_PLACE_KEY)
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
