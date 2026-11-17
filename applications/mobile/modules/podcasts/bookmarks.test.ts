// LOFI-FORK: the podcasts section's bookmarks (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  ADD_BOOKMARK_SQL,
  ALL_BOOKMARKS_SQL,
  DELETE_BOOKMARK_SQL,
  EPISODE_BOOKMARKS_SQL,
  RENAME_BOOKMARK_SQL,
} from "./bookmarkSql"
import {
  type Bookmark,
  bookmarkFromRow,
  bookmarkLabel,
  bookmarkTitle,
  defaultBookmarkTitle,
  parsePending,
  pendingToBookmarks,
} from "./bookmarks"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

describe("titles", () => {
  it("names a bookmark by its time", () => {
    expect(defaultBookmarkTitle(754.9)).toBe("Bookmark at 12:34")
    expect(defaultBookmarkTitle(3723)).toBe("Bookmark at 1:02:03")
    expect(defaultBookmarkTitle(0)).toBe("Bookmark at 0:00")
  })

  it("keeps what the listener typed, trimmed, and falls back to the default", () => {
    expect(bookmarkTitle("  The good part ", 60)).toBe("The good part")
    expect(bookmarkTitle("   ", 60)).toBe("Bookmark at 1:00")
    expect(bookmarkTitle(undefined, 60)).toBe("Bookmark at 1:00")
  })

  it("reads title and place for VoiceOver", () => {
    const mark: Bookmark = {
      id: "b",
      episodeId: "e",
      positionSeconds: 125,
      title: "Funny bit",
      createdAt: 0,
    }
    expect(bookmarkLabel(mark)).toBe("Funny bit, at 2:05")
  })
})

describe("parsePending", () => {
  const good = { id: "a", episodeId: "e1", positionSeconds: 61.5, createdAt: 9 }

  it("reads the list Swift writes", () => {
    expect(parsePending(JSON.stringify([good, { ...good, id: "b" }]))).toEqual([
      good,
      { ...good, id: "b" },
    ])
  })

  it("gives none for text that is not a list", () => {
    expect(parsePending("")).toEqual([])
    expect(parsePending("[]")).toEqual([])
    expect(parsePending("nope")).toEqual([])
    expect(parsePending('{"id":"a"}')).toEqual([])
  })

  it("leaves out entries that are missing a field or have a bad number", () => {
    const text = JSON.stringify([
      good,
      { ...good, id: "" },
      { ...good, id: "c", episodeId: undefined },
      { ...good, id: "d", positionSeconds: -1 },
      { ...good, id: "e", positionSeconds: "12" },
      { ...good, id: "f", createdAt: null },
      7,
      null,
    ])
    expect(parsePending(text)).toEqual([good])
  })
})

describe("pendingToBookmarks", () => {
  const pending = [
    { id: "a", episodeId: "e1", positionSeconds: 754, createdAt: 1 },
    { id: "b", episodeId: "gone", positionSeconds: 5, createdAt: 2 },
  ]

  it("keeps the bookmarks of library episodes, with the default title", () => {
    expect(pendingToBookmarks(pending, new Set(["e1"]))).toEqual([
      {
        id: "a",
        episodeId: "e1",
        positionSeconds: 754,
        createdAt: 1,
        title: "Bookmark at 12:34",
      },
    ])
  })
})

describe("bookmarks in the database", () => {
  function setup() {
    const db = openTestDatabase()
    addShow(db)
    addEpisode(db, { id: "e1" })
    addEpisode(db, { id: "e2" })
    return db
  }
  const add = (
    db: ReturnType<typeof openTestDatabase>,
    id: string,
    episode: string,
    position: number,
    created: number,
  ) =>
    db
      .prepare(ADD_BOOKMARK_SQL)
      .run(id, episode, position, defaultBookmarkTitle(position), created)
  const ids = (rows: unknown[]) =>
    rows.map((row) => bookmarkFromRow(row as Record<string, unknown>).id)

  it("lists an episode's bookmarks in the order of the episode", () => {
    const db = setup()
    add(db, "late", "e1", 900, 1)
    add(db, "early", "e1", 30, 2)
    add(db, "other", "e2", 10, 3)
    expect(ids(db.prepare(EPISODE_BOOKMARKS_SQL).all("e1"))).toEqual([
      "early",
      "late",
    ])
  })

  it("lists every bookmark, the newest first", () => {
    const db = setup()
    add(db, "a", "e1", 30, 100)
    add(db, "b", "e2", 10, 300)
    add(db, "c", "e1", 50, 200)
    expect(ids(db.prepare(ALL_BOOKMARKS_SQL).all())).toEqual(["b", "c", "a"])
  })

  it("saves a bookmark with an id it has once", () => {
    const db = setup()
    add(db, "a", "e1", 30, 100)
    db.prepare(RENAME_BOOKMARK_SQL).run("Mine", "a")
    add(db, "a", "e1", 30, 100)
    expect(db.prepare("SELECT title FROM bookmarks").all()).toEqual([
      { title: "Mine" },
    ])
  })

  it("renames and deletes", () => {
    const db = setup()
    add(db, "a", "e1", 30, 100)
    add(db, "b", "e1", 60, 200)
    db.prepare(RENAME_BOOKMARK_SQL).run("The good part", "a")
    db.prepare(DELETE_BOOKMARK_SQL).run("b")
    expect(db.prepare("SELECT id, title FROM bookmarks").all()).toEqual([
      { id: "a", title: "The good part" },
    ])
  })

  it("goes with its episode", () => {
    const db = setup()
    add(db, "a", "e1", 30, 100)
    db.prepare("DELETE FROM episodes WHERE id = 'e1'").run()
    expect(db.prepare("SELECT COUNT(*) AS n FROM bookmarks").get()).toEqual({
      n: 0,
    })
  })

  it("refuses a bookmark for an episode that isn't in the library", () => {
    const db = setup()
    expect(() => add(db, "a", "preview:x#y", 30, 100)).toThrow()
  })
})
