// LOFI-FORK: the podcasts section's player controller (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import type { PodcastsEvents } from "./index"
import type { Show, StoredEpisode } from "./library"
import {
  type NativePlayer,
  type PlaybackDeps,
  createPlayback,
} from "./playback"
import { showsMiniPlayer } from "./playbackRules"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

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
    transcriptUrl: null,
    transcriptType: null,
    people: [],
    chaptersUrl: null,
    positionSeconds: 0,
    played: false,
    lastPlayedAt: null,
    archived: false,
    starredAt: null,
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
  ownPosition: null,
  categories: [],
  funding: [],
  people: [],
  settings: DEFAULT_SHOW_SETTINGS,
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
    getEpisode: vi.fn(() => Promise.resolve<StoredEpisode | null>(null)),
    setInterval: vi.fn((callback: () => void, ms: number) => {
      ticks.push({ callback, ms })
      return ticks.length
    }),
    clearInterval: vi.fn(),
    playedWithin: vi.fn(() => 0),
    playThroughDownload: vi.fn((): Promise<boolean> | boolean => false),
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

describe("the wait before a stream starts", () => {
  it("shows while Swift checks the start, and ends when it says so", async () => {
    const { playback, state } = setup()
    await playback.playEpisode(episode(), show)
    expect(playback.getView().checkingStart).toBe(false)
    state(0, false, { isBuffering: true, checkingStart: true })
    expect(playback.getView()).toMatchObject({
      checkingStart: true,
      isBuffering: true,
      isPlaying: false,
    })
    state(0.4, true)
    expect(playback.getView()).toMatchObject({
      checkingStart: false,
      isPlaying: true,
    })
  })

  it("is not kept for the next episode that loads", async () => {
    const { playback, state } = setup()
    await playback.playEpisode(episode(), show)
    state(0, false, { isBuffering: true, checkingStart: true })
    await playback.playEpisode(episode({ id: "e2" }), show)
    expect(playback.getView().checkingStart).toBe(false)
  })
})

describe("an episode that Swift starts from Up Next", () => {
  it("becomes the loaded episode, with its show", async () => {
    const next = episode({
      id: "e2",
      title: "Episode two",
      positionSeconds: 90,
    })
    const { playback, deps, handlers } = setup()
    deps.getEpisode.mockResolvedValue(next)
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackAdvanced?.({ episodeId: "e2" })
    await vi.waitFor(() => expect(playback.getView().episode?.id).toBe("e2"))
    const view = playback.getView()
    expect(view.show?.id).toBe("s1")
    expect(view.loaded).toBe(true)
    expect(view.position).toBe(90)
    expect(view.isBuffering).toBe(true)
  })

  it("then follows that episode's state", async () => {
    const { playback, deps, handlers } = setup()
    deps.getEpisode.mockResolvedValue(episode({ id: "e2" }))
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackAdvanced?.({ episodeId: "e2" })
    await vi.waitFor(() => expect(playback.getView().episode?.id).toBe("e2"))
    handlers.onPlaybackState?.({
      episodeId: "e2",
      position: 5,
      duration: 600,
      isPlaying: true,
      isBuffering: false,
      rate: 1,
    })
    expect(playback.getView()).toMatchObject({ isPlaying: true, position: 5 })
  })

  it("is ignored when the library and Up Next both lack the episode", async () => {
    const { playback, deps, handlers } = setup()
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackAdvanced?.({ episodeId: "gone" })
    await vi.waitFor(() => expect(deps.getEpisode).toHaveBeenCalledWith("gone"))
    expect(playback.getView().episode?.id).toBe("e1")
  })

  // This used to assert that an episode the library lacks froze the player on the old one.
  it("follows an episode only Up Next knows, built from its queue item", async () => {
    const { playback, handlers } = setup()
    await playback.playEpisode(episode(), show)
    handlers.onUpNextChange?.({
      items: [
        {
          id: "preview:x#g9",
          showId: "preview:x",
          url: "https://cdn.example.com/9.mp3",
          type: "audio/mpeg",
          title: "Unfollowed one",
          showTitle: "Other",
          artworkUrl: "https://example.com/9.jpg",
          duration: 300,
          position: 12,
        },
      ],
    })
    handlers.onUpNextChange?.({ items: [] }) // Swift drops it before it announces it
    handlers.onPlaybackAdvanced?.({ episodeId: "preview:x#g9" })
    await vi.waitFor(() =>
      expect(playback.getView().episode?.id).toBe("preview:x#g9"),
    )
    expect(playback.getView()).toMatchObject({
      loaded: true,
      position: 12,
      duration: 300,
    })
    expect(playback.getView().episode).toMatchObject({
      title: "Unfollowed one",
      audioUrl: "https://cdn.example.com/9.mp3",
    })
    handlers.onPlaybackState?.({
      episodeId: "preview:x#g9",
      position: 40,
      duration: 300,
      isPlaying: true,
      isBuffering: false,
      rate: 1,
    })
    expect(playback.getView()).toMatchObject({ isPlaying: true, position: 40 })
  })
})

