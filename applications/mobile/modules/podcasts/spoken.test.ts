// LOFI-FORK: the podcasts section's spoken-word search rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { SPOKEN_EMPTY_NOTE, groupSpoken, spokenTime } from "./spoken"

const hit = (episodeId: string, seconds: number, text = "said it") => ({
  episodeId,
  seconds,
  text,
  before: "",
  after: "",
})
const entry = (id: string, publishedAt: number | null) => ({
  episode: { id, publishedAt },
  show: { id: `show-${id}` },
})

describe("spokenTime", () => {
  it("is minutes and seconds, or hours when long", () => {
    expect(spokenTime(754.9)).toBe("12:34")
    expect(spokenTime(3725)).toBe("1:02:05")
    expect(spokenTime(0)).toBe("0:00")
  })
})

describe("groupSpoken", () => {
  it("groups the hits by episode, newest episode first, undated last", () => {
    const known = new Map([
      ["a", entry("a", 100)],
      ["b", entry("b", 300)],
      ["c", entry("c", null)],
    ])
    const groups = groupSpoken(
      [hit("a", 5), hit("c", 1), hit("b", 9), hit("a", 50)],
      known,
    )
    expect(groups.map((g) => g.episode.id)).toEqual(["b", "a", "c"])
    expect(groups[1]?.hits.map((h) => h.seconds)).toEqual([5, 50])
  })
  it("skips hits whose episode is not in the library", () => {
    const groups = groupSpoken(
      [hit("gone", 1), hit("a", 2)],
      new Map([["a", entry("a", 1)]]),
    )
    expect(groups.map((g) => g.episode.id)).toEqual(["a"])
  })
  it("is empty when there are no hits", () => {
    expect(groupSpoken([], new Map())).toEqual([])
  })
})

describe("SPOKEN_EMPTY_NOTE", () => {
  it("says plainly when nothing is searchable", () => {
    expect(SPOKEN_EMPTY_NOTE).toBe(
      "Episodes are searchable once they're downloaded and transcribed.",
    )
  })
})
