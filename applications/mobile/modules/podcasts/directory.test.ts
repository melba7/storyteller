// LOFI-FORK: the podcasts section's directory search (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import { parseDirectoryResults, searchDirectory } from "./directory"

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
