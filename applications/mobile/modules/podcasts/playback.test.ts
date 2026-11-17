// LOFI-FORK: the podcasts section's player controller (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import type { PodcastsEvents } from "./index"
import type { Show, StoredEpisode } from "./library"
import {
  type NativePlayer,
  type PlaybackDeps,
  clampSpeed,
  createPlayback,
  formatTime,
  isPlayed,
  resumeStart,
  showsMiniPlayer,
  speedLabel,
  stepSpeed,
  timeLeft,
} from "./playback"

describe("formatTime", () => {
  it("reads seconds, minutes and hours", () => {
    expect(formatTime(5)).toBe("0:05")
    expect(formatTime(754)).toBe("12:34")
    expect(formatTime(3723)).toBe("1:02:03")
    expect(formatTime(59.9)).toBe("0:59")
  })

  it("reads nonsense as zero", () => {
    expect(formatTime(-4)).toBe("0:00")
    expect(formatTime(Number.NaN)).toBe("0:00")
  })
})

describe("timeLeft", () => {
  it("shows the time left with a minus", () => {
    expect(timeLeft(0, 754)).toBe("-12:34")
    expect(timeLeft(3600, 3723)).toBe("-2:03")
    expect(timeLeft(800, 754)).toBe("-0:00")
  })

  it("shows dashes while the length is unknown", () => {
    expect(timeLeft(10, null)).toBe("--:--")
    expect(timeLeft(10, 0)).toBe("--:--")
  })
})

describe("speed", () => {
  it("is labelled with one decimal", () => {
    expect(speedLabel(1)).toBe("1.0x")
    expect(speedLabel(1.5)).toBe("1.5x")
    expect(speedLabel(2.4)).toBe("2.4x")
  })

  it("steps by a tenth inside 0.5x to 3.0x", () => {
    expect(stepSpeed(1, 1)).toBe(1.1)
    expect(stepSpeed(1.1, 1)).toBe(1.2)
    expect(stepSpeed(1, -1)).toBe(0.9)
    expect(stepSpeed(3, 1)).toBe(3)
    expect(stepSpeed(0.5, -1)).toBe(0.5)
  })

  it("rounds to a tenth and clamps", () => {
    expect(clampSpeed(1.26)).toBe(1.3)
    expect(clampSpeed(9)).toBe(3)
    expect(clampSpeed(0)).toBe(0.5)
    expect(clampSpeed(Number.NaN)).toBe(1)
  })
})

describe("resumeStart and isPlayed", () => {
  it("resumes unless played or nearly over", () => {
    expect(resumeStart(120, 600, false)).toBe(120)
    expect(resumeStart(120, 600, true)).toBe(0)
    expect(resumeStart(595, 600, false)).toBe(0)
    expect(resumeStart(700, 600, false)).toBe(0)
    expect(resumeStart(120, null, false)).toBe(120)
  })

  it("counts played at the end or within 5 seconds of it", () => {
    expect(isPlayed(10, 600, true)).toBe(true)
    expect(isPlayed(595, 600, false)).toBe(true)
    expect(isPlayed(594, 600, false)).toBe(false)
    expect(isPlayed(595, null, false)).toBe(false)
  })
})

describe("showsMiniPlayer", () => {
  it("shows when an episode is loaded or one was played before", () => {
    const episode = {} as StoredEpisode
    expect(showsMiniPlayer(null, null)).toBe(false)
    expect(showsMiniPlayer(episode, null)).toBe(true)
    expect(showsMiniPlayer(null, episode)).toBe(true)
  })
})

// MARK: Controller

function episode(overrides: Partial<StoredEpisode> = {}): StoredEpisode {
  return {
    id: "e1",
    showId: "s1",
    guid: "g1",
    title: "Episode one",
    publishedAt: 1000,
    durationSeconds: 600,
    notes: "",
    audioUrl: "https://cdn.example.com/1.mp3",
    audioType: "audio/mpeg",
    audioBytes: null,
    imageUrl: null,
    season: null,
    number: null,
    positionSeconds: 0,
    played: false,
    lastPlayedAt: null,
    ...overrides,
  }
}

const show: Show = {
  id: "s1",
  feedUrl: "https://example.com/rss",
  title: "The Show",
  author: null,
  description: "",
  imageUrl: "https://example.com/art.jpg",
  link: null,
  language: null,
  addedAt: 1,
  refreshedAt: 1,
  artworkColor: null,
}

