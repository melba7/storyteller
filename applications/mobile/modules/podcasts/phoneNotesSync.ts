// LOFI-FORK: the podcasts section's notes for the Mac (see FORK.md).
//
// Writes what the phone noted about ads into the linked folder: the pending notes are added to
// `Podcasts/phone-notes.jsonl` (with each episode's feed, guid, title and audio address from
// the database), and the skip log and diary are written to `Podcasts/phone-diary.jsonl` when
// they changed. A note leaves the phone's pending list only after the folder says it was
// written, and a file that may exist but could not be read is not written over: it is tried
// again at the next run. The episodes the listener is likely to play next go to
// `Podcasts/phone-queue.json` when they changed. The rules are in phoneNotes.ts and
// phoneQueue.ts. Not imported by any test, because the database and the native modules are not
// there.
import AsyncStorage from "@react-native-async-storage/async-storage"

import { LofiScore } from "@/modules/lofi-score"

import { getAdSkipSettings } from "./adsNative"
import { rows } from "./db"
import { Podcasts } from "./index"
import {
  DIARY_FILE,
  NOTES_FILE,
  type NoteEpisode,
  type PendingNote,
  diaryStamp,
  mergeNoteLines,
  newestNoteAt,
  noteLine,
  oldNotesText,
  parsePendingNotes,
} from "./phoneNotes"
import {
  QUEUE_FILE,
  QUEUE_NEWEST_SQL,
  type QueueEntry,
  chooseQueue,
  newestSince,
  queueCandidate,
  queueToWrite,
  queueUpNextSql,
} from "./phoneQueue"
import { listUpNext } from "./upNextNative"

const DIARY_STAMP_KEY = "podcasts.phoneDiary.stamp"

/** The ids go to the database a few at a time, well under SQLite's limit on placeholders. */
const CHUNK = 200

async function episodesById(ids: readonly string[]) {
  const found = new Map<string, NoteEpisode>()
  for (let i = 0; i < ids.length; i += CHUNK) {
    const part = ids.slice(i, i + CHUNK)
    const marks = part.map(() => "?").join(", ")
    for (const row of await rows(
      `SELECT e.id, e.guid, e.title, e.audio_url, s.feed_url
       FROM episodes e JOIN shows s ON s.id = e.show_id
       WHERE e.id IN (${marks})`,
      part,
    )) {
      found.set(String(row["id"]), {
        feed: String(row["feed_url"] ?? ""),
        guid: String(row["guid"] ?? ""),
        title: String(row["title"] ?? ""),
        address: String(row["audio_url"] ?? ""),
      })
    }
  }
  return found
}

async function feedsByShow(ids: readonly string[]) {
  const found = new Map<string, string>()
  for (let i = 0; i < ids.length; i += CHUNK) {
    const part = ids.slice(i, i + CHUNK)
    const marks = part.map(() => "?").join(", ")
    for (const row of await rows(
      `SELECT id, feed_url FROM shows WHERE id IN (${marks})`,
      part,
    )) {
      found.set(String(row["id"]), String(row["feed_url"] ?? ""))
    }
  }
  return found
}

async function lines(notes: readonly PendingNote[]): Promise<string[]> {
  const episodes = await episodesById([...new Set(notes.map((n) => n.episode))])
  const gone = notes.filter((n) => !episodes.has(n.episode) && n.show !== "")
  const shows = await feedsByShow([...new Set(gone.map((n) => n.show))])
  return notes.map((note) =>
    noteLine(note, episodes.get(note.episode) ?? null, shows.get(note.show)),
  )
}

/** Adds the pending notes to the notes file; they are removed only once it is written. */
async function writeNotes(): Promise<void> {
  if (!Podcasts || !LofiScore) return
  const readAt = Date.now()
  const pending = await Podcasts.readPendingAdNotes()
  const { notes, count } = parsePendingNotes(pending)
  if (count === 0) return
  const old = oldNotesText(
    await LofiScore.readLinkedFolderFileStatus(NOTES_FILE),
  )
  if (old === null) return
  const text = mergeNoteLines(old, await lines(notes))
  const result = await LofiScore.writeLinkedFolderFile(NOTES_FILE, text)
  if (result.status === "written")
    await Podcasts.removePendingAdNotes(count, newestNoteAt(notes, readAt))
}

/** Writes the skip log and the diary when their text is not what was last written. */
async function writeDiary(): Promise<void> {
  if (!Podcasts || !LofiScore) return
  const text = await Podcasts.readSkipLogText()
  if (!text) return
  const stamp = diaryStamp(text)
  if (stamp === (await AsyncStorage.getItem(DIARY_STAMP_KEY))) return
  const result = await LofiScore.writeLinkedFolderFile(DIARY_FILE, text)
  if (result.status === "written")
    await AsyncStorage.setItem(DIARY_STAMP_KEY, stamp)
}

/** The episodes the listener is likely to play next, as the file for the Mac holds them. */
export async function currentQueue(): Promise<QueueEntry[]> {
  const ids = (await listUpNext()).map((item) => item.id).slice(0, CHUNK)
  const queued =
    ids.length === 0 ? [] : await rows(queueUpNextSql(ids.length), ids)
  const byId = new Map(
    queued.map((row) => [String(row["id"]), queueCandidate(row)]),
  )
  const upNext = ids.flatMap((id) => byId.get(id) ?? [])
  const newest = (await rows(QUEUE_NEWEST_SQL, [newestSince(Date.now())])).map(
    queueCandidate,
  )
  return chooseQueue(upNext, newest, await getAdSkipSettings())
}

/** Writes the episodes the listener is likely to play next, when they are not what the file holds. */
async function writeQueue(
  readQueue: () => Promise<QueueEntry[]>,
): Promise<void> {
  if (!Podcasts || !LofiScore) return
  const entries = await readQueue()
  const text = queueToWrite(
    await LofiScore.readLinkedFolderFileStatus(QUEUE_FILE),
    entries,
    Math.floor(Date.now() / 1000),
  )
  if (text !== null) await LofiScore.writeLinkedFolderFile(QUEUE_FILE, text)
}

/**
 * Sends the phone's notes and its list of next episodes to the Mac. One part failing does not
 * stop the others. `readQueue` reads the list of next episodes; a run that read it already for
 * something else passes the same read.
 */
export async function syncPhoneNotes(
  readQueue: () => Promise<QueueEntry[]> = currentQueue,
): Promise<void> {
  for (const part of [writeNotes, writeDiary, () => writeQueue(readQueue)]) {
    try {
      await part()
    } catch (cause) {
      console.warn("Couldn't write the phone's notes for the Mac", cause)
    }
  }
}
