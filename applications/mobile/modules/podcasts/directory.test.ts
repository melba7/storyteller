// LOFI-FORK: the podcasts section's directory search (see FORK.md).
import { readFileSync } from "node:fs"

import { describe, expect, it, vi } from "vitest"

import {
  parseDirectoryResults,
  parseEpisodeResults,
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