function setup(last: StoredEpisode | null = null) {
  const handlers: Partial<PodcastsEvents> = {}
  const native = {
    load: vi.fn(() => Promise.resolve()),
    play: vi.fn(() => Promise.resolve()),
    pause: vi.fn(() => Promise.resolve()),
    togglePlayPause: vi.fn(() => Promise.resolve()),
    seekTo: vi.fn(() => Promise.resolve()),
    skipBy: vi.fn(() => Promise.resolve()),
    setRate: vi.fn((rate: number) => Promise.resolve(rate)),
    artworkColor: vi.fn(() => Promise.resolve<string | null>("#336699")),
    addListener: vi.fn((name: keyof PodcastsEvents, listener: never) => {
      ;(handlers as Record<string, unknown>)[name] = listener
      return { remove: () => {} }
    }),
  }
  const ticks: { callback: () => void; ms: number }[] = []
  const deps = {
    native: native as unknown as NativePlayer,
    savePlayback: vi.fn(() => Promise.resolve()),
    saveArtworkColor: vi.fn(() => Promise.resolve()),
    lastPlayedEpisode: vi.fn(() => Promise.resolve(last)),
    getShow: vi.fn(() => Promise.resolve<Show | null>(show)),
    setInterval: vi.fn((callback: () => void, ms: number) => {
      ticks.push({ callback, ms })
      return ticks.length
    }),
    clearInterval: vi.fn(),
  } satisfies PlaybackDeps
  const playback = createPlayback(deps)
  const state = (
    position: number,
    isPlaying: boolean,
    extra: Record<string, unknown> = {},
  ) =>
    handlers.onPlaybackState?.({
      episodeId: "e1",
      position,
      duration: 600,
      isPlaying,
      isBuffering: false,
      rate: 1,
      ...extra,
    })
  return { playback, native, deps, handlers, ticks, state }
}

describe("playEpisode", () => {
  it("loads the episode at its saved place and plays it", async () => {
    const { playback, native } = setup()
    await playback.playEpisode(episode({ positionSeconds: 120 }), show)
    expect(native.load).toHaveBeenCalledWith({
      episodeId: "e1",
      url: "https://cdn.example.com/1.mp3",
      title: "Episode one",
      showTitle: "The Show",
      artworkUrl: "https://example.com/art.jpg",
      savedPosition: 120,
      duration: 600,
      played: false,
      autoplay: true,
    })
    expect(playback.getView().episode?.id).toBe("e1")
    expect(playback.getView().position).toBe(120)
    expect(playback.getView().isBuffering).toBe(true)
  })

  it("shows the start of a played episode as zero", async () => {
    const { playback } = setup()
    await playback.playEpisode(
      episode({ positionSeconds: 300, played: true }),
      show,
    )
    expect(playback.getView().position).toBe(0)
  })

  it("works out the show's colour once and keeps it", async () => {
    const { playback, native, deps } = setup()
    await playback.playEpisode(episode(), show)
    await vi.waitFor(() =>
      expect(playback.getView().show?.artworkColor).toBe("#336699"),
    )
    expect(deps.saveArtworkColor).toHaveBeenCalledWith("s1", "#336699")
    await playback.playEpisode(episode({ id: "e2" }), playback.getView().show)
    expect(native.artworkColor).toHaveBeenCalledTimes(1)
  })

  it("resumes the same episode instead of loading it again", async () => {
    const { playback, native, state } = setup()
    await playback.playEpisode(episode(), show)
    state(10, false)
    await playback.playEpisode(episode(), show)
    expect(native.load).toHaveBeenCalledTimes(1)
    expect(native.play).toHaveBeenCalledTimes(1)
  })

  it("shows a readable message when loading fails", async () => {
    const { playback, native } = setup()
    native.load.mockRejectedValueOnce(
      new Error("This episode has no playable link."),
    )
    await playback.playEpisode(episode(), show)
    expect(playback.getView().error).toBe("This episode has no playable link.")
    expect(playback.getView().isBuffering).toBe(false)
  })

  it("says so when there is no native player", async () => {
    const { deps } = setup()
    const playback = createPlayback({ ...deps, native: null })
    await playback.playEpisode(episode(), show)
    expect(playback.getView().error).toBe("Podcasts need the iOS app.")
  })
})

