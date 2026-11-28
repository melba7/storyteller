// LOFI-FORK: the podcasts section's exchange with the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type Exchange,
  NEVER_EXCHANGED,
  NOTHING_CAME,
  countAheadMarks,
  exchangeLine,
  exchangeToSave,
  parseExchange,
} from "./macExchange"

// Local times, so the tests read the same in any time zone.
const at = (day: number, hour: number, minute: number) =>
  new Date(2026, 10, day, hour, minute).getTime()
const sent = { list: true, notes: true, diary: false }
const exchange = (
  when: number,
  came = NOTHING_CAME,
  went = sent,
): Exchange => ({
  at: when,
  came,
  went,
})

describe("exchangeLine", () => {
  it("says nothing has moved yet and names the step", () => {
    expect(exchangeLine(null, at(27, 12, 0))).toBe(NEVER_EXCHANGED)
    expect(NEVER_EXCHANGED).toContain("Link the LofiMusic folder in Settings")
  })

  it("says what came and went today", () => {
    const line = exchangeLine(
      exchange(at(27, 23, 10), { files: 0, marks: 7, copies: 1 }),
      at(27, 23, 40),
    )
    expect(line).toBe(
      "Last exchange with your Mac: today 11:10 PM. Came: marks for 7 episodes and 1 copy. Went: your list and notes.",
    )
  })

  it("says yesterday with the time, and the days when it is older than that", () => {
    const old = exchange(at(26, 9, 5), { files: 2, marks: 1, copies: 3 })
    expect(exchangeLine(old, at(27, 8, 0))).toBe(
      "Last exchange with your Mac: yesterday 9:05 AM. Came: marks for 1 episode, 2 teaching files and 3 copies. Went: your list and notes.",
    )
    expect(exchangeLine(old, at(29, 8, 0))).toContain(
      "Last exchange with your Mac: 3 days ago.",
    )
  })

  it("says nothing came or went when that is so", () => {
    expect(
      exchangeLine(
        exchange(at(27, 0, 30), NOTHING_CAME, {
          list: false,
          notes: false,
          diary: true,
        }),
        at(27, 1, 0),
      ),
    ).toBe(
      "Last exchange with your Mac: today 12:30 AM. Came: nothing. Went: diary.",
    )
  })
})

describe("exchangeToSave", () => {
  const came = { files: 1, marks: 4, copies: 0 }
  it("saves nothing when nothing ever moved", () => {
    expect(
      exchangeToSave(null, 1, NOTHING_CAME, {
        list: false,
        notes: false,
        diary: false,
      }),
    ).toBeNull()
  })

  it("saves a run that brought something", () => {
    expect(exchangeToSave(exchange(5), 9, came, sent)).toEqual(
      exchange(9, came, sent),
    )
  })

  it("keeps what came when a quiet run changes nothing, and when it only changes what went", () => {
    const saved = exchange(5, came, sent)
    expect(exchangeToSave(saved, 9, NOTHING_CAME, sent)).toBeNull()
    expect(
      exchangeToSave(saved, 9, NOTHING_CAME, { ...sent, diary: true }),
    ).toEqual(exchange(9, came, { ...sent, diary: true }))
  })
})

describe("parseExchange and countAheadMarks", () => {
  it("reads what was saved and refuses the rest", () => {
    const saved = exchange(5, { files: 1, marks: 2, copies: 3 })
    expect(parseExchange(JSON.stringify(saved))).toEqual(saved)
    expect(parseExchange(null)).toBeNull()
    expect(parseExchange("{")).toBeNull()
    expect(parseExchange(JSON.stringify({ at: "now" }))).toBeNull()
  })

  it("counts the episodes whose marks are not older than 14 days", () => {
    const now = 2_000_000_000
    const text = JSON.stringify({
      version: 1,
      episodes: [
        { feed: "a", guid: "1", marked: now - 3600 },
        { feed: "a", guid: "2", marked: now - 15 * 86_400 },
        { feed: "b", guid: "3" },
      ],
    })
    expect(countAheadMarks(text, now)).toBe(2)
    expect(countAheadMarks("not json", now)).toBe(0)
    expect(countAheadMarks("{}", now)).toBe(0)
  })
})
