// LOFI-FORK: the podcasts section's per-show settings and archive (see FORK.md).
//
// Saves a show's settings and archives or unarchives episodes. Archiving deletes the
// download. Not imported by any test, because op-sqlite is native; the rules are in
// showSettings.ts, archive.ts and episodeList.ts.
import { notifyLibraryChanged } from "./changes"
import { database, listShows } from "./db"
import { deleteDownloads } from "./downloadsNative"
import {
  SETTING_COLUMNS,
  type ShowSettings,
  settingsMirror,
  showSettingsToValues,
} from "./showSettings"
import { writeShowSettings } from "./showSettingsNative"

/** Writes every show's playback settings to the file the Swift player reads. */
export async function syncShowSettings(): Promise<void> {
  const shows = await listShows()
  await writeShowSettings(
    JSON.stringify(
      settingsMirror(shows.map((s) => ({ id: s.id, settings: s.settings }))),
    ),
  )
}

/** Keeps a show's settings, and tells the player. */
export async function saveShowSettings(
  showId: string,
  settings: ShowSettings,
): Promise<void> {
  const db = await database()
  const assignments = SETTING_COLUMNS.map((column) => `${column} = ?`).join(
    ", ",
  )
  await db.execute(`UPDATE shows SET ${assignments} WHERE id = ?`, [
    ...showSettingsToValues(settings),
    showId,
  ])
  notifyLibraryChanged()
  try {
    await syncShowSettings()
  } catch (cause) {
    console.warn("Couldn't save the show's settings for the player", cause)
  }
}

/**
 * Archives episodes: their downloads are deleted first, so a download that can't be removed
 * leaves the episode as it was.
 */
export async function archiveEpisodes(ids: readonly string[]): Promise<void> {
  if (ids.length === 0) return
  await deleteDownloads([...ids])
  await setArchivedFlag(ids, 1)
}

export async function unarchiveEpisodes(ids: readonly string[]): Promise<void> {
  if (ids.length === 0) return
  await setArchivedFlag(ids, 0)
}

async function setArchivedFlag(ids: readonly string[], value: 0 | 1) {
  const db = await database()
  await db.transaction(async (tx) => {
    for (const id of ids) {
      await tx.execute("UPDATE episodes SET archived = ? WHERE id = ?", [
        value,
        id,
      ])
    }
  })
  notifyLibraryChanged()
}