describe("playEpisode", () => {
  it("loads the episode at its saved place and plays it", async () => {
    const { playback, native } = setup()
    await playback.playEpisode(episode({ positionSeconds: 120 }), show)
    expect(native.load).toHaveBeenCalledWith({
      episodeId: "e1",
      showId: "s1",
      url: "https://cdn.example.com/1.mp3",
      title: "Episode one",
      showTitle: "The Show",
      artworkUrl: "https://example.com/art.jpg",
      savedPosition: 120,
      duration: 600,
      played: false,
      autoplay: true,
      audioType: "audio/mpeg",
      chaptersUrl: null,
      playThroughDownload: false,
      language: null,
    })
    expect(playback.getView().episode?.id).toBe("e1")
    expect(playback.getView().position).toBe(120)
    expect(playback.getView().isBuffering).toBe(true)
  })

  it("asks about an episode that starts, not about a resume", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    expect(deps.playThroughDownload).toHaveBeenCalledTimes(1)
    expect(deps.playThroughDownload).toHaveBeenCalledWith(episode(), show)
    state(5, false)
    await playback.playEpisode(episode(), show)
    expect(deps.playThroughDownload).toHaveBeenCalledTimes(1)
  })

  it("loads at once, with the answer and the show's language", async () => {
    const { playback, native, deps } = setup()
    deps.playThroughDownload.mockResolvedValueOnce(true)
    await playback.playEpisode(episode(), { ...show, language: "en" })
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ playThroughDownload: true, language: "en" }),
    )
  })

  it("does not play through the download when nothing says to", async () => {
    const { playback, native } = setup()
    await playback.playEpisode(episode(), show)
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ playThroughDownload: false }),
    )
  })

  it("loads only after the answer, and a newer play wins over one that is deciding", async () => {
    const { playback, native, deps } = setup()
    let answer: (through: boolean) => void = () => {}
    deps.playThroughDownload.mockImplementationOnce(
      () => new Promise<boolean>((done) => (answer = done)),
    )
    const first = playback.playEpisode(episode({ id: "e1" }), show)
    await Promise.resolve()
    expect(native.load).not.toHaveBeenCalled()
    await playback.playEpisode(episode({ id: "e2" }), show)
    expect(native.load).toHaveBeenCalledTimes(1)
    answer(true)
    await first
    expect(native.load).toHaveBeenCalledTimes(1)
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ episodeId: "e2" }),
    )
  })

  it("loads anyway, as a plain stream, when the question fails", async () => {
    const { playback, native, deps } = setup()
    deps.playThroughDownload.mockRejectedValueOnce(new Error("no"))
    await playback.playEpisode(episode(), show)
    expect(native.load).toHaveBeenCalledTimes(1)
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ playThroughDownload: false }),
    )
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

describe("marking played when seconds are left", () => {
  it("saves as played when the window is entered, once", async () => {
    const { playback, deps, state } = setup()
    deps.playedWithin.mockReturnValue(30)
    await playback.playEpisode(episode(), show)
    state(500, true)
    expect(deps.savePlayback).not.toHaveBeenCalled()
    state(570, true)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 570, true)
    state(572, true)
    expect(deps.savePlayback).toHaveBeenCalledTimes(1)
  })

  it("saves again after a seek back out and in", async () => {
    const { playback, deps, state } = setup()
    deps.playedWithin.mockReturnValue(30)
    await playback.playEpisode(episode(), show)
    state(580, true)
    state(100, true)
    state(575, true)
    expect(deps.savePlayback).toHaveBeenCalledTimes(2)
  })

  it("does nothing when the setting is off", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(590, true)
    expect(deps.savePlayback).not.toHaveBeenCalled()
  })

  it("counts a pause inside the window as played", async () => {
    const { playback, deps, state } = setup()
    deps.playedWithin.mockReturnValue(60)
    await playback.playEpisode(episode(), show)
    state(530, true)
    deps.savePlayback.mockClear()
    state(545, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 545, true)
  })
})

describe("the next button starting another episode", () => {
  it("saves the place of the one that was playing", async () => {
    const { playback, deps, handlers, state } = setup()
    deps.getEpisode.mockResolvedValue(episode({ id: "e2" }))
    await playback.playEpisode(episode(), show)
    state(120, true)
    deps.savePlayback.mockClear()
    handlers.onPlaybackAdvanced?.({ episodeId: "e2" })
    await vi.waitFor(() => expect(playback.getView().episode?.id).toBe("e2"))
    expect(deps.savePlayback).toHaveBeenCalledWith("e1", 120, false)
  })

  it("does not save again for one that already ended", async () => {
    const { playback, deps, handlers } = setup()
    deps.getEpisode.mockResolvedValue(episode({ id: "e2" }))
    await playback.playEpisode(episode(), show)
    handlers.onPlaybackEnded?.({
      episodeId: "e1",
      position: 600,
      duration: 600,
      played: true,
    })
    deps.savePlayback.mockClear()
    handlers.onPlaybackAdvanced?.({ episodeId: "e2" })
    await vi.waitFor(() => expect(playback.getView().episode?.id).toBe("e2"))
    expect(deps.savePlayback).not.toHaveBeenCalled()
  })
})

