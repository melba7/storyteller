// LOFI-FORK: the podcasts section's charts (see FORK.md).
//
// The fixtures are saved answers in Apple's formats, written by hand because the cloud
// can't reach Apple. The first build checks the real addresses on the phone.
import { readFileSync } from "node:fs"

import { describe, expect, it, vi } from "vitest"

import {
  CACHE_MS,
  CHART_CATEGORIES,
  TOP_CHART,
  type ChartDeps,
  getJson,
  loadChart,
  parseCategoryChart,
  parseLookup,
  parseSavedChart,
  parseTopChart,
} from "./charts"

function fixture(name: string): unknown {
  return JSON.parse(
    readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), "utf8"),
  )
}

function answer(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status })
}

describe("parseTopChart", () => {
  it("reads the entries in order, dropping repeats and entries without an id or name", () => {
    const entries = parseTopChart(fixture("top-chart"))
    expect(entries.map((e) => e.appleId)).toEqual([
      "1200361736",
      "360084272",
      "999",
    ])
    expect(entries[0]).toEqual({
      appleId: "1200361736",
      title: "The Daily",
      author: "The New York Times",
      imageUrl: "https://example.com/art/daily/200x200bb.png",
    })
  })

  it("gives nothing for answers of the wrong shape", () => {
    expect(parseTopChart(null)).toEqual([])
    expect(parseTopChart({})).toEqual([])
    expect(parseTopChart({ feed: { results: "x" } })).toEqual([])
  })
})

describe("parseCategoryChart", () => {
  it("reads the id, name, author and the largest picture", () => {
    const entries = parseCategoryChart(fixture("category-chart"))
    expect(entries).toEqual([
      {
        appleId: "290783428",
        title: "Planet Money",
        author: "NPR",
        imageUrl: "https://example.com/pm/170.png",
      },
      {
        appleId: "1050462261",
        title: "Acquired",
        author: "Ben Gilbert and David Rosenthal",
        imageUrl: "https://example.com/acq/170.png",
      },
    ])
  })

  it("reads a chart with one show, which Apple sends as an object", () => {
    expect(parseCategoryChart(fixture("category-chart-single"))).toEqual([
      {
        appleId: "42",
        title: "Only One",
        author: "Solo",
        imageUrl: "https://example.com/one/100.png",
      },
    ])
  })

  it("gives nothing for answers of the wrong shape", () => {
    expect(parseCategoryChart([])).toEqual([])
    expect(parseCategoryChart({ feed: {} })).toEqual([])
    expect(parseCategoryChart({ feed: { entry: [1, "a", null] } })).toEqual([])
  })
})

describe("parseLookup", () => {
  it("maps Apple ids to feed links and skips results without one", () => {
    const feeds = parseLookup(fixture("lookup"))
    expect(feeds.get("1200361736")).toBe("https://feeds.example.com/the-daily")
    expect(feeds.has("999")).toBe(false)
    expect(feeds.size).toBe(4)
  })

  it("gives nothing for answers of the wrong shape", () => {
    expect(parseLookup({ results: 3 }).size).toBe(0)
    expect(parseLookup("x").size).toBe(0)
  })
})

describe("the category list", () => {
  it("has Apple's genre numbers and no repeats", () => {
    expect(CHART_CATEGORIES).toHaveLength(19)
    expect(CHART_CATEGORIES.find((c) => c.name === "True Crime")?.id).toBe(
      "1488",
    )
    expect(new Set(CHART_CATEGORIES.map((c) => c.id)).size).toBe(19)
    expect(new Set(CHART_CATEGORIES.map((c) => c.name)).size).toBe(19)
  })
})

