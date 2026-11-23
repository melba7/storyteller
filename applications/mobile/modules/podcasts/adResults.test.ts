// LOFI-FORK: the podcasts section's ad skipping results (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  NO_LONGER_FOLLOWED,
  agoText,
  macSection,
  parseTally,
  passRate,
  resultsFor,
} from "./adResults"
import { parseTeachingState } from "./teaching"

const tally = (shows: Record<string, Record<string, unknown>>) =>
  JSON.stringify({ since: 1_700_000_000_000, shows })

const SHOWS = [
  { id: "a", title: "Alpha Hour" },
  { id: "b", title: "Beta Talk" },
  { id: "c", title: "Gamma Show" },
]

describe("parseTally", () => {
  it("reads the counts for each show", () => {
    const parsed = parseTally(
      tally({
        a: { skipped: 41, undone: 2, trimmed: 1, missed: 3, seconds: 5400 },
      }),
    )
    expect(parsed["a"]).toEqual({
      skipped: 41,
      undone: 2,
      trimmed: 1,
      missed: 3,
      seconds: 5400,
    })
  })

  it("makes anything that is not a good number zero and ignores bad input", () => {
    const parsed = parseTally(
      tally({ a: { skipped: "3", undone: -1, missed: 1.5, seconds: 90 } }),
    )
    expect(parsed["a"]).toEqual({
      skipped: 0,
      undone: 0,
      trimmed: 0,
      missed: 0,
      seconds: 90,
    })
    for (const text of [null, "", "nope", "[]", "{}", '{"shows":[]}']) {
      expect(parseTally(text)).toEqual({})
    }
  })
})

describe("passRate", () => {
  const rate = (
    skipped: number,
    undone: number,
    trimmed: number,
    missed: number,
  ) => passRate({ skipped, undone, trimmed, missed })

  it("counts a skip that stood, over every skip and every missed ad", () => {
    expect(rate(45, 2, 1, 3)).toEqual({ passed: 42, total: 48, percent: 88 })
    expect(rate(41, 0, 0, 4)).toEqual({ passed: 41, total: 45, percent: 91 })
  })

  it("has no rate when nothing was skipped or missed", () => {
    expect(rate(0, 0, 0, 0)).toBeNull()
    expect(rate(0, 3, 1, 0)).toBeNull()
  })

  it("never goes below 0 or above 100 when the counts make no sense", () => {
    expect(rate(2, 5, 4, 0)).toEqual({ passed: 0, total: 2, percent: 0 })
    expect(rate(0, 0, 0, 3)).toEqual({ passed: 0, total: 3, percent: 0 })
    expect(rate(10, 0, 0, 0)).toEqual({ passed: 10, total: 10, percent: 100 })
  })
})

