// LOFI-FORK: the podcasts section's episode search in your shows (see FORK.md).
//
// The query is run against a real SQLite (Node's own, in memory) with the library's real
// tables, so the matching and the order are tested, not just the text of the query.
import { describe, expect, it } from "vitest"

import { migrationStatements } from "./schema"
import {
  SEARCH_LIMIT,
  hitFromRow,
  likePattern,
  localSearchQuery,
  searchWords,
} from "./search"

describe("searchWords", () => {
  it("splits on any spaces and drops empty words", () => {
    expect(searchWords("  space \t  race\n")).toEqual(["space", "race"])
    expect(searchWords("")).toEqual([])
    expect(searchWords("   ")).toEqual([])
  })
})

describe("likePattern", () => {
  it("finds the word anywhere and escapes %, _ and the backslash", () => {
    expect(likePattern("moon")).toBe("%moon%")
    expect(likePattern("100%")).toBe("%100\\%%")
    expect(likePattern("a_b")).toBe("%a\\_b%")
    expect(likePattern("a\\b")).toBe("%a\\\\b%")
  })
})

describe("localSearchQuery", () => {
  it("is null when nothing was typed", () => {
    expect(localSearchQuery("")).toBeNull()
    expect(localSearchQuery("  \t ")).toBeNull()
  })

  it("asks for every word in the title or the notes, and for the limit", () => {
    const query = localSearchQuery(" moon  base ")
    expect(query?.params).toEqual([
      "%moon%",
      "%moon%",
      "%base%",
      "%base%",
      "%moon%",
      "%base%",
      SEARCH_LIMIT,
    ])
    expect(query?.sql.match(/\?/g)).toHaveLength(query?.params.length ?? 0)
  })
})

// Node's built-in SQLite is there from Node 22.13; older versions skip the rest.
let Database:
  | (new (path: string) => {
      exec(sql: string): void
      prepare(sql: string): {
        run(...values: unknown[]): unknown
        all(...values: unknown[]): Record<string, unknown>[]
      }
    })
  | null = null
try {
  Database = (await import("node:sqlite")).DatabaseSync as never
} catch {
  Database = null
}

describe.skipIf(!Database)("running the query", () => {
  function library() {
    const db = new Database!(":memory:")
    for (const statement of migrationStatements(0)) db.exec(statement)
    db.exec(
      `INSERT INTO shows (id, feed_url, title, image_url, added_at, refreshed_at)
       VALUES ('s1', 'https://a.test/rss', 'Space Show', 'https://img/s1.jpg', 0, 0),
              ('s2', 'https://b.test/rss', 'Other Show', NULL, 0, 0)`,
    )
    const add = db.prepare(
      `INSERT INTO episodes (id, show_id, guid, title, published_at, notes, audio_url, audio_type)
       VALUES (?, ?, ?, ?, ?, ?, 'https://cdn.test/a.mp3', 'audio/mpeg')`,
    )
    const episodes: [string, string, string, number | null, string][] = [
      ["e1", "s1", "Moon base", 1000, "About the lunar camp."],
      ["e2", "s1", "Rockets", 3000, "A moon base is not a base on Mars."],
      ["e3", "s2", "Base of the moon", 2000, ""],
      ["e4", "s2", "Undated moon base", null, ""],
      ["e5", "s2", "Only the moon", 5000, "No b-word here."],
      ["e6", "s2", "Sale 100% off", 4000, "Under_score and back\\slash"],
      ["e7", "s2", "Sale 1000 off", 4500, ""],
    ]
    for (const [id, show, title, date, notes] of episodes) {
      add.run(id, show, id, title, date, notes)
    }
    return (input: string, limit?: number) => {
      const query = localSearchQuery(input, limit)
      if (!query) return []
      return db
        .prepare(query.sql)
        .all(...query.params)
        .map((row) => hitFromRow(row).episode.id)
    }
  }

  it("needs every word, in the title or the notes", () => {
    const search = library()
    expect(search("moon base")).toEqual(["e3", "e1", "e4", "e2"])
    expect(search("moon")).toContain("e5")
    expect(search("moon mars")).toEqual(["e2"])
    expect(search("nothing here at all")).toEqual([])
  })

  it("puts title matches first, then the newest, then undated", () => {
    // e3 (2000) and e1 (1000) and e4 (undated) have both words in the title; e2 only in the notes.
    expect(library()("moon base")).toEqual(["e3", "e1", "e4", "e2"])
  })

  it("takes % and _ literally, and the backslash too", () => {
    const search = library()
    expect(search("100%")).toEqual(["e6"])
    expect(search("under_score")).toEqual(["e6"])
    expect(search("back\\slash")).toEqual(["e6"])
    expect(search("%")).toEqual(["e6"])
    expect(search("_")).toEqual(["e6"])
  })

  it("leaves archived episodes out", () => {
    const db = new Database!(":memory:")
    for (const statement of migrationStatements(0)) db.exec(statement)
    db.exec(
      `INSERT INTO shows (id, feed_url, title, added_at, refreshed_at)
       VALUES ('s1', 'u', 'Show', 0, 0);
       INSERT INTO episodes (id, show_id, guid, title, notes, audio_url, audio_type, archived)
       VALUES ('e1', 's1', 'g1', 'Hello there', '', 'https://x/a.mp3', 'audio/mpeg', 0),
              ('e2', 's1', 'g2', 'Hello again', '', 'https://x/b.mp3', 'audio/mpeg', 1)`,
    )
    const query = localSearchQuery("hello")!
    const found = db
      .prepare(query.sql)
      .all(...query.params)
      .map((row) => hitFromRow(row).episode.id)
    expect(found).toEqual(["e1"])
  })

  it("ignores case and keeps to the limit", () => {
    const search = library()
    expect(search("MOON", 2)).toHaveLength(2)
    expect(search("SPACE")).toEqual([])
  })

  it("brings the show's name and picture with each hit", () => {
    const db = new Database!(":memory:")
    for (const statement of migrationStatements(0)) db.exec(statement)
    db.exec(
      `INSERT INTO shows (id, feed_url, title, image_url, added_at, refreshed_at)
       VALUES ('s1', 'u', 'Space Show', 'https://img/s1.jpg', 0, 0);
       INSERT INTO episodes (id, show_id, guid, title, notes, audio_url, audio_type)
       VALUES ('e1', 's1', 'g', 'Hello', '', 'https://x/a.mp3', 'audio/mpeg')`,
    )
    const query = localSearchQuery("hello")!
    const hit = hitFromRow(db.prepare(query.sql).all(...query.params)[0]!)
    expect(hit.showTitle).toBe("Space Show")
    expect(hit.showImageUrl).toBe("https://img/s1.jpg")
    expect(hit.episode.title).toBe("Hello")
  })
})
