// LOFI-FORK: the podcasts section's smart playlists (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  AUTO_DOWNLOAD_LIMIT,
  DEFAULT_RULES,
  type PlaylistRules,
  type PlaylistSort,
  describeRules,
  filterDownloaded,
  parseRules,
  parseSort,
  playlistDownloads,
  playlistQuery,
  serializeRules,
} from "./playlistRules"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

const DAY = 24 * 60 * 60 * 1000
const NOW = 100 * DAY

function rules(patch: Partial<PlaylistRules>): PlaylistRules {
  return { ...DEFAULT_RULES, ...patch }
}

/** The ids the rules pick from a small library, in order. */
function pick(patch: Partial<PlaylistRules>, sort: PlaylistSort = "newest") {
  const db = openTestDatabase()
  addShow(db, "s1")
  addShow(db, "s2")
  addEpisode(db, {
    id: "fresh",
    show_id: "s1",
    published_at: NOW - 2 * 3600_000,
    duration_seconds: 600,
  })
  addEpisode(db, {
    id: "week",
    show_id: "s1",
    published_at: NOW - 5 * DAY,
    duration_seconds: 3600,
    position_seconds: 100,
  })
  addEpisode(db, {
    id: "old",
    show_id: "s2",
    published_at: NOW - 60 * DAY,
    duration_seconds: 7200,
    played: 1,
  })
  addEpisode(db, { id: "undated", show_id: "s2" })
  addEpisode(db, {
    id: "starred",
    show_id: "s2",
    published_at: NOW - 10 * DAY,
    duration_seconds: 1800,
    starred_at: 5,
  })
  addEpisode(db, {
    id: "gone",
    show_id: "s1",
    published_at: NOW - 1000,
    duration_seconds: 600,
    archived: 1,
  })
  const { sql, params } = playlistQuery(rules(patch), sort, NOW)
  return db
    .prepare(sql)
    .all(...params)
    .map((row) => String((row as { id: string }).id))
}

describe("playlistQuery", () => {
  it("takes every episode that is not archived, newest first, undated last", () => {
    expect(pick({})).toEqual(["fresh", "week", "starred", "old", "undated"])
  })

  it("takes only the chosen shows, and nothing when none is chosen", () => {
    expect(pick({ showIds: ["s2"] })).toEqual(["starred", "old", "undated"])
    expect(pick({ showIds: [] })).toEqual([])
  })

  it("takes the played states chosen", () => {
    expect(pick({ played: ["unplayed"] })).toEqual([
      "fresh",
      "starred",
      "undated",
    ])
    expect(pick({ played: ["inProgress"] })).toEqual(["week"])
    expect(pick({ played: ["played"] })).toEqual(["old"])
    expect(pick({ played: ["inProgress", "played"] })).toEqual(["week", "old"])
    expect(pick({ played: ["unplayed", "inProgress", "played"] })).toHaveLength(
      5,
    )
  })

  it("takes episodes inside the release window and leaves out undated ones", () => {
    expect(pick({ release: "day" })).toEqual(["fresh"])
    expect(pick({ release: "week" })).toEqual(["fresh", "week"])
    expect(pick({ release: "twoWeeks" })).toEqual(["fresh", "week", "starred"])
    expect(pick({ release: "month" })).toEqual(["fresh", "week", "starred"])
  })

  it("limits the length, leaving out episodes of unknown length", () => {
    expect(pick({ shorterThan: 20 })).toEqual(["fresh"])
    expect(pick({ longerThan: 45 })).toEqual(["week", "old"])
    expect(pick({ longerThan: 15, shorterThan: 45 })).toEqual(["starred"])
  })

  it("takes only starred episodes when asked", () => {
    expect(pick({ starredOnly: true })).toEqual(["starred"])
  })

  it("combines every rule", () => {
    expect(
      pick({
        showIds: ["s1"],
        played: ["unplayed", "inProgress"],
        release: "week",
        longerThan: 5,
      }),
    ).toEqual(["fresh", "week"])
  })

  it("sorts oldest, shortest and longest first", () => {
    expect(pick({}, "oldest")).toEqual([
      "old",
      "starred",
      "week",
      "fresh",
      "undated",
    ])
    expect(pick({}, "shortest")).toEqual([
      "fresh",
      "starred",
      "week",
      "old",
      "undated",
    ])
    expect(pick({}, "longest")).toEqual([
      "old",
      "week",
      "starred",
      "fresh",
      "undated",
    ])
  })
})

