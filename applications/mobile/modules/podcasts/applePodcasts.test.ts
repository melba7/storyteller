// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type AppleExport,
  feedKey,
  dueShows,
  findShowByFeed,
  parseFailures,
  parseAppleExport,
  parseSeen,
  planFollows,
  planPlayed,
  pendingGuids,
  planPlayedOnce,
  settleArrival,
  withLibraryFeeds,
  withSeen,
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

describe("planPlayedOnce", () => {
  const library = [{ id: "s1", feedUrl: "https://example.com/feed" }]
  const file = {
    shows: [],
    finished: [
      { feed: "http://www.example.com/feed/", guid: "g1" },
      { feed: "https://example.com/feed", guid: "g2" },
      { feed: "https://other.example.com/feed", guid: "g3" },
    ],
  }

  it("marks each finished episode once, then leaves it alone", () => {
    const first = planPlayedOnce(file, library, [])
    expect(first.plays).toEqual([{ showId: "s1", guids: ["g1", "g2"] }])
    const second = planPlayedOnce(file, library, first.applied)
    expect(second.plays).toEqual([])
    expect(second.applied.sort()).toEqual(first.applied.sort())
  })

  it("keeps a pair for a show not in the library for when it arrives", () => {
    const first = planPlayedOnce(file, library, [])
    expect(first.applied).toHaveLength(2)
    const later = planPlayedOnce(
      file,
      [...library, { id: "s2", feedUrl: "https://other.example.com/feed" }],
      first.applied,
    )
    expect(later.plays).toEqual([{ showId: "s2", guids: ["g3"] }])
  })

  it("forgets pairs that are no longer in the file", () => {
    const first = planPlayedOnce(file, library, [])
    const smaller = { shows: [], finished: [file.finished[1] as never] }
    expect(
      planPlayedOnce(smaller, library, first.applied).applied,
    ).toHaveLength(1)
  })
})

describe("planPlayedOnce for episodes the phone does not have yet", () => {
  const library = [{ id: "s1", feedUrl: "https://example.com/feed" }]
  const file = {
    shows: [],
    finished: [
      { feed: "https://example.com/feed", guid: "have" },
      { feed: "https://example.com/feed", guid: "later" },
    ],
  }
  const has = (_feed: string, guid: string) => guid === "have"

  it("marks what the phone has and keeps the rest pending, not applied", () => {
    const plan = planPlayedOnce(file, library, [], has)
    expect(plan.plays).toEqual([{ showId: "s1", guids: ["have"] }])
    expect(plan.applied).toEqual(["example.com/feed\nhave"])
    expect(plan.pending).toEqual(["example.com/feed\nlater"])
  })

  it("marks the pending one when it is there on a later sync", () => {
    const first = planPlayedOnce(file, library, [], has)
    const second = planPlayedOnce(file, library, first.applied, () => true)
    expect(second.plays).toEqual([{ showId: "s1", guids: ["later"] }])
    expect(second.pending).toEqual([])
  })

  it("finds the pending guids of one show, however its feed is spelled", () => {
    const pending = ["example.com/feed\nlater", "other.test/f\nx"]
    expect([...pendingGuids(pending, "http://www.example.com/feed/")]).toEqual([
      "later",
    ])
    expect(pendingGuids(pending, "https://nobody.test/f").size).toBe(0)
  })

  it("moves an episode that arrived from pending to applied", () => {
    const settled = settleArrival(
      ["example.com/feed\nlater", "other.test/f\nx"],
      ["example.com/feed\nhave"],
      "https://example.com/feed",
      ["later"],
    )
    expect(settled.pending).toEqual(["other.test/f\nx"])
    expect(settled.applied).toEqual([
      "example.com/feed\nhave",
      "example.com/feed\nlater",
    ])
  })
})

