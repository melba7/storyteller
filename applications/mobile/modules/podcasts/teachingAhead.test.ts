import { describe, expect, it } from "vitest"

import { migrationStatements } from "./schema"
import { AHEAD_PER_SHOW } from "./teaching"
import { aheadEpisodesQuery, sharedRead, textChanged } from "./teachingAhead"

describe("textChanged", () => {
  it("is true for the first text, and for a text that is not the one last sent", () => {
    expect(textChanged("{}", null)).toBe(true)
    expect(textChanged('{"e1":{}}', "{}")).toBe(true)
  })

  it("is false for the text last sent, even when it is the empty table", () => {
    expect(textChanged('{"e1":{}}', '{"e1":{}}')).toBe(false)
    expect(textChanged("{}", "{}")).toBe(false)
  })
})

describe("sharedRead", () => {
  it("reads once however many times it is asked, and hands the same answer to each", async () => {
    let reads = 0
    const read = sharedRead(async () => {
      reads += 1
      return ["a", "b"]
    })
    const first = await read()
    const second = await read()
    expect(reads).toBe(1)
    expect(second).toBe(first)
  })

  it("does not read before it is asked", () => {
    let reads = 0
    sharedRead(async () => {
      reads += 1
      return 1
    })
    expect(reads).toBe(0)
  })

  it("hands a failure to everyone who asks, and each share reads again", async () => {
    let reads = 0
    const read = sharedRead(async () => {
      reads += 1
      throw new Error("no database")
    })
    await expect(read()).rejects.toThrow("no database")
    await expect(read()).rejects.toThrow("no database")
    expect(reads).toBe(1)
    const another = sharedRead(async () => {
      reads += 1
      return 2
    })
    expect(await another()).toBe(2)
    expect(reads).toBe(2)
  })
})

describe("aheadEpisodesQuery", () => {
  it("has a place for each of its values", () => {
    for (const guids of [[], ["g1"], ["g1", "g2", "g3"]]) {
      const query = aheadEpisodesQuery("s1", guids)
      expect(query.sql.match(/\?/g)).toHaveLength(query.params.length)
    }
    expect(aheadEpisodesQuery("s1", []).params).toEqual(["s1"])
    expect(aheadEpisodesQuery("s1", ["g1", "g2"]).params).toEqual([
      "s1",
      "s1",
      "g1",
      "g2",
    ])
  })

  it("limits the read to the newest few of the table's size", () => {
    expect(aheadEpisodesQuery("s1", []).sql).toContain(
      `LIMIT ${AHEAD_PER_SHOW}`,
    )
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
  const pad = (number: number) => String(number).padStart(2, "0")

  function library() {
    const db = new Database!(":memory:")
    for (const statement of migrationStatements(0)) db.exec(statement)
    db.exec(
      `INSERT INTO shows (id, feed_url, title, image_url, added_at, refreshed_at)
       VALUES ('s1', 'https://a.test/rss', 'One', NULL, 0, 0),
              ('s2', 'https://b.test/rss', 'Two', NULL, 0, 0)`,
    )
    const add = db.prepare(
      `INSERT INTO episodes
         (id, show_id, guid, title, published_at, audio_url, audio_type, played, archived)
       VALUES (?, ?, ?, ?, ?, 'https://cdn.test/a.mp3', 'audio/mpeg', ?, ?)`,
    )
    // Twenty unplayed episodes of show one, e00 the newest, and three that are not for the
    // table: played, archived and undated (the undated one is unplayed, so it counts last).
    for (let i = 0; i < 20; i++) {
      add.run(`e${pad(i)}`, "s1", `g${pad(i)}`, `T${i}`, 10_000 - i, 0, 0)
    }
    add.run("played", "s1", "g-played", "P", 20_000, 1, 0)
    add.run("away", "s1", "g-away", "A", 20_001, 0, 1)
    add.run("undated", "s1", "g-undated", "U", null, 0, 0)
    // An old episode of the phone's list, and one of the other show with a guid of the same style.
    add.run("old", "s1", "g-old", "O", 1, 1, 0)
    add.run("other", "s2", "g-old", "X", 5_000, 0, 0)
    add.run("other-new", "s2", "g-new", "Y", 6_000, 0, 0)
    add.run("other-undated", "s2", "g-undated", "Z", null, 0, 0)
    return (showId: string, guids: string[] = []) => {
      const query = aheadEpisodesQuery(showId, guids)
      return db
        .prepare(query.sql)
        .all(...query.params)
        .map((row) => String(row["id"]))
        .sort()
    }
  }

  it("reads the newest unplayed, unarchived episodes of a show and no more", () => {
    const ids = library()("s1")
    expect(ids).toHaveLength(AHEAD_PER_SHOW)
    expect(ids).toEqual(
      Array.from({ length: AHEAD_PER_SHOW }, (_, i) => `e${pad(i)}`),
    )
  })

  it("reads an episode of the phone's list whatever its age or state, and no other show's", () => {
    const ids = library()("s1", ["g-old", "g-away", "g-gone"])
    expect(ids).toHaveLength(AHEAD_PER_SHOW + 2)
    expect(ids).toContain("old")
    expect(ids).toContain("away")
    expect(ids).not.toContain("other")
  })

  it("reads one episode once when it is both newest and in the list", () => {
    const ids = library()("s1", ["g00", "g01"])
    expect(ids).toEqual(
      Array.from({ length: AHEAD_PER_SHOW }, (_, i) => `e${pad(i)}`),
    )
  })

  it("counts an undated episode last, so it is read only when the show has too few dated ones", () => {
    expect(library()("s2")).toEqual(["other", "other-new", "other-undated"])
    expect(library()("s1")).not.toContain("undated")
  })
})
