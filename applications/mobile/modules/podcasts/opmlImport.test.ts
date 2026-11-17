// LOFI-FORK: the podcasts section's OPML reading and writing (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import { importFeeds, progressLine, summaryLine } from "./opmlImport"

const feed = (name: string) => ({
  title: `Show ${name}`,
  feedUrl: `https://${name}.example.com/feed`,
})

describe("importFeeds", () => {
  it("follows the shows that are not followed yet", async () => {
    const follow = vi.fn(() => Promise.resolve())
    const summary = await importFeeds([feed("a"), feed("b")], [], follow)
    expect(follow.mock.calls).toEqual([
      ["https://a.example.com/feed"],
      ["https://b.example.com/feed"],
    ])
    expect(summary).toEqual({ added: 2, alreadyFollowed: 0, failed: [] })
  })

  it("leaves followed shows alone, however the address is spelled", async () => {
    const follow = vi.fn(() => Promise.resolve())
    const summary = await importFeeds(
      [feed("a"), feed("b")],
      ["feed://A.example.com/feed#top"],
      follow,
    )
    expect(follow).toHaveBeenCalledTimes(1)
    expect(summary).toMatchObject({ added: 1, alreadyFollowed: 1 })
  })

  it("follows a show listed twice once", async () => {
    const follow = vi.fn(() => Promise.resolve())
    const summary = await importFeeds([feed("a"), feed("a")], [], follow)
    expect(follow).toHaveBeenCalledTimes(1)
    expect(summary).toEqual({ added: 1, alreadyFollowed: 1, failed: [] })
  })

  it("keeps going after a failure and says which one failed", async () => {
    const follow = vi.fn((url: string) =>
      url.includes("//b.")
        ? Promise.reject(new Error("Not a feed."))
        : Promise.resolve(),
    )
    const summary = await importFeeds(
      [feed("a"), feed("b"), feed("c")],
      [],
      follow,
    )
    expect(summary).toEqual({
      added: 2,
      alreadyFollowed: 0,
      failed: [{ title: "Show b", reason: "Not a feed." }],
    })
  })

  it("fails an address that is not a web link without trying it", async () => {
    const follow = vi.fn(() => Promise.resolve())
    const summary = await importFeeds(
      [{ title: "", feedUrl: "mailto:me@example.com" }],
      [],
      follow,
    )
    expect(follow).not.toHaveBeenCalled()
    expect(summary.failed).toEqual([
      {
        title: "mailto:me@example.com",
        reason: "That doesn't look like a web link.",
      },
    ])
  })

  it("reports progress before each show and at the end", async () => {
    const seen: [number, number][] = []
    await importFeeds(
      [feed("a"), feed("b")],
      [],
      () => Promise.resolve(),
      (done, total) => seen.push([done, total]),
    )
    expect(seen).toEqual([
      [0, 2],
      [1, 2],
      [2, 2],
    ])
  })

  it("does nothing for an empty list", async () => {
    expect(await importFeeds([], [], () => Promise.resolve())).toEqual({
      added: 0,
      alreadyFollowed: 0,
      failed: [],
    })
  })
})

describe("the words", () => {
  it("shows the show being followed", () => {
    expect(progressLine(0, 12)).toBe("Following 1 of 12")
    expect(progressLine(12, 12)).toBe("Following 12 of 12")
  })
  it("sums up what happened", () => {
    expect(
      summaryLine({
        added: 2,
        alreadyFollowed: 1,
        failed: [{ title: "x", reason: "y" }],
      }),
    ).toBe("2 added, 1 already followed, 1 failed")
    expect(summaryLine({ added: 0, alreadyFollowed: 0, failed: [] })).toBe(
      "0 added",
    )
  })
})
