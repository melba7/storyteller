// LOFI-FORK: the podcasts section's library schema (see FORK.md).
import { describe, expect, it } from "vitest"

import { SCHEMA_VERSION, migrationStatements } from "./schema"

describe("migrationStatements", () => {
  it("builds a new file from nothing up to the current version", () => {
    const statements = migrationStatements(0)
    expect(statements[0]).toContain("CREATE TABLE shows")
    expect(statements.some((s) => s.includes("CREATE TABLE episodes"))).toBe(
      true,
    )
    expect(statements.at(-1)).toBe(`PRAGMA user_version = ${SCHEMA_VERSION}`)
  })

  it("upgrades a version 1 file in place by only adding columns", () => {
    const statements = migrationStatements(1)
    expect(statements).toEqual([
      "ALTER TABLE episodes ADD COLUMN position_seconds REAL NOT NULL DEFAULT 0",
      "ALTER TABLE episodes ADD COLUMN played INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE episodes ADD COLUMN last_played_at INTEGER",
      "ALTER TABLE shows ADD COLUMN artwork_color TEXT",
      "PRAGMA user_version = 2",
    ])
  })

  it("does nothing for a current file", () => {
    expect(migrationStatements(SCHEMA_VERSION)).toEqual([])
    expect(migrationStatements(SCHEMA_VERSION + 1)).toEqual([])
  })

  it("gives a new file the same final steps as an upgraded one", () => {
    expect(migrationStatements(0).slice(-5)).toEqual(migrationStatements(1))
  })

  it("treats a broken version number as a new file", () => {
    expect(migrationStatements(-1)).toEqual(migrationStatements(0))
  })
})
