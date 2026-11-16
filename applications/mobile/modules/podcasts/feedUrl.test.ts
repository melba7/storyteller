// LOFI-FORK: the podcasts section's feed link reader (see FORK.md).
import { describe, expect, it } from "vitest"

import { normalizeFeedUrl } from "./feedUrl"

describe("normalizeFeedUrl", () => {
  it("keeps an https link and trims it", () => {
    expect(normalizeFeedUrl("  https://example.com/feed.xml \n")).toBe(
      "https://example.com/feed.xml",
    )
  })

  it("keeps http", () => {
    expect(normalizeFeedUrl("http://example.com/feed.xml")).toBe(
      "http://example.com/feed.xml",
    )
  })

  it("turns the podcast apps' schemes into https", () => {
    for (const scheme of ["feed", "itpc", "pcast", "FEED"]) {
      expect(normalizeFeedUrl(`${scheme}://example.com/rss`)).toBe(
        "https://example.com/rss",
      )
    }
  })

  it("reads feed: in front of a full link", () => {
    expect(normalizeFeedUrl("feed:https://example.com/rss")).toBe(
      "https://example.com/rss",
    )
    expect(normalizeFeedUrl("feed:http://example.com/rss")).toBe(
      "http://example.com/rss",
    )
  })

  it("adds https when the scheme is missing", () => {
    expect(normalizeFeedUrl("example.com/rss.xml")).toBe(
      "https://example.com/rss.xml",
    )
    expect(normalizeFeedUrl("//example.com/rss.xml")).toBe(
      "https://example.com/rss.xml",
    )
  })

  it("lowercases the host, drops the fragment and gives a bare host a path", () => {
    expect(normalizeFeedUrl("HTTPS://Example.COM")).toBe("https://example.com/")
    expect(normalizeFeedUrl("https://example.com/Feed?a=B#top")).toBe(
      "https://example.com/Feed?a=B",
    )
  })

  it("keeps a port and a private feed's login", () => {
    expect(normalizeFeedUrl("https://me:secret@Example.com:8080/p/rss")).toBe(
      "https://me:secret@example.com:8080/p/rss",
    )
  })

  it("makes two spellings of one feed equal", () => {
    expect(normalizeFeedUrl("feed://Example.com/rss")).toBe(
      normalizeFeedUrl("https://example.com/rss"),
    )
  })

  it("rejects what is not a link, with a message to read", () => {
    expect(() => normalizeFeedUrl("")).toThrow("Paste a podcast link.")
    expect(() => normalizeFeedUrl("   ")).toThrow("Paste a podcast link.")
    expect(() => normalizeFeedUrl("my favourite podcast")).toThrow(
      "That doesn't look like a web link.",
    )
    expect(() => normalizeFeedUrl("localhost")).toThrow(
      "That doesn't look like a web link.",
    )
    expect(() => normalizeFeedUrl("ftp://example.com/rss")).toThrow(
      "That doesn't look like a web link.",
    )
    expect(() => normalizeFeedUrl("javascript:alert(1)")).toThrow(
      "That doesn't look like a web link.",
    )
    expect(() => normalizeFeedUrl("https://")).toThrow(
      "That doesn't look like a web link.",
    )
  })
})
