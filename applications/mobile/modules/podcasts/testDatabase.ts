// LOFI-FORK: the podcasts section's tests (see FORK.md).
//
// A real SQLite database in memory for tests, with every schema step run. It uses Node's own
// SQLite, so tests can check the SQL the app sends to op-sqlite. Only tests import this.
import { DatabaseSync } from "node:sqlite"

import { migrationStatements } from "./schema"

/** A new database at the current schema version, or built from the statements given. */
export function openTestDatabase(
  statements: readonly string[] = migrationStatements(0),
): DatabaseSync {
  const db = new DatabaseSync(":memory:")
  db.exec("PRAGMA foreign_keys = ON")
  for (const statement of statements) db.exec(statement)
  return db
}

/** Inserts a show and returns its id. */
export function addShow(db: DatabaseSync, id = "show-1", title = "A show") {
  db.prepare(
    "INSERT INTO shows (id, feed_url, title, added_at, refreshed_at) VALUES (?, ?, ?, 0, 0)",
  ).run(id, `https://example.com/${id}.xml`, title)
  return id
}

/** Inserts an episode with the given columns (anything not given has a default). */
export function addEpisode(
  db: DatabaseSync,
  values: Record<string, string | number | null> & { id: string },
) {
  const row: Record<string, string | number | null> = {
    show_id: "show-1",
    guid: values.id,
    title: `Episode ${values.id}`,
    audio_url: `https://example.com/${values.id}.mp3`,
    audio_type: "audio/mpeg",
    ...values,
  }
  const columns = Object.keys(row)
  db.prepare(
    `INSERT INTO episodes (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`,
  ).run(...Object.values(row))
}
