// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type AppleExport,
  feedKey,
  parseAppleExport,
  parseSeen,
  planFollows,
  planPlayed,
} from "./applePodcasts"

const file = (
  shows: string[],
  finished: [string, string][] = [],
): AppleExport => ({
  shows: shows.map((feed) => ({ feed, title: null })),
  finished: finished.map(([feed, guid]) => ({ feed, guid })),
})

describe("feedKey", () => {
  it("matches spellings of one address", () => {
    const key = feedKey("https://example.com/feed.xml")
    expect(feedKey("http://example.com/feed.xml")).toBe(key)
    expect(feedKey("HTTPS://Example.COM/feed.xml#top")).toBe(key)
    expect(feedKey("https://www.example.com/feed.xml")).toBe(key)
    expect(feedKey("feed://example.com/feed.xml")).toBe(key)
    expect(feedKey("https://example.com/feed/")).toBe(
      feedKey("https://example.com/feed"),
    )
    expect(feedKey("https://example.com/feed/?a=1")).toBe(
      feedKey("https://example.com/feed?a=1"),
    )
  })

  it("keeps different feeds apart", () => {
    expect(feedKey("https://example.com/a")).not.toBe(
      feedKey("https://example.com/b"),
    )
    expect(feedKey("https://example.com/feed?show=1")).not.toBe(
      feedKey("https://example.com/feed?show=2"),
    )
    expect(feedKey("https://example.com/Feed")).not.toBe(
      feedKey("https://example.com/feed"),
    )
  })
})

describe("parseAppleExport", () => {
  const text = (value: unknown) => JSON.stringify(value)

  it("reads the version 1 file", () => {
    const parsed = parseAppleExport(
      text({
        version: 1,
        writtenAt: 1,
        shows: [{ feed: "https://a.test/f", title: "A" }],
        finished: [{ feed: "https://a.test/f", guid: "g1" }],
      }),
    )
    expect(parsed).toEqual({
      shows: [{ feed: "https://a.test/f", title: "A" }],
      finished: [{ feed: "https://a.test/f", guid: "g1" }],
    })
  })

  it("skips a missing, broken or other-version file", () => {
    expect(parseAppleExport(null)).toBeNull()
    expect(parseAppleExport("not json")).toBeNull()
    expect(parseAppleExport(text([]))).toBeNull()
    expect(
      parseAppleExport(text({ version: 2, shows: [], finished: [] })),
    ).toBeNull()
    expect(parseAppleExport(text({ version: 1, shows: [] }))).toBeNull()
  })

  it("drops entries that are not usable", () => {
    const parsed = parseAppleExport(
      text({
        version: 1,
        shows: [{ feed: "" }, { feed: 3 }, "x", { feed: "https://a.test/f" }],
        finished: [
          { feed: "https://a.test/f", guid: "" },
          { feed: "https://a.test/f" },
          { feed: "https://a.test/f", guid: "g" },
        ],
      }),
    )
    expect(parsed?.shows).toEqual([{ feed: "https://a.test/f", title: null }])
    expect(parsed?.finished).toEqual([{ feed: "https://a.test/f", guid: "g" }])
  })
})

describe("planFollows", () => {
  it("subscribes to everything on the first run", () => {
    const plan = planFollows(
      file(["https://a.test/f", "https://b.test/f"]),
      [],
      [],
    )
    expect(plan.subscribe.map((show) => show.feed)).toEqual([
      "https://a.test/f",
      "https://b.test/f",
    ])
  })

  it("only subscribes to shows it has not seen", () => {
    const seen = [feedKey("https://a.test/f")]
    const plan = planFollows(
      file(["https://a.test/f", "https://b.test/f"]),
      seen,
      [],
    )
    expect(plan.subscribe.map((show) => show.feed)).toEqual([
      "https://b.test/f",
    ])
  })

  it("never adds a show again that was unsubscribed", () => {
    // Seen before, not in the library now.
    const plan = planFollows(
      file(["https://a.test/f/"]),
      [feedKey("http://www.a.test/f")],
      [],
    )
    expect(plan.subscribe).toEqual([])
  })

  it("does not subscribe to a show already in the library, and remembers it", () => {
    const plan = planFollows(
      file(["https://a.test/f"]),
      [],
      ["http://a.test/f/"],
    )
    expect(plan.subscribe).toEqual([])
    expect(plan.seen).toEqual([feedKey("https://a.test/f")])
  })

  it("leaves a show alone that Apple no longer lists", () => {
    const seen = [feedKey("https://a.test/f"), feedKey("https://gone.test/f")]
    const plan = planFollows(file(["https://a.test/f"]), seen, [
      "https://gone.test/f",
    ])
    expect(plan.subscribe).toEqual([])
    expect(plan.seen).toEqual(seen)
  })

  it("lists a show once when the file repeats it", () => {
    const plan = planFollows(
      file(["https://a.test/f", "http://a.test/f/"]),
      [],
      [],
    )
    expect(plan.subscribe).toHaveLength(1)
  })
})

describe("planPlayed", () => {
  const library = [
    { id: "s1", feedUrl: "https://a.test/f" },
    { id: "s2", feedUrl: "https://b.test/f" },
  ]

  it("groups finished guids by the matching show", () => {
    const plan = planPlayed(
      file(
        [],
        [
          ["http://www.a.test/f/", "g1"],
          ["https://a.test/f", "g2"],
          ["https://a.test/f", "g1"],
          ["https://b.test/f", "g3"],
        ],
      ),
      library,
    )
    expect(plan).toEqual([
      { showId: "s1", guids: ["g1", "g2"] },
      { showId: "s2", guids: ["g3"] },
    ])
  })

  it("ignores shows that are not in the library", () => {
    expect(
      planPlayed(file([], [["https://other.test/f", "g"]]), library),
    ).toEqual([])
  })
})

describe("parseSeen", () => {
  it("reads a list and shrugs off bad data", () => {
    expect(parseSeen('["a","b"]')).toEqual(["a", "b"])
    expect(parseSeen('["a",3]')).toEqual(["a"])
    expect(parseSeen("{}")).toEqual([])
    expect(parseSeen("nope")).toEqual([])
    expect(parseSeen(null)).toEqual([])
  })
})
