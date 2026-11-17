// LOFI-FORK: the podcasts section's own audio files (see FORK.md).
//
// Adding files from the Files app, and renaming and deleting them. The native module copies
// each file in and installs it like a download; this makes the "Your files" show and the
// episode rows. The rules are in localFiles.ts. Not imported by any test, because the
// database and the native module are not there.
import * as DocumentPicker from "expo-document-picker"
import * as FileSystem from "expo-file-system/legacy"

import { notifyLibraryChanged } from "./changes"
import { database, getEpisode } from "./db"
import { deleteDownload } from "./downloadsNative"
import { Podcasts } from "./index"
import {
  LOCAL_ARTWORK,
  LOCAL_FEED_URL,
  LOCAL_SHOW_ID,
  LOCAL_SHOW_NOTES,
  LOCAL_SHOW_TITLE,
  type ImportedAudio,
  importSummary,
  localEpisodeValues,
} from "./localFiles"
import { readableError } from "./nativeError"
import { removeManyFromUpNext } from "./upNextNative"

/** Makes the "Your files" show the first time it is needed. */
async function ensureLocalShow(): Promise<void> {
  const now = Date.now()
  const db = await database()
  await db.execute(
    `INSERT OR IGNORE INTO shows (id, feed_url, title, description, image_url, added_at,
       refreshed_at, categories) VALUES (?, ?, ?, ?, ?, ?, ?, '[]')`,
    [
      LOCAL_SHOW_ID,
      LOCAL_FEED_URL,
      LOCAL_SHOW_TITLE,
      LOCAL_SHOW_NOTES,
      LOCAL_ARTWORK,
      now,
      now,
    ],
  )
}

/** Saves the episode of an installed file. Returns false when it was in the library already. */
async function addEpisode(file: ImportedAudio): Promise<boolean> {
  if (await getEpisode(file.episodeId)) return false
  await ensureLocalShow()
  const v = localEpisodeValues(file, Date.now())
  const db = await database()
  await db.execute(
    `INSERT INTO episodes (id, show_id, guid, title, published_at, duration_seconds, notes,
       audio_url, audio_type, audio_bytes) VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?)`,
    [
      v.id,
      LOCAL_SHOW_ID,
      v.guid,
      v.title,
      v.publishedAt,
      v.durationSeconds,
      v.audioUrl,
      v.audioType,
      v.audioBytes,
    ],
  )
  return true
}

/**
 * Opens the Files app and adds the audio files picked there. Returns what to tell the
 * listener, or null when nothing was picked. A file that cannot be added is named, the
 * rest still go in.
 */
export async function pickAndAddAudioFiles(): Promise<string | null> {
  if (!Podcasts) throw new Error("Adding files needs the iOS app.")
  const picked = await DocumentPicker.getDocumentAsync({
    type: "audio/*",
    multiple: true,
    copyToCacheDirectory: true,
  })
  if (picked.canceled || picked.assets.length === 0) return null
  let added = 0
  let already = 0
  const failed: { name: string; reason: string }[] = []
  for (const asset of picked.assets) {
    try {
      const file = await Podcasts.importAudioFile(asset.uri, asset.name)
      if (await addEpisode(file)) added += 1
      else already += 1
    } catch (cause) {
      failed.push({ name: asset.name, reason: readableError(cause) })
    } finally {
      // The picker's copy in the cache is no longer needed.
      await FileSystem.deleteAsync(asset.uri, { idempotent: true }).catch(
        () => undefined,
      )
    }
  }
  if (added > 0) notifyLibraryChanged()
  return importSummary(added, already, failed)
}

/** Gives an added file a new title. */
export async function renameLocalEpisode(
  id: string,
  title: string,
): Promise<void> {
  const db = await database()
  await db.execute("UPDATE episodes SET title = ? WHERE id = ?", [title, id])
  notifyLibraryChanged()
}

/** Deletes an added file: its audio, its side files, its place in Up Next and its episode. */
export async function deleteLocalEpisode(id: string): Promise<void> {
  await deleteDownload(id)
  await removeManyFromUpNext([id])
  const db = await database()
  await db.execute("DELETE FROM episodes WHERE id = ?", [id])
  notifyLibraryChanged()
}
