// LOFI-FORK: the podcasts section's playlists (see FORK.md).
import { describe, expect, it } from "vitest"

import { serializeRules } from "./playlistRules"
import {
  DELETE_PLAYLIST_SQL,
  LIST_PLAYLISTS_SQL,
  NEXT_POSITION_SQL,
  SAVE_PLAYLIST_SQL,
} from "./playlistSql"
import {
  STARTER_PLAYLISTS,
  newPlaylist,
  parseMinutes,
  playlistFromRow,
  playlistProblem,
} from "./playlists"
import { openTestDatabase } from "./testDatabase"

function list(db: ReturnType<typeof openTestDatabase>) {
  return db
    .prepare(LIST_PLAYLISTS_SQL)
    .all()
    .map((row) => playlistFromRow(row))
}

describe("the starter playlists", () => {
  it("are in a new library with the rules they are named for", () => {
    const playlists = list(openTestDatabase())
    expect(playlists.map((p) => p.title)).toEqual([
      "New Releases",
      "In Progress",
      "Starred",
    ])
    expect(playlists.map((p) => p.rules)).toEqual(
      STARTER_PLAYLISTS.map((p) => p.rules),
    )
    expect(playlists.every((p) => !p.autoDownload && p.sort === "newest")).toBe(
      true,
    )
    expect(playlists.every((p) => p.createdAt > 0)).toBe(true)
  })

  it("stay deleted", () => {
    const db = openTestDatabase()
    db.prepare(DELETE_PLAYLIST_SQL).run("starter-starred")
    expect(list(db).map((p) => p.title)).toEqual([
      "New Releases",
      "In Progress",
    ])
  })
})

describe("saving a playlist", () => {
  it("adds a new one after the last", () => {
    const db = openTestDatabase()
    const next = db.prepare(NEXT_POSITION_SQL).get() as { next: number }
    expect(next.next).toBe(3)
    const mine = {
      ...newPlaylist("mine", next.next, 1234),
      title: "Short ones",
      rules: { ...newPlaylist("x", 0, 0).rules, shorterThan: 20 },
      autoDownload: true,
    }
    db.prepare(SAVE_PLAYLIST_SQL).run(
      mine.id,
      mine.title,
      mine.position,
      serializeRules(mine.rules),
      "shortest",
      1,
      mine.createdAt,
      "smart",
    )
    const saved = list(db).at(-1)
    expect(saved).toEqual({ ...mine, sort: "shortest" })
  })

  it("changes an existing one but keeps its place and date", () => {
    const db = openTestDatabase()
    const before = list(db)[1]
    if (!before) throw new Error("the starter playlists are missing")
    db.prepare(SAVE_PLAYLIST_SQL).run(
      before.id,
      "Half-way",
      99,
      serializeRules({ ...before.rules, starredOnly: true }),
      "oldest",
      1,
      5,
      "manual",
    )
    const after = list(db)[1]
    expect(after).toMatchObject({
      id: before.id,
      title: "Half-way",
      position: 1,
      sort: "oldest",
      autoDownload: true,
      createdAt: before.createdAt,
      // A playlist keeps the kind it was made with.
      kind: "smart",
    })
    expect(after?.rules.starredOnly).toBe(true)
  })

  it("starts the first playlist of an empty list at 0", () => {
    const db = openTestDatabase()
    for (const playlist of list(db))
      db.prepare(DELETE_PLAYLIST_SQL).run(playlist.id)
    expect(db.prepare(NEXT_POSITION_SQL).get()).toEqual({ next: 0 })
  })
})

describe("parseMinutes", () => {
  it("reads a whole number above zero", () => {
    expect(parseMinutes("30")).toBe(30)
    expect(parseMinutes(" 5 ")).toBe(5)
  })

  it("gives no limit for anything else", () => {
    expect(parseMinutes("")).toBeNull()
    expect(parseMinutes("0")).toBeNull()
    expect(parseMinutes("-4")).toBeNull()
    expect(parseMinutes("abc")).toBeNull()
  })
})

describe("playlistProblem", () => {
  const ok = newPlaylist("p", 0, 0).rules

  it("accepts a named playlist with workable rules", () => {
    expect(playlistProblem("Mine", ok)).toBeNull()
    expect(
      playlistProblem("Mine", { ...ok, longerThan: 5, shorterThan: 30 }),
    ).toBeNull()
  })

  it("asks for a name", () => {
    expect(playlistProblem("  ", ok)).toMatch(/name/)
  })

  it("asks for a show when shows are chosen but none is", () => {
    expect(playlistProblem("Mine", { ...ok, showIds: [] })).toMatch(/show/)
  })

  it("refuses a length range nothing can be in", () => {
    expect(
      playlistProblem("Mine", { ...ok, longerThan: 30, shorterThan: 30 }),
    ).toMatch(/longer and shorter/)
  })

  it("refuses auto-download for episodes that are not downloaded", () => {
    const rules = { ...ok, downloaded: "notDownloaded" as const }
    expect(playlistProblem("Mine", rules, true)).toMatch(/download/i)
    expect(playlistProblem("Mine", rules, false)).toBeNull()
    expect(playlistProblem("Mine", rules)).toBeNull()
  })
})
