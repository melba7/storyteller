// LOFI-FORK: the podcasts section's Library rooms (see FORK.md).
import { describe, expect, it } from "vitest"

import { recentShowsFromRows, updatedLabel } from "./rooms"
import { LATEST_SQL, RECENT_SHOWS_SQL } from "./roomsSql"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

function ids(rows: unknown[], key = "id"): string[] {
  return rows.map((row) => String((row as Record<string, unknown>)[key]))
}

describe("Latest Episodes", () => {
  it("lists dated, unarchived episodes of followed shows, newest first", () => {
    const db = openTestDatabase()
    addShow(db, "s1")
    addShow(db, "s2")
    addShow(db, "local-files", "Your files")
    addEpisode(db, { id: "a", show_id: "s1", published_at: 1000 })
    addEpisode(db, { id: "b", show_id: "s2", published_at: 3000 })
    addEpisode(db, { id: "c", show_id: "s1", published_at: 2000 })
    addEpisode(db, { id: "old", show_id: "s1", published_at: 5, archived: 1 })
    addEpisode(db, { id: "undated", show_id: "s1", published_at: null })
    addEpisode(db, { id: "mine", show_id: "local-files", published_at: 9000 })
    expect(ids(db.prepare(LATEST_SQL).all())).toEqual(["b", "c", "a"])
  })

  it("keeps played episodes (they are still the latest)", () => {
    const db = openTestDatabase()
    addShow(db)
    addEpisode(db, { id: "a", published_at: 1000, played: 1 })
    expect(ids(db.prepare(LATEST_SQL).all())).toEqual(["a"])
  })
})

describe("Recently Updated", () => {
  function setup() {
    const db = openTestDatabase()
    for (const [id, title, added] of [
      ["s1", "Alpha", 0],
      ["s2", "Beta", 0],
      ["s3", "Gamma", 0],
      ["s4", "Delta", 5000],
    ] as const) {
      addShow(db, id, title)
      db.prepare("UPDATE shows SET added_at = ? WHERE id = ?").run(added, id)
    }
    addShow(db, "local-files", "Your files")
    return db
  }

  it("orders the shows by their newest episode and leaves out the ones without", () => {
    const db = setup()
    addEpisode(db, { id: "a", show_id: "s1", published_at: 1000 })
    addEpisode(db, { id: "b", show_id: "s2", published_at: 3000 })
    addEpisode(db, { id: "c", show_id: "s1", published_at: 2000 })
    addEpisode(db, { id: "x", show_id: "s3", published_at: null })
    addEpisode(db, { id: "m", show_id: "local-files", published_at: 9000 })
    const found = db.prepare(RECENT_SHOWS_SQL).all()
    expect(ids(found, "show_id")).toEqual(["s2", "s1"])
    expect(
      recentShowsFromRows(found as Record<string, unknown>[]).map(
        (r) => r.newestAt,
      ),
    ).toEqual([3000, 2000])
  })

  it("counts unplayed, unarchived episodes since the show was followed", () => {
    const db = setup()
    addEpisode(db, { id: "a", show_id: "s1", published_at: 1000 })
    addEpisode(db, { id: "b", show_id: "s1", published_at: 2000, played: 1 })
    addEpisode(db, { id: "c", show_id: "s2", published_at: 2000, archived: 1 })
    // Before s4 was followed, so it is not new.
    addEpisode(db, { id: "d", show_id: "s4", published_at: 100 })
    const byShow = new Map(
      (db.prepare(RECENT_SHOWS_SQL).all() as Record<string, unknown>[]).map(
        (row) => [row["show_id"], row["unplayed"]],
      ),
    )
    expect(byShow.get("s1")).toBe(1)
    expect(byShow.get("s2")).toBe(0)
    expect(byShow.get("s4")).toBe(0)
  })

  it("breaks ties by title", () => {
    const db = setup()
    addEpisode(db, { id: "a", show_id: "s2", published_at: 1000 })
    addEpisode(db, { id: "b", show_id: "s1", published_at: 1000 })
    expect(ids(db.prepare(RECENT_SHOWS_SQL).all(), "show_id")).toEqual([
      "s1",
      "s2",
    ])
  })
})

describe("updatedLabel", () => {
  const now = new Date(2026, 10, 17, 15, 0).getTime()
  const ago = (days: number, hour = 9) =>
    new Date(2026, 10, 17 - days, hour).getTime()

  it("says today, yesterday, days and weeks", () => {
    expect(updatedLabel(ago(0, 1), now)).toBe("Updated today")
    expect(updatedLabel(ago(1, 23), now)).toBe("Updated yesterday")
    expect(updatedLabel(ago(2), now)).toBe("2 days ago")
    expect(updatedLabel(ago(6), now)).toBe("6 days ago")
    expect(updatedLabel(ago(7), now)).toBe("1 week ago")
    expect(updatedLabel(ago(20), now)).toBe("2 weeks ago")
  })

  it("falls back to the date after eight weeks", () => {
    expect(updatedLabel(new Date(2026, 5, 1).getTime(), now)).toBe("1 Jun 2026")
  })

  it("counts a future date as today", () => {
    expect(updatedLabel(now + 3 * 86_400_000, now)).toBe("Updated today")
  })
})