describe("loadChart", () => {
  function setup(store: Map<string, { value: string; savedAt: number }>) {
    let time = 1_000_000
    const fetchFn = vi.fn(async (url: string) => {
      if (url.includes("/lookup")) return answer(fixture("lookup"))
      if (url.includes("marketingtools")) return answer(fixture("top-chart"))
      return answer(fixture("category-chart"))
    })
    const deps: ChartDeps = {
      fetchFn,
      cacheGet: async (key) => store.get(key) ?? null,
      cachePut: async (key, value) => {
        store.set(key, { value, savedAt: time })
      },
      now: () => time,
    }
    return {
      deps,
      fetchFn,
      advance: (ms: number) => {
        time += ms
      },
    }
  }

  it("fetches the overall chart, then the feed links with one lookup", async () => {
    const { deps, fetchFn } = setup(new Map())
    const shows = await loadChart(TOP_CHART, deps)
    expect(fetchFn.mock.calls.map((c) => c[0])).toEqual([
      "https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json",
      "https://itunes.apple.com/lookup?id=1200361736,360084272,999",
    ])
    // The show with no feed link is dropped; the order is the chart's.
    expect(shows.map((s) => [s.title, s.feedUrl])).toEqual([
      ["The Daily", "https://feeds.example.com/the-daily"],
      ["The Joe Rogan Experience", "https://feeds.example.com/jre"],
    ])
  })

  it("fetches a category's chart from its genre number", async () => {
    const { deps, fetchFn } = setup(new Map())
    const shows = await loadChart("1321", deps)
    expect(fetchFn.mock.calls[0]?.[0]).toBe(
      "https://itunes.apple.com/us/rss/toppodcasts/limit=50/genre=1321/json",
    )
    expect(shows.map((s) => s.appleId)).toEqual(["290783428", "1050462261"])
  })

  it("keeps the answer for a day, then fetches again", async () => {
    const { deps, fetchFn, advance } = setup(new Map())
    await loadChart("1321", deps)
    expect(fetchFn).toHaveBeenCalledTimes(2)
    advance(CACHE_MS - 1)
    await loadChart("1321", deps)
    expect(fetchFn).toHaveBeenCalledTimes(2)
    advance(2)
    await loadChart("1321", deps)
    expect(fetchFn).toHaveBeenCalledTimes(4)
  })

  it("keeps each chart under its own key", async () => {
    const store = new Map()
    const { deps, fetchFn } = setup(store)
    await loadChart("1321", deps)
    await loadChart(TOP_CHART, deps)
    expect([...store.keys()].sort()).toEqual(["chart:1321", "chart:top"])
    expect(fetchFn).toHaveBeenCalledTimes(4)
  })

  it("fetches again when the kept answer can't be read", async () => {
    const store = new Map([
      ["chart:1321", { value: "{oops", savedAt: 1_000_000 }],
    ])
    const { deps, fetchFn } = setup(store)
    expect((await loadChart("1321", deps)).length).toBe(2)
    expect(fetchFn).toHaveBeenCalledTimes(2)
  })

  it("still answers when the cache fails", async () => {
    const { deps } = setup(new Map())
    const shows = await loadChart("1321", {
      ...deps,
      cacheGet: async () => {
        throw new Error("no db")
      },
      cachePut: async () => {
        throw new Error("no db")
      },
    })
    expect(shows).toHaveLength(2)
  })

  it("returns the old kept list when the fetch fails, and throws when nothing is kept", async () => {
    const old = [
      {
        appleId: "1",
        title: "Old",
        author: "A",
        feedUrl: "https://x.test/rss",
        imageUrl: null,
      },
    ]
    const store = new Map([
      ["chart:1321", { value: JSON.stringify(old), savedAt: 1_000_000 }],
    ])
    const { deps, advance } = setup(store)
    advance(CACHE_MS + 1)
    const offline = async (): Promise<Response> => {
      throw new Error("offline")
    }
    expect(await loadChart("1321", { ...deps, fetchFn: offline })).toEqual(old)
    await expect(
      loadChart("1488", { ...deps, fetchFn: offline }),
    ).rejects.toThrow("Couldn't reach Apple's charts")
  })

  it("says plainly when Apple can't be reached, answers badly or sends junk", async () => {
    const base = setup(new Map()).deps
    await expect(
      loadChart("1321", {
        ...base,
        fetchFn: async () => {
          throw new Error("offline")
        },
      }),
    ).rejects.toThrow("Couldn't reach Apple's charts")
    await expect(
      loadChart("1321", { ...base, fetchFn: async () => answer({}, 503) }),
    ).rejects.toThrow("status 503")
    await expect(
      loadChart("1321", {
        ...base,
        fetchFn: async () => new Response("<html>", { status: 200 }),
      }),
    ).rejects.toThrow("couldn't be read")
  })

  it("gives an empty chart, and keeps nothing, when the answer has no shows", async () => {
    const store = new Map()
    const { deps } = setup(store)
    const empty = await loadChart("1321", {
      ...deps,
      fetchFn: async () => answer({ feed: {} }),
    })
    expect(empty).toEqual([])
    expect(store.size).toBe(0)
  })

  it("returns the old kept list, and keeps it, when the new answer has no shows or no feed links", async () => {
    const old = [
      {
        appleId: "1",
        title: "Old",
        author: "A",
        feedUrl: "https://x.test/rss",
        imageUrl: null,
      },
    ]
    const saved = JSON.stringify(old)
    for (const mode of ["no entries", "no feed links"]) {
      const store = new Map([
        ["chart:1321", { value: saved, savedAt: 1_000_000 }],
      ])
      const { deps, advance } = setup(store)
      advance(CACHE_MS + 1)
      const fetchFn = async (url: string) =>
        url.includes("/lookup")
          ? answer({ results: [] })
          : mode === "no entries"
            ? answer({ feed: {} })
            : answer(fixture("category-chart"))
      expect(await loadChart("1321", { ...deps, fetchFn })).toEqual(old)
      expect(store.get("chart:1321")?.value).toBe(saved)
    }
  })
})

