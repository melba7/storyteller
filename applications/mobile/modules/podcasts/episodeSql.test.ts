// LOFI-FORK: the podcasts section's episode actions (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  CLEAR_HISTORY_SQL,
  HISTORY_SQL,
  SET_PLAYED_SQL,
  SET_STARRED_SQL,
  STAR_ORDER_SQL,
  RECORD_LISTEN_SQL,
} from "./episodeSql"
import { migrationStatements } from "./schema"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

function setup() {
  const db = openTestDatabase()
  addShow(db)
  addEpisode(db, { id: "a", published_at: 1000 })
  addEpisode(db, { id: "b", published_at: 2000 })
  addEpisode(db, { id: "c", published_at: 3000 })
  return db
}

function ids(rows: unknown[]): string[] {
  return rows.map((row) => String((row as { id: string }).id))
}

describe("starring", () => {
  it("stamps the time when starring and clears it when unstarring", () => {
    const db = setup()
    db.prepare(SET_STARRED_SQL).run(500, "a")
    expect(
      db.prepare("SELECT starred_at FROM episodes WHERE id = 'a'").get(),
    ).toEqual({
      starred_at: 500,
    })
    db.prepare(SET_STARRED_SQL).run(null, "a")
    expect(
      db.prepare("SELECT starred_at FROM episodes WHERE id = 'a'").get(),
    ).toEqual({
      starred_at: null,
    })
  })

  it("lists starred episodes newest star first", () => {
    const db = setup()
    db.prepare(SET_STARRED_SQL).run(100, "a")
    db.prepare(SET_STARRED_SQL).run(300, "c")
    db.prepare(SET_STARRED_SQL).run(200, "b")
    expect(ids(db.prepare(STAR_ORDER_SQL).all())).toEqual(["c", "b", "a"])
  })
})

describe("marking played", () => {
  it("marks played, keeping the place", () => {
    const db = setup()
    db.prepare("UPDATE episodes SET position_seconds = 30 WHERE id = 'a'").run()
    db.prepare(SET_PLAYED_SQL).run(1, 1, "a")
    expect(
      db
        .prepare("SELECT played, position_seconds FROM episodes WHERE id = 'a'")
        .get(),
    ).toEqual({ played: 1, position_seconds: 30 })
  })

  it("marks unplayed and forgets the place", () => {
    const db = setup()
    db.prepare(
      "UPDATE episodes SET position_seconds = 30, played = 1 WHERE id = 'a'",
    ).run()
    db.prepare(SET_PLAYED_SQL).run(0, 0, "a")
    expect(
      db
        .prepare("SELECT played, position_seconds FROM episodes WHERE id = 'a'")
        .get(),
    ).toEqual({ played: 0, position_seconds: 0 })
  })
})

describe("the listening history", () => {
  it("lists episodes by when they were last listened to, newest first", () => {
    const db = setup()
    const first = RECORD_LISTEN_SQL
    db.prepare(first).run(5, 0, 1000, 1000, "b")
    db.prepare(first).run(5, 0, 3000, 3000, "a")
    db.prepare(first).run(5, 0, 2000, 2000, "c")
    expect(ids(db.prepare(HISTORY_SQL).all())).toEqual(["a", "c", "b"])
  })

  it("leaves out episodes never listened to", () => {
    const db = setup()
    expect(db.prepare(HISTORY_SQL).all()).toEqual([])
  })

  it("is emptied by clearing, which keeps the last-played times", () => {
    const db = setup()
    db.prepare(RECORD_LISTEN_SQL).run(5, 1, 1000, 1000, "a")
    db.prepare(CLEAR_HISTORY_SQL).run()
    expect(db.prepare(HISTORY_SQL).all()).toEqual([])
    expect(
      db
        .prepare("SELECT last_played_at, played FROM episodes WHERE id = 'a'")
        .get(),
    ).toEqual({ last_played_at: 1000, played: 1 })
  })

  it("fills the history from the last-played times of an older file", () => {
    const all = migrationStatements(0).slice(0, -1)
    const step = migrationStatements(7).slice(0, -1)
    const db = openTestDatabase(all.slice(0, all.length - step.length))
    addShow(db)
    addEpisode(db, { id: "a", last_played_at: 700 })
    addEpisode(db, { id: "b" })
    for (const statement of step) db.exec(statement)
    expect(
      db.prepare("SELECT id, history_at FROM episodes ORDER BY id").all(),
    ).toEqual([
      { id: "a", history_at: 700 },
      { id: "b", history_at: null },
    ])
  })
})