describe("playFrom", () => {
  it("loads a new episode at the given second, even if it was played", async () => {
    const { playback, native } = setup()
    await playback.playFrom(
      episode({ positionSeconds: 30, played: true }),
      show,
      95,
    )
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({
        savedPosition: 95,
        played: false,
        autoplay: true,
      }),
    )
    expect(playback.getView().position).toBe(95)
  })

  it("seeks the loaded episode and plays it", async () => {
    const { playback, native, state } = setup()
    await playback.playEpisode(episode(), show)
    state(10, false)
    await playback.playFrom(episode(), show, 95)
    expect(native.load).toHaveBeenCalledTimes(1)
    expect(native.seekTo).toHaveBeenCalledWith(95)
    expect(native.play).toHaveBeenCalledTimes(1)
  })

  it("only seeks when the episode is already playing", async () => {
    const { playback, native, state } = setup()
    await playback.playEpisode(episode(), show)
    state(10, true)
    await playback.playFrom(episode(), show, 95)
    expect(native.seekTo).toHaveBeenCalledWith(95)
    expect(native.play).not.toHaveBeenCalled()
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

describe("marking the loaded episode", () => {
  it("keeps played through the player's next save", async () => {
    const { playback, deps, state } = setup()
    await playback.playEpisode(episode(), show)
    state(30, true)
    await playback.episodesMarked(["e1"], true)
    state(31, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 31, true)
  })

  it("unplayed goes back to the start and is saved as unplayed", async () => {
    const { playback, native, deps, state } = setup()
    await playback.playEpisode(episode({ played: true }), show)
    state(590, true)
    await playback.episodesMarked(["e1"], true)
    await playback.episodesMarked(["e1"], false)
    expect(native.seekTo).toHaveBeenCalledWith(0)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 0, false)
    state(1, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 1, false)
  })

  it("ignores other episodes", async () => {
    const { playback, native, state, deps } = setup()
    await playback.playEpisode(episode(), show)
    state(10, true)
    await playback.episodesMarked(["other"], false)
    expect(native.seekTo).not.toHaveBeenCalled()
    state(11, false)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 11, false)
  })
})

describe("a followed preview", () => {
  const preview = episode({
    id: "preview:f#g1",
    guid: "g1",
    showId: "preview:f",
  })

  it("saves its place to the library episode with the same guid", async () => {
    const { playback, deps, handlers } = setup()
    await playback.playEpisode(preview, show)
    handlers.onPlaybackState?.({
      episodeId: "preview:f#g1",
      position: 77,
      duration: 600,
      isPlaying: true,
      isBuffering: false,
      rate: 1,
    })
    playback.adoptLibrary(
      [
        episode({ id: "lib2", guid: "g2" }),
        episode({ id: "lib1", guid: "g1" }),
      ],
      show,
    )
    expect(playback.getView().episode?.id).toBe("lib1")
    expect(deps.savePlayback).toHaveBeenCalledWith("lib1", 77, false)
    // The native player still calls it by the preview id, and the view keeps following.
    handlers.onPlaybackState?.({
      episodeId: "preview:f#g1",
      position: 80,
      duration: 600,
      isPlaying: true,
      isBuffering: false,
      rate: 1,
    })
    expect(playback.getView().position).toBe(80)
  })

  it("leaves a library episode alone", async () => {
    const { playback } = setup()
    await playback.playEpisode(episode(), show)
    playback.adoptLibrary([episode({ id: "lib1" })], show)
    expect(playback.getView().episode?.id).toBe("e1")
  })
})

describe("seeking before the first Play", () => {
  it("stores the place and starts there on load", async () => {
    const { playback, native, deps } = setup(episode({ positionSeconds: 10 }))
    await playback.restoreLast()
    await playback.seekTo(200)
    await playback.skip(15)
    expect(playback.getView().position).toBe(215)
    expect(deps.savePlayback).toHaveBeenLastCalledWith("e1", 215, false)
    expect(native.seekTo).not.toHaveBeenCalled()
    await playback.togglePlayPause()
    expect(native.load).toHaveBeenCalledWith(
      expect.objectContaining({ savedPosition: 215 }),
    )
  })
})

describe("a renamed episode", () => {
  it("shows its new title", async () => {
    const { playback, deps } = setup()
    await playback.playEpisode(episode(), show)
    deps.getEpisode.mockResolvedValue(episode({ title: "Renamed" }))
    await playback.refreshEpisode()
    expect(playback.getView().episode?.title).toBe("Renamed")
  })
})