describe("planFollows and a show the listener already has", () => {
  const apple = (feed: string, title: string | null) => ({
    shows: [{ feed, title }],
    finished: [],
  })

  it("does not subscribe to a show whose title is already in the library", () => {
    const plan = planFollows(
      apple("https://moved.example.com/feed", "  The Daily "),
      [],
      ["https://old.example.com/feed"],
      ["the daily"],
    )
    expect(plan.subscribe).toEqual([])
    expect(plan.seen).toEqual(["moved.example.com/feed"])
  })

  it("still subscribes when no title matches or the file has none", () => {
    const titles = ["the daily"]
    expect(
      planFollows(apple("https://a.test/f", "Another"), [], [], titles)
        .subscribe,
    ).toHaveLength(1)
    expect(
      planFollows(apple("https://a.test/f", null), [], [], titles).subscribe,
    ).toHaveLength(1)
  })
})

describe("withSeen", () => {
  it("adds a feed's key once", () => {
    expect(withSeen(["a.test/f"], "https://B.test/f/")).toEqual([
      "a.test/f",
      "b.test/f",
    ])
    expect(withSeen(["b.test/f"], "http://www.b.test/f")).toEqual(["b.test/f"])
  })
})

describe("findShowByFeed", () => {
  const shows = [
    { id: "a", feedUrl: "https://example.com/feed" },
    { id: "own", feedUrl: "local:files" },
  ]
  it("finds a show whatever the spelling of its address", () => {
    expect(findShowByFeed(shows, "http://www.EXAMPLE.com/feed/")?.id).toBe("a")
    expect(findShowByFeed(shows, "https://example.com/other")).toBeUndefined()
  })
})

describe("dueShows", () => {
  const day = 24 * 3_600_000
  const shows = [
    { feed: "https://a.test/f", title: null },
    { feed: "https://b.test/f", title: null },
  ]

  it("leaves out a show that failed less than a day ago", () => {
    const failed = { "a.test/f": 1000 }
    expect(dueShows(shows, failed, 1000 + day - 1).map((s) => s.feed)).toEqual([
      "https://b.test/f",
    ])
    expect(dueShows(shows, failed, 1000 + day).map((s) => s.feed)).toEqual([
      "https://a.test/f",
      "https://b.test/f",
    ])
  })
})

describe("parseFailures", () => {
  it("reads the saved times and shrugs off bad data", () => {
    expect(parseFailures('{"a.test/f":5,"b":"x","c":null}')).toEqual({
      "a.test/f": 5,
    })
    expect(parseFailures("nope")).toEqual({})
    expect(parseFailures(null)).toEqual({})
    expect(parseFailures("[1]")).toEqual({})
  })
})

describe("an unsubscribed show remembered by its title too", () => {
  it("is not followed again under another address", () => {
    const seen = withSeen([], "https://old.test/f", " The Daily ")
    expect(seen).toEqual(["old.test/f", "title:the daily"])
    const plan = planFollows(
      {
        shows: [{ feed: "https://apple.test/f", title: "the daily" }],
        finished: [],
      },
      seen,
      [],
    )
    expect(plan.subscribe).toEqual([])
  })

  it("does not remember an empty title", () => {
    expect(withSeen([], "https://old.test/f", "  ")).toEqual(["old.test/f"])
  })
})

describe("withLibraryFeeds", () => {
  const library = [
    { id: "s1", feedUrl: "https://lib.test/feed", title: "The Daily" },
  ]
  const apple: AppleExport = {
    shows: [{ feed: "https://apple.test/feed", title: " the daily " }],
    finished: [
      { feed: "https://apple.test/feed", guid: "g1" },
      { feed: "https://other.test/feed", guid: "g2" },
    ],
  }

  it("points a finished episode of a title-matched show at the library's address", () => {
    const resolved = withLibraryFeeds(apple, library)
    expect(resolved.finished).toEqual([
      { feed: "https://lib.test/feed", guid: "g1" },
      { feed: "https://other.test/feed", guid: "g2" },
    ])
  })

  it("leaves a feed key that matches alone, and marks the title-matched show played", () => {
    const same = withLibraryFeeds(
      {
        shows: [],
        finished: [{ feed: "http://www.lib.test/feed", guid: "g" }],
      },
      library,
    )
    expect(same.finished[0]?.feed).toBe("http://www.lib.test/feed")
    const plan = planPlayedOnce(withLibraryFeeds(apple, library), library, [])
    expect(plan.plays).toEqual([{ showId: "s1", guids: ["g1"] }])
  })
})
