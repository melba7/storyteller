// LOFI-FORK: the podcasts section's library file (see FORK.md).
//
// Shows and episodes live in their own SQLite file, `podcasts.db`, next to the books'
// database. Storyteller's own database, its migrations and its store are not touched.
// Not imported by any test, because op-sqlite is native.
import {
  ANDROID_DATABASE_PATH,
  type DB,
  IOS_DOCUMENT_PATH,
  open,
} from "@op-engineering/op-sqlite"
import { randomUUID } from "expo-crypto"
import { Platform } from "react-native"

import { notifyLibraryChanged } from "./changes"
import { normalizeFeedUrl } from "./feedUrl"
import {
  Podcasts,
  type PodcastFeedData,
  type PodcastFeedEpisode,
} from "./index"
import {
  type FetchedEpisode,
  type Show,
  type StoredEpisode,
  episodeFromRow,
  mergeEpisodes,
  showFromRow,
  sortEpisodes,
} from "./library"
import { readableError } from "./nativeError"
import { migrationStatements } from "./schema"

let opened: Promise<DB> | null = null

/** Opens the file the first time it is needed and creates or upgrades its tables. */
function database(): Promise<DB> {
  opened ??= (async () => {
    const db = open({
      name: "podcasts.db",
      location:
        Platform.OS === "android"
          ? ANDROID_DATABASE_PATH
          : `${IOS_DOCUMENT_PATH}/SQLite`,
    })
    await db.execute("PRAGMA foreign_keys = ON")
    const result = await db.execute("PRAGMA user_version")
    const version = Number(result.rows[0]?.["user_version"] ?? 0)
    const statements = migrationStatements(version)
    if (statements.length > 0) {
      await db.transaction(async (tx) => {
        for (const statement of statements) await tx.execute(statement)
      })
    }
    return db
  })()
  // A failed open is tried again next time.
  opened.catch(() => {
    opened = null
  })
  return opened
}

async function rows(sql: string, params: (string | number)[] = []) {
  const db = await database()
  return (await db.execute(sql, params)).rows
}

// MARK: Reading

export async function listShows(): Promise<Show[]> {
  const found = await rows("SELECT * FROM shows ORDER BY title COLLATE NOCASE")
  return found.map(showFromRow)
}

export async function getShow(id: string): Promise<Show | null> {
  const found = await rows("SELECT * FROM shows WHERE id = ?", [id])
  return found[0] ? showFromRow(found[0]) : null
}

/** A show's episodes, newest first. */
export async function listEpisodes(showId: string): Promise<StoredEpisode[]> {
  const found = await rows("SELECT * FROM episodes WHERE show_id = ?", [showId])
  return sortEpisodes(found.map(episodeFromRow))
}

export async function getEpisode(id: string): Promise<StoredEpisode | null> {
  const found = await rows("SELECT * FROM episodes WHERE id = ?", [id])
  return found[0] ? episodeFromRow(found[0]) : null
}

// MARK: Playing

/** Keeps where the listener is in an episode, and whether it counts as played. */
export async function savePlayback(
  episodeId: string,
  position: number,
  played: boolean,
): Promise<void> {
  const db = await database()
  await db.execute(
    "UPDATE episodes SET position_seconds = ?, played = ?, last_played_at = ? WHERE id = ?",
    [Math.max(0, position), played ? 1 : 0, Date.now(), episodeId],
  )
  notifyLibraryChanged()
}

/** The episode played most recently, for the mini player after the app restarts. */
export async function lastPlayedEpisode(): Promise<StoredEpisode | null> {
  const found = await rows(
    "SELECT * FROM episodes WHERE last_played_at IS NOT NULL ORDER BY last_played_at DESC LIMIT 1",
  )
  return found[0] ? episodeFromRow(found[0]) : null
}

/** Keeps the main colour of a show's artwork, worked out once by the player. */
export async function saveArtworkColor(
  showId: string,
  color: string,
): Promise<void> {
  const db = await database()
  await db.execute("UPDATE shows SET artwork_color = ? WHERE id = ?", [
    color,
    showId,
  ])
  notifyLibraryChanged()
}

// MARK: Reading a feed

function orNull<T>(value: T | null | undefined): T | null {
  return value ?? null
}

function fetchedEpisode(episode: PodcastFeedEpisode): FetchedEpisode {
  return {
    guid: episode.guid,
    title: episode.title,
    publishedAt: orNull(episode.publishedAt),
    durationSeconds: orNull(episode.durationSeconds),
    notes: episode.notes,
    audioUrl: episode.audioUrl,
    audioType: episode.audioType,
    audioBytes: orNull(episode.audioBytes),
    imageUrl: orNull(episode.imageUrl),
    season: orNull(episode.season),
    number: orNull(episode.number),
  }
}

