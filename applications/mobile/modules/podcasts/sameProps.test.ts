// LOFI-FORK: the podcasts section's row comparison (see FORK.md).
import { describe, expect, it } from "vitest"

import { dateWords } from "./episodeRowLook"
import type { Show, StoredEpisode } from "./library"
import { sameData, sameProps, sameRowProps, saysTimeAgo } from "./sameProps"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

function episode(overrides: Partial<StoredEpisode> = {}): StoredEpisode {
  return {
    id: "e1",
    showId: "s1",
    guid: "g1",
    title: "Episode one",
    publishedAt: 1_000,
    durationSeconds: 600,
    notes: "<p>Notes</p>",
    audioUrl: "https://cdn.example.com/1.mp3",
    audioType: "audio/mpeg",
    audioBytes: 123,
    imageUrl: "https://cdn.example.com/1.jpg",
    season: 2,
    number: 5,
    transcriptUrl: "https://cdn.example.com/1.vtt",
    transcriptType: "text/vtt",
    people: [{ name: "Ann", role: "host", group: "cast" }],
    chaptersUrl: "https://cdn.example.com/1.json",
    positionSeconds: 30,
    played: false,
    lastPlayedAt: 5_000,
    archived: false,
    starredAt: 6_000,
    ...overrides,
  }
}

function show(overrides: Partial<Show> = {}): Show {
  return {
    id: "s1",
    feedUrl: "https://example.com/rss",
    title: "The Show",
    author: "Someone",
    description: "About it",
    imageUrl: "https://example.com/art.jpg",
    link: null,
    language: "en",
    addedAt: 1,
    refreshedAt: 2,
    artworkColor: "#336699",
    ownPosition: 3,
    categories: ["News"],
    funding: [{ url: "https://example.com/pay", label: "Support" }],
    people: [{ name: "Bob", role: "host", group: "cast" }],
    settings: { ...DEFAULT_SHOW_SETTINGS },
    ...overrides,
  }
}

/** The same fields in a new object, the way a second read of the library gives them. */
function copy<T>(value: T): T {
  return structuredClone(value)
}

/** A different value of the same kind, whatever the field holds. */
function changed(value: unknown): unknown {
  if (typeof value === "number") return value + 1
  if (typeof value === "string") return `${value}!`
  if (typeof value === "boolean") return !value
  if (Array.isArray(value))
    return [...value, { name: "New", role: "x", group: "y" }]
  // null: a field that is empty in the fixture gets something.
  return 1
}

describe("sameData", () => {
  it("is true for the same value and for equal plain data", () => {
    expect(sameData(1, 1)).toBe(true)
    expect(sameData("a", "a")).toBe(true)
    expect(sameData(null, null)).toBe(true)
    expect(sameData(Number.NaN, Number.NaN)).toBe(true)
    expect(sameData([1, [2, { a: 3 }]], [1, [2, { a: 3 }]])).toBe(true)
    expect(sameData({ a: { b: [1] } }, { a: { b: [1] } })).toBe(true)
  })

  it("is false for anything that differs", () => {
    expect(sameData(1, 2)).toBe(false)
    expect(sameData(0, -0)).toBe(false)
    expect(sameData(null, undefined)).toBe(false)
    expect(sameData([1, 2], [1, 2, 3])).toBe(false)
    expect(sameData([1, 2], [2, 1])).toBe(false)
    expect(sameData([], {})).toBe(false)
    expect(sameData({ a: 1 }, { a: 2 })).toBe(false)
    expect(sameData({ a: { b: 1 } }, { a: { b: 2 } })).toBe(false)
  })

  it("sees a field that only one side has, even an undefined one", () => {
    expect(sameData({ a: 1 }, { a: 1, b: 2 })).toBe(false)
    expect(sameData({ a: 1, b: 2 }, { a: 1 })).toBe(false)
    expect(sameData({ a: 1 }, { a: 1, b: undefined })).toBe(false)
    const hidden = Symbol("hidden")
    expect(sameData({ [hidden]: 1 }, { [hidden]: 2 })).toBe(false)
  })

  it("compares a function and anything that is not plain data by identity", () => {
    const fn = () => 1
    expect(sameData(fn, fn)).toBe(true)
    expect(
      sameData(
        () => 1,
        () => 1,
      ),
    ).toBe(false)
    expect(sameData(new Date(5), new Date(5))).toBe(false)
    expect(sameData(new Map([[1, 2]]), new Map([[1, 2]]))).toBe(false)
    expect(sameData({ f: fn }, { f: fn })).toBe(true)
    expect(sameData({ f: () => 1 }, { f: () => 1 })).toBe(false)
  })

  it("ends on data that points back to itself", () => {
    const a: Record<string, unknown> = { x: 1 }
    const b: Record<string, unknown> = { x: 1 }
    a["self"] = a
    b["self"] = b
    expect(sameData(a, b)).toBe(false)
    expect(sameData(a, a)).toBe(true)
  })
})

