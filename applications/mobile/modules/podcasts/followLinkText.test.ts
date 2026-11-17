// LOFI-FORK: the podcasts section's links (see FORK.md).
import { describe, expect, it } from "vitest"

import { isFollowLink } from "./followLinkText"

describe("isFollowLink", () => {
  it("accepts an http or https feed link", () => {
    expect(isFollowLink("https://example.com/feed.xml")).toBe(true)
    expect(isFollowLink("http://example.com/rss")).toBe(true)
    expect(isFollowLink("  HTTPS://Example.com/feed \n")).toBe(true)
  })

  it("accepts an Apple Podcasts link, with or without an episode", () => {
    expect(
      isFollowLink("https://podcasts.apple.com/us/podcast/some-show/id1234567"),
    ).toBe(true)
    expect(
      isFollowLink(
        "https://podcasts.apple.com/us/podcast/some-show/id1234567?i=1000",
      ),
    ).toBe(true)
  })

  it("rejects words to search for", () => {
    expect(isFollowLink("")).toBe(false)
    expect(isFollowLink("true crime")).toBe(false)
    expect(isFollowLink("example.com")).toBe(false)
    expect(isFollowLink("http")).toBe(false)
  })

  it("rejects a link with spaces or another scheme", () => {
    expect(isFollowLink("https://example.com/a feed")).toBe(false)
    expect(isFollowLink("ftp://example.com/feed.xml")).toBe(false)
    expect(isFollowLink("https://")).toBe(false)
    expect(isFollowLink("https://localhost")).toBe(false)
  })
})