describe("keeping the place", () => {
  it("saves on pause", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(30, true)
    state(42, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 42, false)
  })

  it("saves every 15 seconds while playing, and stops when paused", async () => {
    const { playback, deps, ticks, state } = setup()
    await playback.playEpisode(episode(), show)
    state(30, true)
    expect(ticks).toHaveLength(1)
    expect(ticks[0]?.ms).toBe(15_000)
    state(45, true)
    expect(ticks).toHaveLength(1)
    ticks[0]?.callback()
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 45, false)
    state(46, false)
    expect(deps.clearInterval).toHaveBeenCalledWith(1)
  })

  it("saves where a seek lands", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(0, true)
    await playback.seekTo(200)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 200, false)
    await playback.seekTo(9000)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 600, true)
  })

  it("saves a skip, kept inside the episode", async () => {
    const { playback, native, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(5, true)
    await playback.skip(-10)
    expect(native.skipBy).toHaveBeenCalledWith(-10)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 0, false)
  })

  it("marks played when it plays to the end", async () => {
    const { playback, deps, handlers } = setup()
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackEnded?.({
      episodeId: "e1",
      position: 600,
      duration: 600,
      played: true,
    })
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 600, true)
    expect(playback.getView().isPlaying).toBe(false)
  })

  it("marks played when paused within 5 seconds of the end", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(590, true)
    state(597, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 597, true)
  })

  it("does not save while the stream is only buffering", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(30, true)
    state(30, false, { isBuffering: true })
    expect(deps.savePlayback).not.toHaveBeenCalled()
  })

  it("keeps playing when saving fails", async () => {
    const { playback, deps, state } = setup()
    const report = vi.fn()
    const failing = createPlayback({
      ...deps,
      savePlayback: () => Promise.reject(new Error("disk full")),
      report,
    })
    await failing.playEpisode(episode(), show)
    state(30, true)
    state(40, false)
    await vi.waitFor(() => expect(report).toHaveBeenCalled())
    expect(playback.getView().error).toBeNull()
  })
})

describe("native events", () => {
  it("follows the native state", async () => {
    const { playback, state } = setup()
    await playback.playEpisode(episode(), show)
    state(12, true, { rate: 1.5, duration: 700 })
    expect(playback.getView()).toMatchObject({
      loaded: true,
      position: 12,
      duration: 700,
      isPlaying: true,
      rate: 1.5,
    })
  })

  it("ignores state from another episode", async () => {
    const { playback, state } = setup()
    await playback.playEpisode(episode(), show)
    state(99, true, { episodeId: "other" })
    expect(playback.getView().position).toBe(0)
  })

  it("shows an error from the player and clears it when playing again", async () => {
    const { playback, handlers, state } = setup()
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackError?.({ episodeId: "e1", message: "Server said 404." })
    expect(playback.getView().error).toBe("Server said 404.")
    state(1, true)
    expect(playback.getView().error).toBeNull()
  })

  it("tells subscribers about each change", async () => {
    const { playback, state } = setup()
    const listener = vi.fn()
    const unsubscribe = playback.subscribe(listener)
    await playback.playEpisode(episode(), show)
    const count = listener.mock.calls.length
    state(3, true)
    expect(listener.mock.calls.length).toBe(count + 1)
    unsubscribe()
    state(4, true)
    expect(listener.mock.calls.length).toBe(count + 1)
  })
})

describe("controls", () => {
  it("toggles between play and pause", async () => {
    const { playback, native, state } = setup()
    await playback.playEpisode(episode(), show)
    state(1, true)
    await playback.togglePlayPause()
    expect(native.pause).toHaveBeenCalled()
    state(1, false)
    await playback.togglePlayPause()
    expect(native.play).toHaveBeenCalled()
  })

  it("sets the speed to the one the player reports", async () => {
    const { playback, native } = setup()
    native.setRate.mockResolvedValueOnce(1.3)
    await playback.setRate(1.26)
    expect(native.setRate).toHaveBeenCalledWith(1.3)
    expect(playback.getView().rate).toBe(1.3)
  })
})

describe("restoreLast", () => {
  it("shows the last played episode without loading it", async () => {
    const last = episode({ positionSeconds: 200, lastPlayedAt: 5 })
    const { playback, native } = setup(last)
    await playback.restoreLast()
    expect(playback.getView()).toMatchObject({
      episode: last,
      show,
      loaded: false,
      position: 200,
      isPlaying: false,
    })
    expect(native.load).not.toHaveBeenCalled()
    expect(showsMiniPlayer(playback.getView().episode, null)).toBe(true)
  })

  it("loads it when play is pressed", async () => {
    const last = episode({ positionSeconds: 200, lastPlayedAt: 5 })
    const { playback, native } = setup(last)
    await playback.restoreLast()
    await playback.togglePlayPause()
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ episodeId: "e1", savedPosition: 200 }),
    )
  })

  it("shows nothing when nothing was played", async () => {
    const { playback } = setup(null)
    await playback.restoreLast()
    expect(playback.getView().episode).toBeNull()
  })

  it("does not replace an episode that is already loaded", async () => {
    const { playback } = setup(episode({ id: "old" }))
    await playback.playEpisode(episode(), show)
    await playback.restoreLast()
    expect(playback.getView().episode?.id).toBe("e1")
  })
})
