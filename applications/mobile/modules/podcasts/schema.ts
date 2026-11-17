// LOFI-FORK: the podcasts section's library schema (see FORK.md).
//
// The tables of `podcasts.db` as a list of steps, one per schema version. Kept apart from
// db.ts, which needs the native SQLite module, so the steps can be tested. A new install
// runs every step; an older file runs only the steps it lacks.

/** The version a finished `podcasts.db` has (SQLite's `PRAGMA user_version`). */
export const SCHEMA_VERSION = 2

const VERSION_1 = [
  `CREATE TABLE shows (
    id TEXT PRIMARY KEY NOT NULL,
    feed_url TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    author TEXT,
    description TEXT NOT NULL DEFAULT '',
    image_url TEXT,
    link TEXT,
    language TEXT,
    added_at INTEGER NOT NULL,
    refreshed_at INTEGER NOT NULL
  )`,
  `CREATE TABLE episodes (
    id TEXT PRIMARY KEY NOT NULL,
    show_id TEXT NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
    guid TEXT NOT NULL,
    title TEXT NOT NULL,
    published_at INTEGER,
    duration_seconds REAL,
    notes TEXT NOT NULL DEFAULT '',
    audio_url TEXT NOT NULL,
    audio_type TEXT NOT NULL,
    audio_bytes INTEGER,
    image_url TEXT,
    season INTEGER,
    number INTEGER,
    UNIQUE (show_id, guid)
  )`,
  "CREATE INDEX episodes_show_published ON episodes (show_id, published_at)",
]

/** Version 2: where each episode was left, whether it was played, and the show's colour. */
const VERSION_2 = [
  "ALTER TABLE episodes ADD COLUMN position_seconds REAL NOT NULL DEFAULT 0",
  "ALTER TABLE episodes ADD COLUMN played INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE episodes ADD COLUMN last_played_at INTEGER",
  "ALTER TABLE shows ADD COLUMN artwork_color TEXT",
]

/** The steps in order: the one at index 0 takes a file from version 0 to 1. */
const STEPS = [VERSION_1, VERSION_2]

/**
 * The statements that bring a file at `fromVersion` up to SCHEMA_VERSION, ending with the
 * new version number. Empty when the file is already current. Run them in one transaction.
 */
export function migrationStatements(fromVersion: number): string[] {
  if (fromVersion >= SCHEMA_VERSION) return []
  const statements = STEPS.slice(Math.max(0, fromVersion)).flat()
  return [...statements, `PRAGMA user_version = ${SCHEMA_VERSION}`]
}
