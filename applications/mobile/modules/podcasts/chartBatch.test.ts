// LOFI-FORK: the podcasts section's grouped chart loading (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import {
  applyListEvent,
  startListStates,
  loadChartGroups,
  keptChart,
  type ChartListUpdate,
  type ListState,
} from "./chartBatch"
import { CACHE_MS, type ChartDeps, type ChartShow, loadChart } from "./charts"

const NOW = 10_000_000_000

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status })
}

/** A category chart of 50 shows whose ids are unique to the genre. */
function chartFor(genre: string): unknown {
  return {
    feed: {
      entry: Array.from({ length: 50 }, (_, i) => ({
        id: { attributes: { "im:id": `${genre}-${i}` } },
        "im:name": { label: `Show ${genre}-${i}` },
        "im:artist": { label: "A" },
        "im:image": [
          { label: "https://x.test/i.png", attributes: { height: "170" } },
        ],
      })),
    },
  }
}

function lookupFor(url: string): unknown {
  const ids = decodeURIComponent(url.split("id=")[1] ?? "").split(",")
  return {
    results: ids.map((id) => ({
      collectionId: id,
      feedUrl: `https://feeds.test/${id}`,
    })),
  }
}

function setup(
  store = new Map<string, { value: string; savedAt: number }>(),
  failing: (url: string) => boolean = () => false,
) {
  const calls: string[] = []
  const fetchFn = vi.fn(async (url: string) => {
    calls.push(url)
    if (failing(url)) return json({}, 500)
    if (url.includes("/lookup")) return json(lookupFor(url))
    const genre = /genre=(\d+)/.exec(url)?.[1] ?? "x"
    return json(chartFor(genre))
  })
  const deps: ChartDeps = {
    fetchFn,
    cacheGet: async (key) => store.get(key) ?? null,
    cachePut: async (key, value) => {
      store.set(key, { value, savedAt: NOW })
    },
    now: () => NOW,
  }
  return { deps, calls, store }
}

function keep(
  store: Map<string, { value: string; savedAt: number }>,
  id: string,
  age: number,
) {
  const shows: ChartShow[] = [
    {
      appleId: `${id}-0`,
      title: "Old",
      author: "A",
      feedUrl: `https://feeds.test/${id}-0`,
      imageUrl: null,
    },
  ]
  store.set(`chart:${id}`, { value: JSON.stringify(shows), savedAt: NOW - age })
  return shows
}

function collect() {
  const events: [string, ChartListUpdate][] = []
  return {
    events,
    onList: (id: string, u: ChartListUpdate) => events.push([id, u]),
  }
}

const lookups = (calls: string[]) => calls.filter((c) => c.includes("/lookup"))

describe("loadChartGroups", () => {
  it("fetches seven lists with seven feed requests and three lookups of at most 150 ids", async () => {
    const { deps, calls } = setup()
    const { events, onList } = collect()
    const ids = ["1", "2", "3", "4", "5", "6", "7"]
    await loadChartGroups(ids, deps, onList)
    expect(calls).toHaveLength(7 + 3)
    const looked = lookups(calls)
    expect(looked).toHaveLength(3)
    for (const url of looked) {
      expect(url.split("id=")[1]!.split(",").length).toBeLessThanOrEqual(150)
    }
    expect(events.filter(([, u]) => u.status === "loaded")).toHaveLength(7)
  })

  it("makes no request for a fresh kept list", async () => {
    const store = new Map()
    const shows = keep(store, "1", 1000)
    const { deps, calls } = setup(store)
    const { events, onList } = collect()
    await loadChartGroups(["1"], deps, onList)
    expect(calls).toEqual([])
    expect(events).toEqual([["1", { status: "kept", shows, fresh: true }]])
  })

  it("reports an old kept list first, then replaces it", async () => {
    const store = new Map()
    keep(store, "1", CACHE_MS + 1)
    const { deps } = setup(store)
    const { events, onList } = collect()
    await loadChartGroups(["1"], deps, onList)
    expect(events.map(([, u]) => u.status)).toEqual(["kept", "loaded"])
    expect(events[0]![1]).toMatchObject({ fresh: false })
    expect(JSON.parse(store.get("chart:1")!.value)).toHaveLength(50)
  })

  it("reports every kept list before any fetch starts", async () => {
    const store = new Map()
    keep(store, "1", CACHE_MS + 1)
    keep(store, "2", CACHE_MS + 1)
    const { deps } = setup(store)
    const { events, onList } = collect()
    await loadChartGroups(["1", "2"], deps, onList)
    expect(events.map(([, u]) => u.status)).toEqual([
      "kept",
      "kept",
      "loaded",
      "loaded",
    ])
  })

  it("lets the other lists of a group arrive when one feed answers 500", async () => {
    const store = new Map()
    const old = keep(store, "2", CACHE_MS + 1)
    const { deps } = setup(store, (url) => url.includes("genre=2/"))
    const { events, onList } = collect()
    await loadChartGroups(["1", "2", "3"], deps, onList)
    const last = (id: string) => events.filter(([i]) => i === id).at(-1)![1]
    expect(last("1").status).toBe("loaded")
    expect(last("3").status).toBe("loaded")
    expect(last("2")).toEqual({ status: "failed", shows: old })
  })

  it("fails only its own group when the lookup fails", async () => {
    const { deps, store } = setup(
      undefined,
      (url) => url.includes("/lookup") && url.includes("id=1-"),
    )
    const { events, onList } = collect()
    await loadChartGroups(["1", "2", "3", "4"], deps, onList)
    const status = (id: string) => events.find(([i]) => i === id)![1].status
    expect(["1", "2", "3"].map(status)).toEqual(["failed", "failed", "failed"])
    expect(events.find(([i]) => i === "1")![1]).toEqual({
      status: "failed",
      shows: null,
    })
    expect(status("4")).toBe("loaded")
    expect(store.has("chart:4")).toBe(true)
    expect(store.has("chart:1")).toBe(false)
  })

  it("asks no lookup for links already known from the kept copy", async () => {
    const store = new Map()
    // The kept copy knows show 1-0, which is the only entry we make the chart hold.
    keep(store, "1", CACHE_MS + 1)
    const { deps, calls } = setup(store)
    await loadChartGroups(["1"], deps, () => {})
    const ids = lookups(calls)[0]!.split("id=")[1]!.split(",")
    expect(ids).not.toContain("1-0")
    expect(ids).toHaveLength(49)
  })

  it("fetches once when two calls overlap", async () => {
    const { deps, calls } = setup()
    const a = collect()
    const b = collect()
    await Promise.all([
      loadChartGroups(["1", "2"], deps, a.onList),
      loadChartGroups(["1", "2"], deps, b.onList),
    ])
    expect(calls).toHaveLength(2 + 1)
    expect(a.events.filter(([, u]) => u.status === "loaded")).toHaveLength(2)
    expect(b.events.filter(([, u]) => u.status === "loaded")).toHaveLength(2)
  })
})