describe("parseRules", () => {
  it("reads what serializeRules wrote", () => {
    const wanted = rules({
      showIds: ["a"],
      played: ["unplayed", "played"],
      release: "week",
      shorterThan: 30,
      longerThan: 5,
      downloaded: "notDownloaded",
      starredOnly: true,
    })
    expect(parseRules(serializeRules(wanted))).toEqual(wanted)
  })

  it("falls back to the defaults for anything broken", () => {
    expect(parseRules(null)).toEqual(DEFAULT_RULES)
    expect(parseRules("{nope")).toEqual(DEFAULT_RULES)
    expect(parseRules("[1]")).toEqual(DEFAULT_RULES)
    expect(
      parseRules(
        JSON.stringify({
          release: "yesterday",
          played: ["x", "played"],
          shorterThan: -3,
          showIds: [1, "a"],
          downloaded: 4,
        }),
      ),
    ).toEqual(rules({ played: ["played"], showIds: ["a"] }))
  })

  it("reads a sort, with newest as the fallback", () => {
    expect(parseSort("longest")).toBe("longest")
    expect(parseSort("sideways")).toBe("newest")
  })
})

describe("filterDownloaded", () => {
  const episodes = [{ id: "a" }, { id: "b" }, { id: "c" }]
  const onPhone = new Set(["b"])

  it("keeps the downloaded, the not downloaded, or all", () => {
    expect(
      filterDownloaded(episodes, { downloaded: "downloaded" }, onPhone),
    ).toEqual([{ id: "b" }])
    expect(
      filterDownloaded(episodes, { downloaded: "notDownloaded" }, onPhone),
    ).toEqual([{ id: "a" }, { id: "c" }])
    expect(filterDownloaded(episodes, { downloaded: "any" }, onPhone)).toEqual(
      episodes,
    )
  })
})

describe("describeRules", () => {
  it("says every episode for no rules", () => {
    expect(describeRules(DEFAULT_RULES)).toBe("Every episode")
  })

  it("lists what is asked for", () => {
    expect(
      describeRules(
        rules({
          played: ["unplayed"],
          release: "twoWeeks",
          starredOnly: true,
          showIds: ["a", "b"],
          shorterThan: 30,
        }),
      ),
    ).toBe("2 shows · Unplayed · Last 2 weeks · Under 30 min · Starred")
  })
})

describe("playlistDownloads", () => {
  const episode = (id: string) => ({
    id,
    showId: "s",
    audioUrl: `u/${id}`,
    audioType: "audio/mpeg",
  })
  const many = Array.from({ length: 8 }, (_, i) => episode(`e${i}`))

  it("takes each playlist's first episodes, only for playlists that ask", () => {
    const picked = playlistDownloads(
      [
        { id: "p1", autoDownload: true },
        { id: "p2", autoDownload: false },
      ],
      new Map([
        ["p1", many],
        ["p2", [episode("x")]],
      ]),
      new Set(),
    )
    expect(picked.map((e) => e.id)).toEqual(
      many.slice(0, AUTO_DOWNLOAD_LIMIT).map((e) => e.id),
    )
  })

  it("leaves out what is downloaded, on its way or failed, and does not count it", () => {
    const picked = playlistDownloads(
      [{ id: "p1", autoDownload: true }],
      new Map([["p1", many]]),
      new Set(["e0", "e1"]),
    )
    expect(picked.map((e) => e.id)).toEqual(["e2", "e3", "e4"])
  })

  it("takes an episode once when two playlists hold it", () => {
    const picked = playlistDownloads(
      [
        { id: "p1", autoDownload: true },
        { id: "p2", autoDownload: true },
      ],
      new Map([
        ["p1", [episode("a"), episode("b")]],
        ["p2", [episode("b"), episode("c")]],
      ]),
      new Set(),
    )
    expect(picked.map((e) => e.id)).toEqual(["a", "b", "c"])
  })
})