describe("parseSavedChart", () => {
  it("round-trips a chart and refuses anything damaged", () => {
    const shows = [
      {
        appleId: "1",
        title: "A",
        author: "B",
        feedUrl: "https://x.test/rss",
        imageUrl: null,
      },
    ]
    expect(parseSavedChart(JSON.stringify(shows))).toEqual(shows)
    expect(parseSavedChart('[{"appleId":"1"}]')).toBeNull()
    expect(parseSavedChart("3")).toBeNull()
  })
})

describe("getJson's timeout", () => {
  const never = () => new Promise<Response>(() => {})

  it("rejects when the network never answers", async () => {
    vi.useFakeTimers()
    try {
      const result = getJson("https://x.test/a", never).then(
        () => "answered",
        (error: Error) => error.message,
      )
      await vi.advanceTimersByTimeAsync(13_000)
      expect(await result).toMatch(/Couldn't reach Apple's charts/)
    } finally {
      vi.useRealTimers()
    }
  })

  it("rejects when the headers arrive but the body never does", async () => {
    vi.useFakeTimers()
    try {
      const hangingBody = async () =>
        ({
          ok: true,
          status: 200,
          json: () => new Promise(() => {}),
        }) as Response
      const result = getJson("https://x.test/a", hangingBody).then(
        () => "answered",
        (error: Error) => error.message,
      )
      await vi.advanceTimersByTimeAsync(13_000)
      expect(await result).toMatch(/Couldn't reach Apple's charts/)
    } finally {
      vi.useRealTimers()
    }
  })

  it("lets loadChart fall back on the kept copy when the fetch hangs", async () => {
    vi.useFakeTimers()
    try {
      const old = [
        {
          appleId: "1",
          title: "Old",
          author: "",
          feedUrl: "https://x.test/f",
          imageUrl: null,
        },
      ]
      const deps: ChartDeps = {
        fetchFn: never,
        cacheGet: async () => ({
          value: JSON.stringify(old),
          savedAt: Date.now() - CACHE_MS - 1000,
        }),
        cachePut: async () => {},
      }
      const result = loadChart("hang-chart", deps)
      await vi.advanceTimersByTimeAsync(13_000)
      expect(await result).toEqual(old)
    } finally {
      vi.useRealTimers()
    }
  })
})
