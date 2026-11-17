// LOFI-FORK: the podcasts section's directory search (see FORK.md).
import { readFileSync } from "node:fs"

import { describe, expect, it, vi } from "vitest"

import {
  findAppleEpisode,
  lookupAppleEpisode,
  lookupFeedUrl,
  parseAppleLink,
  parseDirectoryResults,
  parseEpisodeResults,
  parseLookupFeed,
  pickEpisode,
  searchDirectory,
  searchDirectoryEpisodes,
} from "./directory"

const result = {
  collectionId: 101,
  collectionName: "The Show",
  artistName: "Ada Host",
  feedUrl: "https://example.com/rss",
  artworkUrl30: "https://img/30.jpg",
  artworkUrl60: "https://img/60.jpg",
  artworkUrl100: "https://img/100.jpg",
  artworkUrl600: "https://img/600.jpg",
}

describe("parseDirectoryResults", () => {
  it("reads a result and picks the largest artwork", () => {
    expect(parseDirectoryResults({ results: [result] })).toEqual([
      {
        id: "101",
        title: "The Show",
        author: "Ada Host",
        feedUrl: "https://example.com/rss",
        imageUrl: "https://img/600.jpg",
      },
    ])
  })

  it("uses the next largest artwork when the biggest is missing", () => {
    const { artworkUrl600: _, ...smaller } = result
    expect(parseDirectoryResults({ results: [smaller] })[0]?.imageUrl).toBe(
      "https://img/100.jpg",
    )
  })

  it("orders any artworkUrlNN by its number", () => {
    const shows = parseDirectoryResults({
      results: [
        {
          ...result,
          artworkUrl60: undefined,
          artworkUrl100: undefined,
          artworkUrl600: undefined,
          artworkUrl1400: "https://img/1400.jpg",
        },
      ],
    })
    expect(shows[0]?.imageUrl).toBe("https://img/1400.jpg")
  })

  it("has a null image when there is no artwork", () => {
    const shows = parseDirectoryResults({
      results: [
        { collectionId: 1, collectionName: "Bare", feedUrl: "https://e.com/r" },
      ],
    })
    expect(shows[0]).toEqual({
      id: "1",
      title: "Bare",
      author: "",
      feedUrl: "https://e.com/r",
      imageUrl: null,
    })
  })

  it("drops results without a feed address", () => {
    const { feedUrl: _, ...noFeed } = result
    expect(
      parseDirectoryResults({
        results: [
          noFeed,
          { ...result, feedUrl: "" },
          { ...result, feedUrl: 5 },
        ],
      }),
    ).toEqual([])
  })

  it("falls back to trackName and the feed address for the id", () => {
    const shows = parseDirectoryResults({
      results: [{ trackName: "Track", feedUrl: "https://e.com/r" }],
    })
    expect(shows[0]).toMatchObject({ id: "https://e.com/r", title: "Track" })
  })

  it("survives nonsense", () => {
    expect(parseDirectoryResults(null)).toEqual([])
    expect(parseDirectoryResults("x")).toEqual([])
    expect(parseDirectoryResults({})).toEqual([])
    expect(parseDirectoryResults({ results: "no" })).toEqual([])
    expect(parseDirectoryResults({ results: [null, 3, "x"] })).toEqual([])
  })
})

