// LOFI-FORK: the podcasts section's wait for the Mac's copy (see FORK.md).
//
// Reads the Mac's `coming` list from the linked folder and says which episodes of the library the
// phone must not download by itself now (the rules are in coming.ts, which also makes one key of
// two spellings of a feed address). Not imported by any test,
// because the database and the native module are not there.
import { LofiScore } from "@/modules/lofi-score"

import { comingKey, heldKeys, parseComing } from "./coming"
import { rows } from "./db"

const AHEAD_FILE = "Podcasts/ahead-ads.json"

/** The guids go to the database a few at a time, well under SQLite's limit on placeholders. */
const CHUNK = 200

/**
 * The ids of the episodes the Mac is preparing and the phone waits for. Empty when there is no
 * linked folder, no file, nothing coming or any trouble reading: then the phone downloads as before.
 */
export async function heldEpisodeIds(now = Date.now()): Promise<Set<string>> {
  const ids = new Set<string>()
  try {
    if (!LofiScore) return ids
    const read = await LofiScore.readLinkedFolderFileStatus(AHEAD_FILE)
    if (read.status !== "found") return ids
    const keys = heldKeys(parseComing(read.text), now)
    if (keys.size === 0) return ids
    const guids = [...new Set([...keys].map((key) => key.split("\n")[1] ?? ""))]
    for (let i = 0; i < guids.length; i += CHUNK) {
      const part = guids.slice(i, i + CHUNK)
      const marks = part.map(() => "?").join(", ")
      for (const row of await rows(
        `SELECT e.id, e.guid, s.feed_url FROM episodes e JOIN shows s ON s.id = e.show_id
         WHERE e.guid IN (${marks})`,
        part,
      )) {
        if (keys.has(comingKey(String(row["feed_url"]), String(row["guid"]))))
          ids.add(String(row["id"]))
      }
    }
  } catch (cause) {
    console.warn("Couldn't read which episodes the Mac is preparing", cause)
  }
  return ids
}
