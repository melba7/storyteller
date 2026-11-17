// LOFI-FORK: the podcasts section's library view rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { type Show } from "./library"
import {
  type ShowActivity,
  badgeCount,
  badgeLabel,
  parseLibraryView,
  serializeLibraryView,
  sortShows,
} from "./libraryView"

function show(id: string, overrides: Partial<Show> = {}): Show {
  return {
    id,
    feedUrl: `https://example.com/${id}`,
    title: id,
    author: null,
    description: "",
    imageUrl: null,
    link: null,
    language: null,
    addedAt: 1,
    refreshedAt: 1,
    artworkColor: null,
    ownPosition: null,
    ...overrides,
  }
}

function activity(overrides: Partial<ShowActivity> = {}): ShowActivity {
  return { newestAt: null, newestPlayed: true, unplayedSince: 0, ...overrides }
}

const ids = (shows: Show[]) => shows.map((s) => s.id)

describe("sortShows by name", () => {
  it("ignores case and a leading The", () => {
    const shows = [
      show("a", { title: "The Zebra Show" }),
      show("b", { title: "apple talk" }),
      show("c", { title: "Mango" }),
      show("d", { title: "Theory of Things" }),
    ]
    expect(ids(sortShows(shows, "name", {}))).toEqual(["b", "c", "d", "a"])
  })

  it("keeps the given order for equal names", () => {
    const shows = [
      show("a", { title: "Same" }),
      show("b", { title: "the same" }),
      show("c", { title: "SAME" }),
    ]
    expect(ids(sortShows(shows, "name", {}))).toEqual(["a", "b", "c"])
  })

  it("does not change the list it is given", () => {
    const shows = [show("a", { title: "B" }), show("b", { title: "A" })]
    sortShows(shows, "name", {})
    expect(ids(shows)).toEqual(["a", "b"])
  })
})

describe("sortShows by date added", () => {
  it("puts the newest first and keeps the order on ties", () => {
    const shows = [
      show("a", { addedAt: 10 }),
      show("b", { addedAt: 30 }),
      show("c", { addedAt: 10 }),
      show("d", { addedAt: 20 }),
    ]
    expect(ids(sortShows(shows, "added", {}))).toEqual(["b", "d", "a", "c"])
  })
})

describe("sortShows by newest episode", () => {
  it("puts the newest first, undated shows last, and ties by name", () => {
    const shows = [
      show("none", { title: "Nothing" }),
      show("old", { title: "Old" }),
      show("tieB", { title: "Beta" }),
      show("tieA", { title: "Alpha" }),
      show("new", { title: "New" }),
      show("missing", { title: "Missing" }),
    ]
    const found = {
      old: activity({ newestAt: 100 }),
      tieB: activity({ newestAt: 200 }),
      tieA: activity({ newestAt: 200 }),
      new: activity({ newestAt: 900 }),
      none: activity({ newestAt: null }),
    }
    expect(ids(sortShows(shows, "newest", found))).toEqual([
      "new",
      "tieA",
      "tieB",
      "old",
      "missing",
      "none",
    ])
  })
})

describe("sortShows in your own order", () => {
  it("puts placed shows first by position, then unplaced ones oldest first", () => {
    const shows = [
      show("late", { addedAt: 90 }),
      show("second", { ownPosition: 1, addedAt: 5 }),
      show("early", { addedAt: 10 }),
      show("first", { ownPosition: 0, addedAt: 50 }),
    ]
    expect(ids(sortShows(shows, "own", {}))).toEqual([
      "first",
      "second",
      "early",
      "late",
    ])
  })

  it("keeps the given order for unplaced shows added at the same time", () => {
    const shows = [show("a"), show("b"), show("c")]
    expect(ids(sortShows(shows, "own", {}))).toEqual(["a", "b", "c"])
  })
})

describe("badgeCount", () => {
  it("is 1 for a show just followed whose newest episode is unplayed", () => {
    const found = activity({ newestAt: 50, newestPlayed: false })
    expect(badgeCount(found, 100)).toBe(1)
  })

  it("counts unplayed episodes released since following", () => {
    const found = activity({
      newestAt: 400,
      newestPlayed: false,
      unplayedSince: 3,
    })
    expect(badgeCount(found, 100)).toBe(3)
  })

  it("adds the old newest episode only when it is unplayed", () => {
    const old = activity({
      newestAt: 50,
      newestPlayed: false,
      unplayedSince: 2,
    })
    expect(badgeCount(old, 100)).toBe(3)
  })

  it("is 0 when the newest episode before following is played", () => {
    const found = activity({ newestAt: 50, newestPlayed: true })
    expect(badgeCount(found, 100)).toBe(0)
  })

  it("does not count the newest episode twice when it came after following", () => {
    const found = activity({
      newestAt: 150,
      newestPlayed: false,
      unplayedSince: 1,
    })
    expect(badgeCount(found, 100)).toBe(1)
  })

  it("is 0 for a show with no dated episodes and for no activity", () => {
    expect(badgeCount(activity(), 100)).toBe(0)
    expect(badgeCount(undefined, 100)).toBe(0)
  })

  it("counts an episode that is in progress as unplayed", () => {
    // The database reports played = 0 for an episode that is only partly heard.
    const found = activity({
      newestAt: 400,
      newestPlayed: false,
      unplayedSince: 1,
    })
    expect(badgeCount(found, 100)).toBe(1)
  })
})

describe("badgeLabel", () => {
  it("is empty at 0, the number up to 99 and 99+ beyond", () => {
    expect(badgeLabel(0)).toBe("")
    expect(badgeLabel(1)).toBe("1")
    expect(badgeLabel(99)).toBe("99")
    expect(badgeLabel(100)).toBe("99+")
    expect(badgeLabel(2500)).toBe("99+")
  })
})

describe("parseLibraryView", () => {
  it("reads a saved choice", () => {
    const saved = serializeLibraryView({ layout: "list", order: "newest" })
    expect(parseLibraryView(saved)).toEqual({ layout: "list", order: "newest" })
  })

  it("reads your own order", () => {
    expect(parseLibraryView('{"layout":"list","order":"own"}')).toEqual({
      layout: "list",
      order: "own",
    })
  })

  it("falls back to large grid and name for unknown values", () => {
    expect(parseLibraryView('{"layout":"huge","order":"random"}')).toEqual({
      layout: "large",
      order: "name",
    })
  })

  it("keeps the part that is good", () => {
    expect(parseLibraryView('{"layout":"small","order":7}')).toEqual({
      layout: "small",
      order: "name",
    })
  })

  it("falls back for broken JSON, null, and values that are not objects", () => {
    const fallback = { layout: "large", order: "name" }
    expect(parseLibraryView("{nope")).toEqual(fallback)
    expect(parseLibraryView(null)).toEqual(fallback)
    expect(parseLibraryView("42")).toEqual(fallback)
    expect(parseLibraryView("null")).toEqual(fallback)
    expect(parseLibraryView("[]")).toEqual(fallback)
  })
})