describe("searchDirectory", () => {
  it("asks Apple's directory with the term encoded", async () => {
    const fetchFn = vi.fn(() =>
      Promise.resolve(
        new Response(JSON.stringify({ results: [result] }), { status: 200 }),
      ),
    )
    const shows = await searchDirectory("true crime & more", fetchFn)
    expect(fetchFn).toHaveBeenCalledWith(
      "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=25&term=true%20crime%20%26%20more",
    )
    expect(shows).toHaveLength(1)
  })

  it("does not ask for an empty term", async () => {
    const fetchFn = vi.fn()
    expect(await searchDirectory("   ", fetchFn)).toEqual([])
    expect(fetchFn).not.toHaveBeenCalled()
  })

  it("explains a failed request", async () => {
    await expect(
      searchDirectory("x", () =>
        Promise.resolve(new Response("", { status: 503 })),
      ),
    ).rejects.toThrow("Apple's podcast directory answered with status 503.")
  })

  it("explains a missing connection", async () => {
    await expect(
      searchDirectory("x", () =>
        Promise.reject(new TypeError("Network request failed")),
      ),
    ).rejects.toThrow(
      "Couldn't reach Apple's podcast directory. Check your connection.",
    )
  })

  it("explains an answer that is not JSON", async () => {
    await expect(
      searchDirectory("x", () =>
        Promise.resolve(new Response("<html>", { status: 200 })),
      ),
    ).rejects.toThrow(
      "Apple's podcast directory sent an answer that couldn't be read.",
    )
  })
})

// The saved answer is written by hand in Apple's format, because the cloud can't reach Apple.
describe("parseEpisodeResults", () => {
  const saved: unknown = JSON.parse(
    readFileSync(
      new URL("./fixtures/episode-search.json", import.meta.url),
      "utf8",
    ),
  )

  it("reads the title, show, date, length, feed, guid and audio address", () => {
    expect(parseEpisodeResults(saved)[0]).toEqual({
      id: "1000700001",
      title: "The Moon Base Episode",
      showTitle: "Space Talk",
      publishedAt: Date.parse("2023-01-02T10:30:00Z"),
      durationSeconds: 2535,
      feedUrl: "https://feeds.example.com/space-talk",
      guid: "abc-123",
      audioUrl: "https://cdn.example.com/moon.mp3?src=apple",
      imageUrl: "https://img/600.jpg",
    })
  })

  it("leaves out what Apple doesn't give, and drops results without a title or feed", () => {
    const episodes = parseEpisodeResults(saved)
    expect(episodes).toHaveLength(2)
    expect(episodes[1]).toMatchObject({
      title: "Bare answer",
      publishedAt: null,
      durationSeconds: null,
      guid: null,
      audioUrl: null,
      imageUrl: null,
    })
  })

  it("gives nothing for answers of the wrong shape", () => {
    expect(parseEpisodeResults(null)).toEqual([])
    expect(parseEpisodeResults({ results: "x" })).toEqual([])
  })
})

describe("searchDirectoryEpisodes", () => {
  it("asks for podcast episodes with the words encoded, and reads the answer", async () => {
    const fetchFn = vi.fn(
      async () =>
        new Response(JSON.stringify({ results: [] }), { status: 200 }),
    )
    expect(await searchDirectoryEpisodes(" moon & base ", fetchFn)).toEqual([])
    expect(fetchFn).toHaveBeenCalledWith(
      "https://itunes.apple.com/search?media=podcast&entity=podcastEpisode&limit=50&term=moon%20%26%20base",
    )
  })

  it("asks nothing for empty words", async () => {
    const fetchFn = vi.fn()
    expect(await searchDirectoryEpisodes("  ", fetchFn)).toEqual([])
    expect(fetchFn).not.toHaveBeenCalled()
  })

  it("says plainly when Apple can't be reached or answers badly", async () => {
    await expect(
      searchDirectoryEpisodes("x", async () => {
        throw new Error("offline")
      }),
    ).rejects.toThrow("Couldn't reach")
    await expect(
      searchDirectoryEpisodes(
        "x",
        async () => new Response("", { status: 500 }),
      ),
    ).rejects.toThrow("status 500")
  })
})

// MARK: Apple Podcasts share links