describe("loadChart and loadChartGroups together", () => {
  it("fetch a list once whichever starts first, and give the same shows", async () => {
    for (const chartFirst of [true, false]) {
      const { deps, calls } = setup()
      const { events, onList } = collect()
      const ids = ["91", "92"]
      const chart = () => loadChart("91", deps)
      const groups = () => loadChartGroups(ids, deps, onList)
      const [a, b] = chartFirst ? [chart(), groups()] : [groups(), chart()]
      await Promise.all([a, b])
      const shows = await chart()
      expect(calls.filter((c) => c.includes("genre=91"))).toHaveLength(1)
      expect(lookups(calls).filter((c) => c.includes("91-0"))).toHaveLength(1)
      const loaded = events.find(
        ([id, u]) => id === "91" && u.status === "loaded",
      )
      expect(loaded?.[1].shows).toEqual(shows)
      expect(shows).toHaveLength(50)
    }
  })
})

describe("keptChart", () => {
  it("gives null for nothing kept, damage or a failing cache", async () => {
    const { deps } = setup(
      new Map([["chart:1", { value: "{x", savedAt: NOW }]]),
    )
    expect(await keptChart("1", deps)).toBeNull()
    expect(await keptChart("2", deps)).toBeNull()
    expect(
      await keptChart("2", {
        ...deps,
        cacheGet: async () => {
          throw new Error("no db")
        },
      }),
    ).toBeNull()
  })
})

describe("applyListEvent", () => {
  const shows = [{ appleId: "1" }] as ChartShow[]
  const loading: ListState = { status: "loading" }
  const ready: ListState = { status: "ready", shows }

  it("makes a kept or loaded list ready with its shows", () => {
    expect(
      applyListEvent(loading, { status: "kept", shows, fresh: false }),
    ).toEqual(ready)
    expect(applyListEvent(loading, { status: "loaded", shows })).toEqual(ready)
  })

  it("replaces the shows of a ready list when new ones load", () => {
    const fresh = [{ appleId: "2" }] as ChartShow[]
    expect(applyListEvent(ready, { status: "loaded", shows: fresh })).toEqual({
      status: "ready",
      shows: fresh,
    })
  })

  it("keeps the shows when a fetch fails after the list was ready", () => {
    expect(applyListEvent(ready, { status: "failed", shows: null })).toBe(ready)
    expect(applyListEvent(ready, { status: "failed", shows })).toEqual(ready)
  })

  it("gives missing when a fetch fails with nothing kept", () => {
    expect(applyListEvent(loading, { status: "failed", shows: null })).toEqual({
      status: "missing",
    })
  })

  it("draws the old copy when the fetch fails but one is kept", () => {
    expect(applyListEvent(loading, { status: "failed", shows })).toEqual(ready)
  })

  it("does not turn a ready list into missing when a load comes back empty", () => {
    expect(applyListEvent(ready, { status: "loaded", shows: [] })).toBe(ready)
    expect(applyListEvent(loading, { status: "loaded", shows: [] })).toEqual({
      status: "missing",
    })
  })
})

describe("startListStates", () => {
  const ready: ListState = { status: "ready", shows: [] }
  const missing: ListState = { status: "missing" }
  const loading: ListState = { status: "loading" }

  it("turns a missing list back into a skeleton on pull to refresh and the first load", () => {
    const next = startListStates(
      { a: missing, b: ready },
      ["a", "b", "c"],
      true,
    )
    expect(next).toEqual({ a: loading, b: ready, c: loading })
  })

  it("keeps a missing list missing on a focus retry, so the page does not flicker", () => {
    const next = startListStates(
      { a: missing, b: ready },
      ["a", "b", "c"],
      false,
    )
    expect(next).toEqual({ a: missing, b: ready, c: loading })
  })
})