describe("two episodes", () => {
  it("are the same when every field is equal, even in a new object", () => {
    const first = episode()
    expect(sameData(first, copy(first))).toBe(true)
    expect(sameData(first, episode())).toBe(true)
  })

  it("differ when any single field changes", () => {
    const first = episode()
    const keys = Object.keys(first) as (keyof StoredEpisode)[]
    // The type makes the fixture hold every field, so a field added later is tried too.
    expect(keys).toEqual(
      expect.arrayContaining([
        "positionSeconds",
        "played",
        "archived",
        "people",
      ]),
    )
    for (const key of keys) {
      const other = { ...copy(first), [key]: changed(first[key]) }
      expect(sameData(first, other), `the field ${key}`).toBe(false)
    }
  })

  it("differ when a field inside a person changes", () => {
    const first = episode()
    const other = copy(first)
    other.people[0] = { name: "Ann", role: "guest", group: "cast" }
    expect(sameData(first, other)).toBe(false)
  })
})

describe("sameProps", () => {
  const props = () => ({
    episode: episode(),
    show: show(),
    here: { show: true },
    selection: {
      on: true,
      selected: ["e1"],
      toggle: () => {},
    },
  })

  it("is true for equal props in new objects (the functions are the same)", () => {
    const first = props()
    const second = {
      ...copy({ ...first, selection: undefined }),
      selection: first.selection,
    }
    expect(sameProps(first, second)).toBe(true)
    expect(sameProps(first, first)).toBe(true)
  })

  it("is false when a show field, a flag or the picked ids change", () => {
    const first = props()
    expect(
      sameProps(first, { ...first, show: show({ artworkColor: null }) }),
    ).toBe(false)
    expect(sameProps(first, { ...first, here: { show: false } })).toBe(false)
    expect(
      sameProps(first, {
        ...first,
        selection: { ...first.selection, selected: ["e1", "e2"] },
      }),
    ).toBe(false)
    expect(
      sameProps(first, {
        ...first,
        selection: { ...first.selection, on: false },
      }),
    ).toBe(false)
  })

  it("is false when a prop appears or goes away", () => {
    const first = props()
    const { here: _here, ...without } = first
    expect(sameProps(first, without as typeof first)).toBe(false)
    expect(sameProps(without as typeof first, first)).toBe(false)
  })

  it("is false when a function prop is a new function", () => {
    const first = props()
    const second = {
      ...first,
      selection: { ...first.selection, toggle: () => {} },
    }
    expect(sameProps(first, second)).toBe(false)
  })
})

describe("the row says how long ago an episode came out", () => {
  const NOW = 1_700_000_000_000
  const HOUR = 3_600_000

  it("is true for the first day only, and false without a date", () => {
    expect(saysTimeAgo(NOW - 60_000, NOW)).toBe(true)
    expect(saysTimeAgo(NOW - 23 * HOUR, NOW)).toBe(true)
    expect(saysTimeAgo(NOW - 24 * HOUR, NOW)).toBe(false)
    expect(saysTimeAgo(NOW - 48 * HOUR, NOW)).toBe(false)
    expect(saysTimeAgo(NOW + HOUR, NOW)).toBe(false)
    expect(saysTimeAgo(null, NOW)).toBe(false)
    expect(saysTimeAgo(Number.NaN, NOW)).toBe(false)
  })

  it("agrees with the words the row shows, so the two cannot drift apart", () => {
    const ages = [
      0,
      1,
      59_999,
      HOUR - 1,
      HOUR,
      23 * HOUR,
      24 * HOUR - 1,
      24 * HOUR,
      24 * HOUR + 1,
      72 * HOUR,
      -1,
      -HOUR,
    ]
    for (const age of ages) {
      const published = NOW - age
      expect(saysTimeAgo(published, NOW), `${age} ms old`).toBe(
        dateWords(published, NOW).endsWith(" ago"),
      )
    }
  })

  it("makes a row of a new episode draw again, and leaves an old one alone", () => {
    const old = { episode: episode({ publishedAt: 1_000 }), show: show() }
    expect(sameRowProps(old, copy(old), NOW)).toBe(true)
    const fresh = {
      episode: episode({ publishedAt: NOW - 5 * 60_000 }),
      show: show(),
    }
    expect(sameRowProps(fresh, copy(fresh), NOW)).toBe(false)
  })

  it("keeps drawing a row for a second day, when its words have just turned into a date", () => {
    // The row was drawn at 23 h 50 m and said "23h ago". The list reads again a minute after the
    // episode turned 24 h old: the words are now a date, so the row must be drawn again.
    const turned = {
      episode: episode({ publishedAt: NOW - 24 * HOUR - 60_000 }),
      show: show(),
    }
    expect(sameRowProps(turned, copy(turned), NOW)).toBe(false)
    const lateInTheSecondDay = {
      episode: episode({ publishedAt: NOW - 47 * HOUR }),
      show: show(),
    }
    expect(
      sameRowProps(lateInTheSecondDay, copy(lateInTheSecondDay), NOW),
    ).toBe(false)
  })

  it("leaves a row alone from the third day on", () => {
    for (const age of [48 * HOUR, 72 * HOUR]) {
      const old = {
        episode: episode({ publishedAt: NOW - age }),
        show: show(),
      }
      expect(sameRowProps(old, copy(old), NOW), `${age} ms old`).toBe(true)
    }
  })

  it("still tells a changed old row apart", () => {
    const old = { episode: episode({ publishedAt: 1_000 }), show: show() }
    const played = {
      ...old,
      episode: episode({ publishedAt: 1_000, played: true }),
    }
    expect(sameRowProps(old, played, NOW)).toBe(false)
  })
})