describe("parseAppleLink", () => {
  it("reads the show id from links of different countries", () => {
    for (const link of [
      "https://podcasts.apple.com/us/podcast/space-talk/id1535809341",
      "https://podcasts.apple.com/gb/podcast/space-talk/id1535809341",
      "https://podcasts.apple.com/de/podcast/raumfahrt-gespr%C3%A4che/id1535809341",
      "https://podcasts.apple.com/jp/podcast/%E5%AE%87%E5%AE%99/id1535809341",
    ]) {
      expect(parseAppleLink(link)).toEqual({
        showId: "1535809341",
        episodeId: null,
      })
    }
  })

  it("accepts a link without the country or the slug", () => {
    expect(
      parseAppleLink("https://podcasts.apple.com/podcast/id1535809341"),
    ).toEqual({
      showId: "1535809341",
      episodeId: null,
    })
    expect(
      parseAppleLink("https://podcasts.apple.com/us/podcast/id1535809341")
        ?.showId,
    ).toBe("1535809341")
    expect(
      parseAppleLink("https://podcasts.apple.com/id1535809341")?.showId,
    ).toBe("1535809341")
  })

  it("keeps the episode id from ?i= and ignores other parameters", () => {
    expect(
      parseAppleLink(
        "https://podcasts.apple.com/us/podcast/space-talk/id1535809341?i=1000700001",
      ),
    ).toEqual({ showId: "1535809341", episodeId: "1000700001" })
    expect(
      parseAppleLink(
        "https://podcasts.apple.com/us/podcast/space-talk/id1535809341?uo=4&i=1000700001&l=en",
      )?.episodeId,
    ).toBe("1000700001")
    expect(
      parseAppleLink(
        "https://podcasts.apple.com/us/podcast/space-talk/id1535809341?uo=4",
      )?.episodeId,
    ).toBeNull()
    expect(
      parseAppleLink(
        "https://podcasts.apple.com/us/podcast/x/id1535809341?i=abc",
      )?.episodeId,
    ).toBeNull()
  })

  it("accepts the itunes host, http, a fragment and spaces around it", () => {
    expect(
      parseAppleLink(
        "https://itunes.apple.com/us/podcast/space-talk/id1535809341?mt=2",
      ),
    ).toEqual({ showId: "1535809341", episodeId: null })
    expect(
      parseAppleLink("http://podcasts.apple.com/us/podcast/x/id77")?.showId,
    ).toBe("77")
    expect(
      parseAppleLink("  https://podcasts.apple.com/us/podcast/x/id77#top \n")
        ?.showId,
    ).toBe("77")
    expect(
      parseAppleLink("HTTPS://Podcasts.Apple.com/us/podcast/x/ID77")?.showId,
    ).toBe("77")
  })

  it("rejects other hosts, links without an id and ids followed by letters", () => {
    for (const link of [
      "",
      "https://example.com/feed.xml",
      "https://example.com/podcast/id1535809341",
      "https://podcasts.apple.com.evil.example/us/podcast/x/id1535809341",
      "https://notpodcasts.apple.com/us/podcast/x/id1535809341",
      "https://podcasts.apple.com/us/podcast/space-talk",
      "https://podcasts.apple.com/us/podcast/space-talk/id",
      "https://podcasts.apple.com/us/podcast/space-talk/id1535809341abc",
      "https://podcasts.apple.com/us/podcast/space-talk/idabc",
      "ftp://podcasts.apple.com/us/podcast/x/id1535809341",
      "podcasts.apple.com/us/podcast/x/id1535809341",
      "see https://podcasts.apple.com/us/podcast/x/id1535809341",
    ]) {
      expect(parseAppleLink(link), link).toBeNull()
    }
  })
})

