// LOFI-FORK: the podcasts section's library schema (see FORK.md).
import { describe, expect, it } from "vitest"

import { SCHEMA_VERSION, migrationStatements } from "./schema"
import { SETTING_COLUMNS } from "./showSettings"

/** The statements of the step that takes a file from `version` to the next one. */
function stepFrom(version: number): string[] {
  const now = migrationStatements(version).slice(0, -1)
  const later = migrationStatements(version + 1).slice(0, -1)
  return now.slice(0, now.length - later.length)
}

describe("migrationStatements", () => {
  it("builds a new file from nothing up to the current version", () => {
    const statements = migrationStatements(0)
    expect(statements[0]).toContain("CREATE TABLE shows")
    expect(statements.some((s) => s.includes("CREATE TABLE episodes"))).toBe(
      true,
    )
    expect(statements.at(-1)).toBe(`PRAGMA user_version = ${SCHEMA_VERSION}`)
  })

  it("is at version 8", () => {
    expect(SCHEMA_VERSION).toBe(8)
  })

  it("upgrades a version 1 file in place by only adding columns", () => {
    const statements = migrationStatements(1)
    expect(statements.slice(0, 4)).toEqual([
      "ALTER TABLE episodes ADD COLUMN position_seconds REAL NOT NULL DEFAULT 0",
      "ALTER TABLE episodes ADD COLUMN played INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE episodes ADD COLUMN last_played_at INTEGER",
      "ALTER TABLE shows ADD COLUMN artwork_color TEXT",
    ])
    expect(statements.filter((s) => s.startsWith("DROP"))).toEqual([])
    expect(statements.at(-1)).toBe(`PRAGMA user_version = ${SCHEMA_VERSION}`)
  })

  it("version 2 adds the own-order column", () => {
    expect(stepFrom(2)).toEqual([
      "ALTER TABLE shows ADD COLUMN own_position INTEGER",
    ])
  })

  it("version 4 adds a categories column and a cache table", () => {
    const statements = stepFrom(3)
    expect(statements).toHaveLength(2)
    expect(statements[0]).toBe("ALTER TABLE shows ADD COLUMN categories TEXT")
    expect(statements[1]).toContain("CREATE TABLE cache")
    expect(statements[1]).toContain("key TEXT PRIMARY KEY")
    expect(statements[1]).toContain("saved_at INTEGER")
  })

  it("version 5 adds the transcript columns", () => {
    expect(stepFrom(4)).toEqual([
      "ALTER TABLE episodes ADD COLUMN transcript_url TEXT",
      "ALTER TABLE episodes ADD COLUMN transcript_type TEXT",
    ])
  })

  it("version 6 adds the show settings, with the defaults of the screen", () => {
    const statements = stepFrom(5)
    expect(
      statements.every((s) => s.startsWith("ALTER TABLE shows ADD COLUMN")),
    ).toBe(true)
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN skip_intro INTEGER NOT NULL DEFAULT 0",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN auto_download INTEGER NOT NULL DEFAULT 1",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN auto_up_next TEXT NOT NULL DEFAULT 'off'",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN notify INTEGER NOT NULL DEFAULT 1",
    )
    // Null means follow the player's speed and the global switches.
    expect(statements).toContain("ALTER TABLE shows ADD COLUMN speed REAL")
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN skip_ads INTEGER",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN skip_plugs INTEGER",
    )
  })

  it("version 7 adds archived episodes and the archive and view settings", () => {
    const statements = stepFrom(6)
    expect(statements).toContain(
      "ALTER TABLE episodes ADD COLUMN archived INTEGER NOT NULL DEFAULT 0",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN archive_after_played TEXT NOT NULL DEFAULT 'never'",
    )
    expect(statements).toContain(
      "ALTER TABLE shows ADD COLUMN episode_sort TEXT NOT NULL DEFAULT 'newest'",
    )
    expect(statements).toHaveLength(7)
  })

  it("version 8 adds the feed's chapters address to episodes", () => {
    expect(stepFrom(7)).toEqual([
      "ALTER TABLE episodes ADD COLUMN chapters_url TEXT",
    ])
  })

  it("has a column for every setting the screen saves", () => {
    const columns = migrationStatements(0)
      .filter((s) => s.startsWith("ALTER TABLE shows ADD COLUMN"))
      .map((s) => s.split(" ")[5])
    for (const column of SETTING_COLUMNS) expect(columns).toContain(column)
  })

  it("does nothing for a current file", () => {
    expect(migrationStatements(SCHEMA_VERSION)).toEqual([])
    expect(migrationStatements(SCHEMA_VERSION + 1)).toEqual([])
  })

  it("gives a new file the same final steps as an upgraded one", () => {
    const fresh = migrationStatements(0)
    const upgraded = migrationStatements(1)
    expect(fresh.slice(-upgraded.length)).toEqual(upgraded)
  })

  it("treats a broken version number as a new file", () => {
    expect(migrationStatements(-1)).toEqual(migrationStatements(0))
  })
})
