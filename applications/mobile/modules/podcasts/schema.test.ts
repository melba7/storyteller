// LOFI-FORK: the podcasts section's library schema (see FORK.md).
import { describe, expect, it } from "vitest"

import { SCHEMA_VERSION, migrationStatements } from "./schema"

const VERSION_5_STATEMENTS = [
  "ALTER TABLE episodes ADD COLUMN transcript_url TEXT",
  "ALTER TABLE episodes ADD COLUMN transcript_type TEXT",
]
const VERSION_4_STATEMENTS = migrationStatements(3).slice(
  0,
  -1 - VERSION_5_STATEMENTS.length,
)

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
      "ALTER TABLE shows ADD COLUMN own_position INTEGER",
      ...VERSION_4_STATEMENTS,
      ...VERSION_5_STATEMENTS,
      "PRAGMA user_version = 5",
    ])
  })

  it("upgrades a version 2 file with the own-order column and version 4's changes", () => {
    expect(migrationStatements(2)).toEqual([
      "ALTER TABLE shows ADD COLUMN own_position INTEGER",
      ...VERSION_4_STATEMENTS,
      ...VERSION_5_STATEMENTS,
      "PRAGMA user_version = 5",
    ])
  })

  it("upgrades a version 4 file with the transcript columns only", () => {
    expect(migrationStatements(4)).toEqual([
      ...VERSION_5_STATEMENTS,
      "PRAGMA user_version = 5",
    ])
  })

  it("upgrades a version 3 file with a categories column and a cache table", () => {
    const statements = migrationStatements(3)
    expect(statements).toHaveLength(5)
    expect(statements[0]).toBe("ALTER TABLE shows ADD COLUMN categories TEXT")
    expect(statements[1]).toContain("CREATE TABLE cache")
    expect(statements[1]).toContain("key TEXT PRIMARY KEY")
    expect(statements[1]).toContain("value TEXT")
    expect(statements[1]).toContain("saved_at INTEGER")
    expect(statements.slice(2)).toEqual([
      ...VERSION_5_STATEMENTS,
      "PRAGMA user_version = 5",
    ])
  })

  it("does nothing for a current file", () => {
    expect(SCHEMA_VERSION).toBe(5)
    expect(migrationStatements(5)).toEqual([])
    expect(migrationStatements(SCHEMA_VERSION)).toEqual([])
    expect(migrationStatements(SCHEMA_VERSION + 1)).toEqual([])
  })

  it("gives a new file the same final steps as an upgraded one", () => {
    expect(migrationStatements(0).slice(-10)).toEqual(migrationStatements(1))
  })

  it("treats a broken version number as a new file", () => {
    expect(migrationStatements(-1)).toEqual(migrationStatements(0))
  })
})