describe("the feed address from Apple's lookup", () => {
  const fixture = (name: string): unknown =>
    JSON.parse(
      readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), "utf8"),
    )

  it("reads the feed address of the show", () => {
    expect(parseLookupFeed(fixture("lookup-show"), "1535809341")).toBe(
      "https://feeds.example.com/space-talk",
    )
  })

  it("says so when Apple lists no feed for the show", () => {
    expect(() =>
      parseLookupFeed(fixture("lookup-no-feed"), "1535809341"),
    ).toThrow("Apple doesn't list a feed for this show")
  })

  it("says so when Apple has no show for the link", () => {
    expect(() => parseLookupFeed({ resultCount: 0, results: [] }, "1")).toThrow(
      "no show for this link",
    )
    expect(() => parseLookupFeed("nonsense", "1")).toThrow(
      "no show for this link",
    )
  })

  it("asks the lookup for the show and reads the answer", async () => {
    const fetchFn = vi.fn(
      async () =>
        new Response(JSON.stringify(fixture("lookup-show")), { status: 200 }),
    )
    expect(await lookupFeedUrl("1535809341", fetchFn)).toBe(
      "https://feeds.example.com/space-talk",
    )
    expect(fetchFn).toHaveBeenCalledWith(
      "https://itunes.apple.com/lookup?id=1535809341&entity=podcast",
    )
  })

  it("says plainly when Apple can't be reached", async () => {
    await expect(
      lookupFeedUrl("1", async () => {
        throw new Error("offline")
      }),
    ).rejects.toThrow("Couldn't reach")
    await expect(
      lookupFeedUrl("1", async () => new Response("", { status: 503 })),
    ).rejects.toThrow("status 503")
  })
})

describe("the episode a share link named", () => {
  const answer = JSON.parse(
    readFileSync(
      new URL("./fixtures/lookup-episodes.json", import.meta.url),
      "utf8",
    ),
  ) as unknown

  it("matches Apple's episode id to the feed's id", () => {
    expect(findAppleEpisode(answer, "1000700001")).toEqual({
      guid: "abc-123",
      audioUrl: "https://cdn.example.com/moon.mp3?src=apple",
    })
  })

  it("falls back to the audio address when Apple gives no id", () => {
    expect(findAppleEpisode(answer, "1000700002")).toEqual({
      guid: null,
      audioUrl: "https://cdn.example.com/only.mp3",
    })
  })

  it("finds nothing for an unlisted episode or one with nothing to match on", () => {
    expect(findAppleEpisode(answer, "42")).toBeNull()
    expect(findAppleEpisode(answer, "1000700003")).toBeNull()
    expect(findAppleEpisode("nonsense", "1000700001")).toBeNull()
  })

  it("asks for 200 episodes of the show", async () => {
    const fetchFn = vi.fn(
      async () => new Response(JSON.stringify(answer), { status: 200 }),
    )
    expect(
      await lookupAppleEpisode("1535809341", "1000700001", fetchFn),
    ).toMatchObject({
      guid: "abc-123",
    })
    expect(fetchFn).toHaveBeenCalledWith(
      "https://itunes.apple.com/lookup?id=1535809341&entity=podcastEpisode&limit=200",
    )
  })

  it("is null when Apple can't be reached, so the show opens instead", async () => {
    expect(
      await lookupAppleEpisode("1", "2", async () => {
        throw new Error("offline")
      }),
    ).toBeNull()
  })
})

describe("pickEpisode", () => {
  const stored = [
    { id: "e1", guid: "abc-123", audioUrl: "https://cdn.example.com/moon.mp3" },
    { id: "e2", guid: "g2", audioUrl: "https://cdn.example.com/only.mp3" },
  ]

  it("prefers the feed's id", () => {
    expect(
      pickEpisode(stored, {
        guid: "abc-123",
        audioUrl: "https://cdn.example.com/only.mp3",
      }),
    ).toBe("e1")
  })

  it("falls back to the audio address", () => {
    expect(
      pickEpisode(stored, {
        guid: "nope",
        audioUrl: "https://cdn.example.com/only.mp3",
      }),
    ).toBe("e2")
    expect(
      pickEpisode(stored, {
        guid: null,
        audioUrl: "https://cdn.example.com/only.mp3",
      }),
    ).toBe("e2")
  })

  it("is null when the feed does not have the episode", () => {
    expect(pickEpisode(stored, { guid: "zzz", audioUrl: null })).toBeNull()
    expect(pickEpisode([], { guid: "abc-123", audioUrl: null })).toBeNull()
  })
})
