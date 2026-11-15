// LOFI-FORK: tests for running the sound check against a fake player (see FORK.md).
import { afterEach, describe, expect, it } from "vitest"

import type { LofiSoundCheckStop, LofiStatus } from "./index"
import {
  keepResults,
  keptResults,
  restoreLeftoverPlace,
  RESULTS_KEY,
  savedPlaceKey,
  type SoundCheckDeps,
  SoundCheckRunner,
  type SoundCheckState,
} from "./soundCheckRunner"

const twoStops: LofiSoundCheckStop[] = [
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

/** The runners a test made: each one's check is ended after the test. */
const made: SoundCheckRunner[] = []
afterEach(async () => {
  for (const runner of made.splice(0)) await runner.stop()
})

/** A knock at sentence 311, in a stop that starts 11 sentences before it. */
const knock: LofiSoundCheckStop = {
  globalIndex: 300,
  lastIndex: 312,
  kind: "oneOff",
  sounds: [{ key: "doorKnock" }],
  cueIndex: 311,
  relativeUrl: "c.mp3",
  start: 5,
}

/**
 * A player that lands on a stop's first sentence when it seeks to the stop and
 * moves on a sentence every 2 s while playing. `brokenUrls` never land,
 * `throwingUrls` fail, and `knockAt` is the sentence where a one-off plays.
 */
function fakes(
  options: {
    stops?: LofiSoundCheckStop[]
    brokenUrls?: string[]
    throwingUrls?: string[]
    muted?: boolean
    knockAt?: number
  } = {},
) {
  const stops = options.stops ?? twoStops
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
        if (options.throwingUrls?.includes(to)) throw new Error("boom")
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
      missingOneShots: [],
      oneShotsPlayed:
        options.knockAt !== undefined && (current() ?? 0) >= options.knockAt
          ? 1
          : 0,
      route: "builtIn",
      routeMuted: false,
      voiceLoudnessLUFS: -16,
      bedLevelDB: -10,
      oneShotsEnabled: true,
      pausesEnabled: true,
    }),
    willJump: async (globalIndex) => {
      calls.push(`jump ${globalIndex}`)
    },
    wait: async (ms) => {
      clock += ms
    },
    now,
  }
  const states: SoundCheckState[] = []
  const runner = new SoundCheckRunner(deps, (state) => states.push(state))
  made.push(runner)
  return { runner, deps, store, calls, states, hooks, now }
}

describe("running the sound check", () => {
  it("plays each stop, asks, and puts the narration back at the end", async () => {
    const { runner, calls, store } = fakes()
    await runner.start("book")
    expect(runner.current.phase).toBe("asking")
    expect(runner.current.index).toBe(0)
    expect(store.has(savedPlaceKey("book"))).toBe(true)
    expect(runner.current.results[0]?.reading?.route).toBe("builtIn")
    // The sounds are told of each jump first, so even a near one starts afresh.
    expect(calls.slice(0, 3)).toEqual(["jump 100", "seek a.mp3 10", "play"])

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
    expect(store.size).toBe(0)
  })

  it("takes one answer for the last stop, however fast the taps", async () => {
    const { runner, calls, states } = fakes()
    await runner.start("book")
    await runner.answer("clear")
    await Promise.all([runner.answer("faint"), runner.answer("tooLoud")])
    expect(runner.current.results[1]?.answer).toBe("faint")
    expect(states.filter((s) => s.phase === "done")).toHaveLength(1)
    expect(calls.filter((c) => c === "seek home.mp3 77")).toHaveLength(1)
  })

  it("reads what played even at a stop shorter than the fade-in", async () => {
    const short = { ...twoStops[0]!, lastIndex: 100 }
    const { runner } = fakes({ stops: [short] })
    await runner.start("book")
    expect(runner.current.phase).toBe("asking")
    expect(runner.current.results[0]?.reading?.route).toBe("builtIn")
  })

  it("plays a one-off stop to the end of its sound, past 20 s, and notes that it played", async () => {
    const { runner, now } = fakes({ stops: [knock], knockAt: 311 })
    await runner.start("book")
    expect(runner.current.phase).toBe("asking")
    // 13 sentences at 2 s each.
    expect(now()).toBeGreaterThan(25_000)
    expect(runner.current.results[0]?.oneOffPlayed).toBe(true)

    const silent = fakes({ stops: [knock] })
    await silent.runner.start("book")
    expect(silent.runner.current.results[0]?.oneOffPlayed).toBe(false)
  })

  it("leaves the narration paused at the listener's place when the app goes to the background", async () => {
    const { runner, calls, store } = fakes()
    await runner.start("book")
    await runner.stop(false)
    expect(calls.slice(-2)).toEqual(["pause", "seek home.mp3 77"])
    expect(runner.current.phase).toBe("idle")
    expect(store.size).toBe(0)
  })

  it("puts the narration back and says why when a jump fails", async () => {
    const { runner, calls, store } = fakes({ throwingUrls: ["b.mp3"] })
    await runner.start("book")
    await runner.answer("clear")
    expect(runner.current.phase).toBe("done")
    expect(runner.current.message).toMatch(/boom/)
    expect(runner.current.results[0]?.answer).toBe("clear")
    expect(calls.slice(-3)).toEqual(["pause", "seek home.mp3 77", "play"])
    expect(store.size).toBe(0)
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
    expect(store.size).toBe(0)
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
    const { deps, store, calls } = fakes()
    const place = {
      bookID: "book",
      relativeUri: "x.mp3",
      position: 5,
      wasPlaying: true,
    }
    store.set(savedPlaceKey("book"), JSON.stringify(place))
    await restoreLeftoverPlace(deps.player, deps.storage, "other")
    expect(calls).toEqual([])
    await restoreLeftoverPlace(deps.player, deps.storage, "book")
    expect(calls).toEqual(["seek x.mp3 5"])
    expect(store.size).toBe(0)
  })

  it("keeps a left-behind place until the player is really back there", async () => {
    const { deps, store } = fakes()
    store.set(
      savedPlaceKey("book"),
      JSON.stringify({ bookID: "book", relativeUri: "x.mp3", position: 5 }),
    )
    // The player has not loaded the book yet: it ignores the file.
    const notLoaded = {
      seekTo: async () => {},
      getCurrentTrack: async () => null,
    }
    await restoreLeftoverPlace(notLoaded, deps.storage, "book")
    expect(store.has(savedPlaceKey("book"))).toBe(true)
    await restoreLeftoverPlace(deps.player, deps.storage, "book")
    expect(store.size).toBe(0)

    store.set(savedPlaceKey("book"), "not json")
    await restoreLeftoverPlace(deps.player, deps.storage, "book")
    expect(store.size).toBe(0)
  })

  it("leaves a left-behind place alone while a check is running", async () => {
    const { runner, deps, calls } = fakes()
    await runner.start("book")
    const before = calls.length
    await restoreLeftoverPlace(deps.player, deps.storage, "book")
    expect(calls).toHaveLength(before)
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
