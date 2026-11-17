// LOFI-FORK: the podcasts section's library schema (see FORK.md).
//
// The tables of `podcasts.db` as a list of steps, one per schema version. Kept apart from
// db.ts, which needs the native SQLite module, so the steps can be tested. A new install
// runs every step; an older file runs only the steps it lacks.

/** The version a finished `podcasts.db` has (SQLite's `PRAGMA user_version`). */
export const SCHEMA_VERSION = 9

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

/** Version 3: where the listener put each show in "Your order" (null: not placed yet). */
const VERSION_3 = ["ALTER TABLE shows ADD COLUMN own_position INTEGER"]

/**
 * Version 4: the categories of each show (a JSON list of names, filled at the next refresh
 * for shows followed before), and answers kept for a day (Apple's charts).
 */
const VERSION_4 = [
  "ALTER TABLE shows ADD COLUMN categories TEXT",
  `CREATE TABLE cache (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    saved_at INTEGER NOT NULL
  )`,
]

/**
 * Version 5: the feed's transcript for each episode (its address and type, chosen from the
 * `podcast:transcript` tags). Filled at the next refresh for episodes saved before.
 */
const VERSION_5 = [
  "ALTER TABLE episodes ADD COLUMN transcript_url TEXT",
  "ALTER TABLE episodes ADD COLUMN transcript_type TEXT",
]

/**
 * Version 6: each show's own settings. Skip lengths are seconds, `speed` is null to follow the
 * player's speed, `skip_ads` and `skip_plugs` are null to follow the global switch, and
 * `auto_up_next` is off, top or bottom.
 */
const VERSION_6 = [
  "ALTER TABLE shows ADD COLUMN skip_intro INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE shows ADD COLUMN skip_outro INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE shows ADD COLUMN speed REAL",
  "ALTER TABLE shows ADD COLUMN auto_download INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE shows ADD COLUMN auto_up_next TEXT NOT NULL DEFAULT 'off'",
  "ALTER TABLE shows ADD COLUMN notify INTEGER NOT NULL DEFAULT 1",
  "ALTER TABLE shows ADD COLUMN skip_ads INTEGER",
  "ALTER TABLE shows ADD COLUMN skip_plugs INTEGER",
]

/**
 * Version 7: archived episodes, each show's auto-archive rules and its page's view (sort,
 * grouping by season, whether archived episodes show).
 */
const VERSION_7 = [
  "ALTER TABLE episodes ADD COLUMN archived INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE shows ADD COLUMN archive_after_played TEXT NOT NULL DEFAULT 'never'",
  "ALTER TABLE shows ADD COLUMN archive_after_days INTEGER",
  "ALTER TABLE shows ADD COLUMN keep_newest INTEGER",
  "ALTER TABLE shows ADD COLUMN episode_sort TEXT NOT NULL DEFAULT 'newest'",
  "ALTER TABLE shows ADD COLUMN group_by_season INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE shows ADD COLUMN show_archived INTEGER NOT NULL DEFAULT 0",
]

/**
 * Version 8: each show's own voice boost and silence trimming. Null follows the main setting
 * in Profile; otherwise the strength's name (off, low, medium, high / off, mild, medium,
 * strong).
 */
const VERSION_8 = [
  "ALTER TABLE shows ADD COLUMN voice_boost TEXT",
  "ALTER TABLE shows ADD COLUMN trim_silence TEXT",
]

/** Version 9: the address of the feed's `podcast:chapters` file for each episode. */
const VERSION_9 = ["ALTER TABLE episodes ADD COLUMN chapters_url TEXT"]

/** The steps in order: the one at index 0 takes a file from version 0 to 1. */
const STEPS = [
  VERSION_1,
  VERSION_2,
  VERSION_3,
  VERSION_4,
  VERSION_5,
  VERSION_6,
  VERSION_7,
  VERSION_8,
  VERSION_9,
]

/**
 * The statements that bring a file at `fromVersion` up to SCHEMA_VERSION, ending with the
 * new version number. Empty when the file is already current. Run them in one transaction.
 */
export function migrationStatements(fromVersion: number): string[] {
  if (fromVersion >= SCHEMA_VERSION) return []
  const statements = STEPS.slice(Math.max(0, fromVersion)).flat()
  return [...statements, `PRAGMA user_version = ${SCHEMA_VERSION}`]
}
