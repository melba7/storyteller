// LOFI-FORK: the podcasts section's top episodes chart (see FORK.md).
import { readFileSync } from "node:fs"

import { describe, expect, it, vi } from "vitest"

import { CACHE_MS, type ChartDeps } from "./charts"
import {
  EPISODES_CHART,
  EPISODE_COUNT,
  applyEpisodesEvent,
  joinEpisodes,
  loadTopEpisodes,
  parseShowLookup,
  parseTopEpisodes,
  type EpisodesState,
  type EpisodesUpdate,
} from "./topEpisodes"

const read = (name: string): unknown =>
  JSON.parse(
    readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"),
  )
const chart = read("top-episodes.json")
const lookup = read("top-episodes-lookup.json")

describe("parseTopEpisodes", () => {
  it("reads the real answer in rank order with the show id from the address", () => {
    const entries = parseTopEpisodes(chart)
    expect(entries.map((e) => e.episodeId)).toEqual([
      "1000801585453",
      "1000802201557",
      "1000802201223",
    ])
    expect(entries.map((e) => e.showId)).toEqual([
      "1322200189",
      "1089022756",
      "1043699613",
    ])
    expect(entries[0]).toMatchObject({
      title: "MISSING: Lisa Jameson",
      showName: "Audiochuck",
    })
    expect(entries[0]!.imageUrl).toContain("100x100bb")
  })

  it("gives an empty list for a wrong shape, and skips entries it cannot use", () => {
    expect(parseTopEpisodes(null)).toEqual([])
    expect(parseTopEpisodes({ feed: { results: "no" } })).toEqual([])
    const odd = {
      feed: {
        results: [
          { id: "1", name: "No address" },
          { id: "2", name: "Bad", url: "https://podcasts.apple.com/x" },
          { id: "3", name: "Ok", url: "https://p.test/a/id77?i=3" },
        ],
      },
    }
    expect(parseTopEpisodes(odd).map((e) => e.episodeId)).toEqual(["3"])
  })
})

describe("joinEpisodes", () => {
  it("adds the feed link and show name, and drops a show the lookup lacks", () => {
    const joined = joinEpisodes(
      parseTopEpisodes(chart),
      parseShowLookup(lookup),
    )
    expect(joined.map((e) => e.episodeId)).toEqual([
      "1000801585453",
      "1000802201557",
    ])
    expect(joined[0]).toMatchObject({
      showName: "Crime Junkie",
      feedUrl: "https://feeds.simplecast.com/qm_9xx0g",
    })
    expect(joined[1]!.showName).toBe("Pardon My Take")
  })

  it("keeps 30", () => {
    const entries = Array.from({ length: 40 }, (_, i) => ({
      episodeId: `e${i}`,
      title: `T${i}`,
      showId: "5",
      showName: "S",
      imageUrl: null,
    }))
    const feeds = new Map([["5", { feedUrl: "f", name: "S", imageUrl: null }]])
    expect(joinEpisodes(entries, feeds)).toHaveLength(EPISODE_COUNT)
  })
})

const NOW = 10_000_000_000

function setup(kept?: { value: string; savedAt: number }, failing = false) {
  const store = new Map<string, { value: string; savedAt: number }>()
  if (kept) store.set(`chart:${EPISODES_CHART}`, kept)
  const calls: string[] = []
  const fetchFn = vi.fn(async (url: string) => {
    calls.push(url)
    if (failing) throw new Error("offline")
    const body = url.includes("lookup") ? lookup : chart
    return new Response(JSON.stringify(body))
  })
  const deps: ChartDeps = {
    fetchFn,
    now: () => NOW,
    cacheGet: async (key) => store.get(key) ?? null,
    cachePut: async (key, value) => {
      store.set(key, { value, savedAt: NOW })
    },
  }
  const updates: EpisodesUpdate[] = []
  return {
    deps,
    store,
    calls,
    updates,
    onUpdate: (u: EpisodesUpdate) => updates.push(u),
  }
}

const savedEpisode = {
  episodeId: "old",
  title: "Old",
  showId: "1",
  showName: "S",
  imageUrl: null,
  feedUrl: "https://feeds.test/old",
}

describe("loadTopEpisodes", () => {
  it("fetches the chart and one lookup, then keeps the result", async () => {
    const t = setup()
    await loadTopEpisodes(t.deps, t.onUpdate)
    expect(t.calls).toHaveLength(2)
    expect(t.calls[0]).toContain("podcast-episodes.json")
    expect(t.calls[1]).toContain("lookup?id=1322200189,1089022756,1043699613")
    expect(t.updates).toHaveLength(1)
    expect(t.updates[0]).toMatchObject({ status: "loaded" })
    expect(t.store.has("chart:top-episodes")).toBe(true)
  })

  it("draws a fresh kept copy with no request", async () => {
    const t = setup({
      value: JSON.stringify([savedEpisode]),
      savedAt: NOW - CACHE_MS + 1000,
    })
    await loadTopEpisodes(t.deps, t.onUpdate)
    expect(t.calls).toHaveLength(0)
    expect(t.updates).toEqual([
      { status: "kept", episodes: [savedEpisode], fresh: true },
    ])
  })

  it("reports an old copy first, then the new answer", async () => {
    const t = setup({
      value: JSON.stringify([savedEpisode]),
      savedAt: NOW - CACHE_MS - 1,
    })
    await loadTopEpisodes(t.deps, t.onUpdate)
    expect(t.updates.map((u) => u.status)).toEqual(["kept", "loaded"])
  })

  it("keeps the old copy when the fetch fails, and reports nothing kept as null", async () => {
    const old = setup(
      { value: JSON.stringify([savedEpisode]), savedAt: NOW - CACHE_MS - 1 },
      true,
    )
    await loadTopEpisodes(old.deps, old.onUpdate)
    expect(old.updates.at(-1)).toEqual({
      status: "failed",
      episodes: [savedEpisode],
    })
    const none = setup(undefined, true)
    await loadTopEpisodes(none.deps, none.onUpdate)
    expect(none.updates).toEqual([{ status: "failed", episodes: null }])
  })

  it("shares one fetch between two callers at once", async () => {
    const t = setup()
    const second: EpisodesUpdate[] = []
    await Promise.all([
      loadTopEpisodes(t.deps, t.onUpdate),
      loadTopEpisodes(t.deps, (u) => second.push(u)),
    ])
    expect(t.calls).toHaveLength(2)
    expect(second.at(-1)).toMatchObject({ status: "loaded" })
  })
})

describe("applyEpisodesEvent", () => {
  it("never takes drawn episodes away, and says missing with nothing", () => {
    const ready: EpisodesState = { status: "ready", episodes: [savedEpisode] }
    expect(
      applyEpisodesEvent(ready, { status: "failed", episodes: null }),
    ).toBe(ready)
    expect(
      applyEpisodesEvent(
        { status: "loading" },
        { status: "failed", episodes: null },
      ),
    ).toEqual({ status: "missing" })
    expect(
      applyEpisodesEvent(
        { status: "loading" },
        { status: "loaded", episodes: [savedEpisode] },
      ),
    ).toEqual({ status: "ready", episodes: [savedEpisode] })
  })
})
