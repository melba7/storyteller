// LOFI-FORK: the podcasts section's tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { CACHE_KEEP_MS, PRUNE_CACHE_SQL } from "./cacheSql"
import { openTestDatabase } from "./testDatabase"

describe("PRUNE_CACHE_SQL", () => {
  it("deletes rows older than a week and keeps newer ones", () => {
    const db = openTestDatabase()
    const now = 100 * CACHE_KEEP_MS
    const put = db.prepare(
      "INSERT INTO cache (key, value, saved_at) VALUES (?, 'v', ?)",
    )
    put.run("old", now - CACHE_KEEP_MS - 1)
    put.run("edge", now - CACHE_KEEP_MS)
    put.run("fresh", now - 1000)
    db.prepare(PRUNE_CACHE_SQL).run(now - CACHE_KEEP_MS)
    const keys = db
      .prepare("SELECT key FROM cache ORDER BY key")
      .all()
      .map((r) => r["key"])
    expect(keys).toEqual(["edge", "fresh"])
  })
})
