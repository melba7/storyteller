// LOFI-FORK: tests for running the sound check against a fake player (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiSoundCheckStop, LofiStatus } from "./index"
import {
  keepResults,
  keptResults,
  RESULTS_KEY,
  SAVED_PLACE_KEY,
  type SoundCheckDeps,
  SoundCheckRunner,
  type SoundCheckState,
} from "./soundCheckRunner"

const stops: LofiSoundCheckStop[] = [
  {
    globalIndex: 100,
    lastIndex: 120,
    kind: "water",
    sounds: [{ key: "river", level: "full" }],
    relativeUrl: "a.mp3",
    start: 10,
  },
  {
    globalIndex: 200,
    lastIndex: 203,
    kind: "weather",
    sounds: [{ key: "rain", level: "soft" }],
    relativeUrl: "b.mp3",
    start: 50,
  },
]

/**
 * A player that lands on a stop's first sentence when it seeks to the stop and
 * moves on a sentence every 2 s while playing. `brokenUrls` never land.
 */
function fakes(options: { brokenUrls?: string[]; muted?: boolean } = {}) {
  const store = new Map<string, string>()
  const calls: string[] = []
  let clock = 0
  let sentence: number | undefined = 500
  let sentenceSince = 0
  let playing = true
  let uri = "home.mp3"
  let position = 77
  const now = () => clock
  const current = () =>
    sentence === undefined
      ? undefined
      : sentence + (playing ? Math.floor((clock - sentenceSince) / 2000) : 0)
  const hooks: { beforeSeek?: () => void } = {}
  const status = (): LofiStatus =>
    ({
      playback: { sentence: current(), narrating: playing },
      atmosphere: {
        enabled: true,
        routeMuted: options.muted ?? false,
        preparing: false,
        track: true,
      },
    }) as unknown as LofiStatus

  const deps: SoundCheckDeps = {
    player: {
      getCurrentTrack: async () => ({ relativeUri: uri }),
      getPosition: async () => position,
      getIsPlaying: async () => playing,
      seekTo: async (to, at) => {
        hooks.beforeSeek?.()
        calls.push(`seek ${to} ${at}`)
        uri = to
        position = at
        const stop = stops.find((s) => s.relativeUrl === to)
        sentence =
          stop && !options.brokenUrls?.includes(to)
            ? stop.globalIndex
            : to === "home.mp3"
              ? 500
              : 9999
        sentenceSince = clock
      },
      play: async () => {
        calls.push("play")
        sentence = current()
        sentenceSince = clock
        playing = true
      },
      pause: async () => {
        calls.push("pause")
        sentence = current()
        sentenceSince = clock
        playing = false
      },
    },
    storage: {
      getItem: async (key) => store.get(key) ?? null,
      setItem: async (key, value) => void store.set(key, value),
      removeItem: async (key) => void store.delete(key),
    },
    getStatus: async () => status(),
    getStops: async () => stops,
    getReading: async () => ({
      voices: [],
      missingSounds: [],
      route: "builtIn",
      routeMuted: false,
      voiceLoudnessLUFS: -16,
      bedLevelDB: -10,
      oneShotsEnabled: true,
      pausesEnabled: true,
    }),
    wait: async (ms) => {
      clock += ms
    },
    now,
  }
  const states: SoundCheckState[] = []
  const runner = new SoundCheckRunner(deps, (state) => states.push(state))
  return { runner, deps, store, calls, states, hooks }
}

describe("running the sound check", () => {
  it("plays each stop, asks, and puts the narration back at the end", async () => {
    const { runner, calls, store } = fakes()
    await runner.start("book")
    expect(runner.current.phase).toBe("asking")
    expect(runner.current.index).toBe(0)
    expect(store.has(SAVED_PLACE_KEY)).toBe(true)
    expect(runner.current.results[0]?.reading?.route).toBe("builtIn")

    await runner.answer("clear")
    expect(runner.current.phase).toBe("asking")
    expect(runner.current.index).toBe(1)
    await runner.answer("faint")

    expect(runner.current.phase).toBe("done")
    expect(runner.current.results.map((r) => r.answer)).toEqual([
      "clear",
      "faint",
    ])
    expect(calls.slice(-3)).toEqual(["pause", "seek home.mp3 77", "play"])
    expect(store.has(SAVED_PLACE_KEY)).toBe(false)
  })

  it("ends a stop when the scene ends, before the 20 s", async () => {
    const { runner, states } = fakes()
    await runner.start("book")
    await runner.answer("clear")
    // The rain lasts 4 sentences (about 8 s here), so the countdown never gets near 0.
    const rain = states.filter((s) => s.index === 1 && s.phase === "listening")
    expect(Math.min(...rain.map((s) => s.secondsLeft))).toBeGreaterThan(8)
    expect(runner.current.phase).toBe("asking")
  })

  it("skips a stop the jump does not land on", async () => {
    const { runner } = fakes({ brokenUrls: ["a.mp3"] })
    await runner.start("book")
    expect(runner.current.index).toBe(1)
    expect(runner.current.results[0]?.couldNotPlay).toBe(true)
  })

  it("ignores answers while a stop plays", async () => {
    const { runner } = fakes()
    const started = runner.start("book")
    await runner.answer("tooLoud")
    await started
    expect(runner.current.results[0]?.answer).toBeUndefined()
  })

  it("puts the narration back once when stopped mid-jump, and starts nothing after", async () => {
    const { runner, calls, hooks, store } = fakes()
    let stopping: Promise<void> | undefined
    hooks.beforeSeek = () => {
      delete hooks.beforeSeek
      stopping = runner.stop()
    }
    await runner.start("book")
    await stopping
    expect(calls.filter((c) => c === "seek home.mp3 77")).toHaveLength(1)
    expect(calls.at(-1)).toBe("play")
    expect(runner.current.phase).toBe("idle")
    expect(store.has(SAVED_PLACE_KEY)).toBe(false)
  })

  it("plays a stop again on request", async () => {
    const { runner, calls } = fakes()
    await runner.start("book")
    await runner.playAgain()
    expect(calls.filter((c) => c === "seek a.mp3 10")).toHaveLength(2)
    expect(runner.current.index).toBe(0)
  })

  it("won't start while the sounds are off in the car", async () => {
    const { runner, calls } = fakes({ muted: true })
    await runner.start("book")
    expect(runner.current.phase).toBe("idle")
    expect(runner.current.message).toMatch(/car/)
    expect(calls).toEqual([])
  })

  it("puts back a place a closed app left behind, only for its book", async () => {
    const { runner, store, calls } = fakes()
    const place = {
      bookID: "book",
      relativeUri: "x.mp3",
      position: 5,
      wasPlaying: true,
    }
    store.set(SAVED_PLACE_KEY, JSON.stringify(place))
    await runner.restoreLeftover("other")
    expect(calls).toEqual([])
    await runner.restoreLeftover("book")
    expect(calls).toEqual(["pause", "seek x.mp3 5"])
    expect(store.has(SAVED_PLACE_KEY)).toBe(false)
  })

  it("keeps the last five runs' results, newest first", async () => {
    const { deps, store } = fakes()
    for (const n of [1, 2, 3, 4, 5, 6])
      await keepResults(deps.storage, `run ${n}`)
    expect(await keptResults(deps.storage)).toEqual([
      "run 6",
      "run 5",
      "run 4",
      "run 3",
      "run 2",
    ])
    store.set(RESULTS_KEY, "not json")
    expect(await keptResults(deps.storage)).toEqual([])
  })
})