describe("resultsFor", () => {
  it("adds up the totals at the top", () => {
    const results = resultsFor(
      parseTally(
        tally({
          a: { skipped: 41, undone: 2, missed: 3, seconds: 3600 },
          b: { skipped: 10, undone: 0, missed: 0, seconds: 1500 },
        }),
      ),
      SHOWS,
    )
    expect(results.empty).toBe(false)
    expect(results.totals).toEqual([
      {
        key: "passed",
        label: "Passed by your ears",
        value: "49 of 54 (91%)",
      },
      { key: "skipped", label: "Ads skipped", value: "51" },
      { key: "saved", label: "Time saved", value: "1 h 25 min" },
      { key: "undone", label: "Skips you took back", value: "2" },
      { key: "missed", label: "Ads you marked as missed", value: "3" },
    ])
  })

  it("leaves the pass line out when there is nothing to rate", () => {
    const results = resultsFor(parseTally(tally({ a: { undone: 2 } })), SHOWS)
    expect(results.totals.map((total) => total.key)).toEqual([
      "skipped",
      "saved",
      "undone",
      "missed",
    ])
  })

  it("explains what the pass line counts", () => {
    expect(resultsFor({}, SHOWS).passNote).toBe(
      "A skip you took back or trimmed, or an ad you marked as missed, counts as not passed. It only knows what you told it.",
    )
  })

  it("writes one row for each show, the most missed and undone first", () => {
    const results = resultsFor(
      parseTally(
        tally({
          a: { skipped: 41, undone: 2, missed: 3 },
          b: { skipped: 90, undone: 0, missed: 0 },
          c: { skipped: 5, undone: 4, missed: 4 },
        }),
      ),
      SHOWS,
    )
    expect(results.rows.map((row) => row.text)).toEqual([
      "Gamma Show: 5 skipped, 4 taken back, 4 missed",
      "Alpha Hour: 41 skipped, 2 taken back, 3 missed",
      "Beta Talk: 90 skipped",
    ])
  })

  it("breaks a tie by the most skipped, then by title", () => {
    const results = resultsFor(
      parseTally(
        tally({
          a: { skipped: 3 },
          b: { skipped: 3 },
          c: { skipped: 9 },
        }),
      ),
      SHOWS,
    )
    expect(results.rows.map((row) => row.title)).toEqual([
      "Gamma Show",
      "Alpha Hour",
      "Beta Talk",
    ])
  })

  it("names a show that is not followed any more in plain words", () => {
    const results = resultsFor(
      parseTally(tally({ gone: { skipped: 2, missed: 1 } })),
      SHOWS,
    )
    expect(NO_LONGER_FOLLOWED).toBe("A show you no longer follow")
    expect(results.rows[0]?.text).toBe(
      "A show you no longer follow: 2 skipped, 1 missed",
    )
  })

  it("names a previewed show and the added files for what they are", () => {
    const results = resultsFor(
      parseTally(
        tally({
          "preview:https://example.com/rss": { skipped: 3 },
          "": { skipped: 2 },
        }),
      ),
      SHOWS,
    )
    expect(results.rows.map((row) => row.text)).toEqual([
      "A show you previewed: 3 skipped",
      "Your files: 2 skipped",
    ])
  })

  it("says 1 and not 1s, and leaves out a show with nothing to say", () => {
    const results = resultsFor(
      parseTally(
        tally({ a: { skipped: 1, undone: 1, missed: 1 }, b: { trimmed: 4 } }),
      ),
      SHOWS,
    )
    expect(results.rows).toHaveLength(1)
    expect(results.rows[0]?.text).toBe(
      "Alpha Hour: 1 skipped, 1 taken back, 1 missed",
    )
  })

  it("is empty for a phone that has skipped nothing", () => {
    expect(resultsFor({}, SHOWS).empty).toBe(true)
    expect(
      resultsFor(parseTally(tally({ a: { trimmed: 2 } })), SHOWS).empty,
    ).toBe(true)
    expect(resultsFor({}, SHOWS).rows).toEqual([])
  })

  it("counts a missed ad alone as something to show", () => {
    const results = resultsFor(parseTally(tally({ a: { missed: 2 } })), SHOWS)
    expect(results.empty).toBe(false)
    expect(results.rows[0]?.text).toBe("Alpha Hour: 0 skipped, 2 missed")
  })
})

describe("agoText", () => {
  const now = Date.parse("2026-11-22T12:00:00Z")

  it("says how many days ago", () => {
    expect(agoText("2026-11-10T09:00:00Z", now)).toBe("12 days ago")
    expect(agoText("2026-11-21T09:00:00Z", now)).toBe("yesterday")
    expect(agoText("2026-11-22T01:00:00Z", now)).toBe("today")
    expect(agoText(now - 3 * 86_400_000, now)).toBe("3 days ago")
  })

  it("says nothing when the time cannot be read", () => {
    expect(agoText("someday", now)).toBeNull()
    expect(agoText(null, now)).toBeNull()
  })

  it("says today for a time in the future", () => {
    expect(agoText(now + 86_400_000, now)).toBe("today")
  })
})

describe("macSection", () => {
  const now = Date.parse("2026-11-22T12:00:00Z")

  it("says what the Mac taught, one line each", () => {
    const state = parseTeachingState(
      JSON.stringify({
        model: {
          writtenAt: "2026-11-10T09:00:00Z",
          episodes: 312,
          precision: 0.93,
          recall: 0.8,
        },
        library: 41,
        habits: 12,
        sounds: 7,
      }),
    )
    const section = macSection(state, now)
    expect(section.empty).toBeNull()
    expect(section.lines).toEqual([
      {
        key: "model",
        label: "Small model",
        text: "From 312 episodes, 12 days ago. Right 93 times in 100 on episodes it never saw.",
      },
      {
        key: "library",
        label: "Known ads",
        text: "41 ads it has heard before",
      },
      {
        key: "habits",
        label: "How shows start",
        text: "Knows how 12 shows usually start",
      },
      { key: "sounds", label: "Ad sounds", text: "7 sounds it listens for" },
    ])
  })

  it("leaves out what the Mac has not taught, and the precision when unknown", () => {
    const state = parseTeachingState(
      JSON.stringify({ model: { episodes: 1, writtenAt: "x" }, sounds: 1 }),
    )
    expect(macSection(state, now).lines).toEqual([
      { key: "model", label: "Small model", text: "From 1 episode." },
      { key: "sounds", label: "Ad sounds", text: "1 sound it listens for" },
    ])
  })

  it("says nothing yet, and that the phone skips ads by itself", () => {
    const section = macSection(parseTeachingState(null), now)
    expect(section.lines).toEqual([])
    expect(section.empty).toEqual({
      title: "Nothing from your Mac yet",
      text: "Your phone still skips ads by itself.",
    })
  })
})