async function fetchFeed(feedUrl: string): Promise<PodcastFeedData> {
  if (!Podcasts) throw new Error("Podcasts need the iOS app.")
  try {
    return await Podcasts.fetchFeed(feedUrl)
  } catch (cause) {
    throw new Error(readableError(cause))
  }
}

// MARK: Writing

function insertEpisode(showId: string, episode: FetchedEpisode) {
  return [
    `INSERT INTO episodes (id, show_id, guid, title, published_at, duration_seconds, notes,
       audio_url, audio_type, audio_bytes, image_url, season, number)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      randomUUID(),
      showId,
      episode.guid,
      episode.title,
      episode.publishedAt,
      episode.durationSeconds,
      episode.notes,
      episode.audioUrl,
      episode.audioType,
      episode.audioBytes,
      episode.imageUrl,
      episode.season,
      episode.number,
    ],
  ] as const
}

function updateEpisode(id: string, episode: FetchedEpisode) {
  return [
    `UPDATE episodes SET title = ?, published_at = ?, duration_seconds = ?, notes = ?,
       audio_url = ?, audio_type = ?, audio_bytes = ?, image_url = ?, season = ?, number = ?
     WHERE id = ?`,
    [
      episode.title,
      episode.publishedAt,
      episode.durationSeconds,
      episode.notes,
      episode.audioUrl,
      episode.audioType,
      episode.audioBytes,
      episode.imageUrl,
      episode.season,
      episode.number,
      id,
    ],
  ] as const
}

/** Subscribes to the feed at this link (a pasted one or one from the directory). */
export async function subscribe(link: string): Promise<Show> {
  const feedUrl = normalizeFeedUrl(link)
  const existing = (
    await rows("SELECT * FROM shows WHERE feed_url = ?", [feedUrl])
  )[0]
  if (existing) return showFromRow(existing)

  const feed = await fetchFeed(feedUrl)
  const now = Date.now()
  const id = randomUUID()
  const { insert } = mergeEpisodes([], feed.episodes.map(fetchedEpisode))
  const db = await database()
  await db.transaction(async (tx) => {
    await tx.execute(
      `INSERT INTO shows (id, feed_url, title, author, description, image_url, link, language,
         added_at, refreshed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        feedUrl,
        feed.title,
        orNull(feed.author),
        feed.description,
        orNull(feed.imageUrl),
        orNull(feed.link),
        orNull(feed.language),
        now,
        now,
      ],
    )
    for (const episode of insert) {
      const [sql, params] = insertEpisode(id, episode)
      await tx.execute(sql, [...params])
    }
  })
  notifyLibraryChanged()
  const show = await getShow(id)
  if (!show) throw new Error("The show couldn't be saved.")
  return show
}

/** Reads the show's feed again: adds new episodes, updates changed ones, deletes none. */
export async function refreshShow(id: string): Promise<void> {
  const show = await getShow(id)
  if (!show) return
  const feed = await fetchFeed(show.feedUrl)
  const { insert, update } = mergeEpisodes(
    await listEpisodes(id),
    feed.episodes.map(fetchedEpisode),
  )
  const db = await database()
  await db.transaction(async (tx) => {
    await tx.execute(
      `UPDATE shows SET title = ?, author = ?, description = ?, image_url = ?, link = ?,
         language = ?, refreshed_at = ? WHERE id = ?`,
      [
        feed.title,
        orNull(feed.author),
        feed.description,
        orNull(feed.imageUrl),
        orNull(feed.link),
        orNull(feed.language),
        Date.now(),
        id,
      ],
    )
    for (const episode of insert) {
      const [sql, params] = insertEpisode(id, episode)
      await tx.execute(sql, [...params])
    }
    for (const { id: episodeId, episode } of update) {
      const [sql, params] = updateEpisode(episodeId, episode)
      await tx.execute(sql, [...params])
    }
  })
  notifyLibraryChanged()
}

/** Refreshes every show, one after the other. A show that fails does not stop the rest. */
export async function refreshAllShows(): Promise<{ failed: string[] }> {
  const failed: string[] = []
  for (const show of await listShows()) {
    try {
      await refreshShow(show.id)
    } catch {
      failed.push(show.title)
    }
  }
  return { failed }
}

/** Removes the show and its episodes from the library. */
export async function unsubscribe(id: string): Promise<void> {
  const db = await database()
  await db.transaction(async (tx) => {
    await tx.execute("DELETE FROM episodes WHERE show_id = ?", [id])
    await tx.execute("DELETE FROM shows WHERE id = ?", [id])
  })
  notifyLibraryChanged()
}
