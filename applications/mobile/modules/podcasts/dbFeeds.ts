// LOFI-FORK: the podcasts section's feed reading and writing (see FORK.md).
//
// Reading a feed, following and refreshing a show, and the one-day cache for Apple's
// charts. These use db.ts's open file. Not imported by any test, because op-sqlite is native.
import { randomUUID } from "expo-crypto"

import { type NewEpisode, newEpisodes } from "./automatic"
import { notifyLibraryChanged } from "./changes"
import { database, getShow, listEpisodes, listShows, rows } from "./db"
import { normalizeFeedUrl } from "./feedUrl"
import { Podcasts, type PodcastFeedData } from "./index"
import {
  type FetchedEpisode,
  type Show,
  fetchedEpisode,
  mergeEpisodes,
  showFromRow,
} from "./library"
import { feedShows, isLocalFeedUrl } from "./localFiles"
import { readableError } from "./nativeError"
import { fundingFromJson, peopleFromJson, toJson } from "./people"

// MARK: Reading a feed

function orNull<T>(value: T | null | undefined): T | null {
  return value ?? null
}

/** Downloads and reads a feed without saving it. Throws a message to show the listener. */
export async function fetchFeed(feedUrl: string): Promise<PodcastFeedData> {
  if (!Podcasts) throw new Error("Podcasts need the iOS app.")
  try {
    return await Podcasts.fetchFeed(feedUrl)
  } catch (cause) {
    throw new Error(readableError(cause))
  }
}

// MARK: Writing

function insertEpisode(id: string, showId: string, episode: FetchedEpisode) {
  return [
    `INSERT INTO episodes (id, show_id, guid, title, published_at, duration_seconds, notes,
       audio_url, audio_type, audio_bytes, image_url, season, number, transcript_url,
       transcript_type, chapters_url, people)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
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
      episode.transcriptUrl,
      episode.transcriptType,
      episode.chaptersUrl,
      toJson(episode.people),
    ],
  ] as const
}

function updateEpisode(id: string, episode: FetchedEpisode) {
  return [
    `UPDATE episodes SET title = ?, published_at = ?, duration_seconds = ?, notes = ?,
       audio_url = ?, audio_type = ?, audio_bytes = ?, image_url = ?, season = ?, number = ?,
       transcript_url = ?, transcript_type = ?, chapters_url = ?, people = ?
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
      episode.transcriptUrl,
      episode.transcriptType,
      episode.chaptersUrl,
      toJson(episode.people),
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
         added_at, refreshed_at, categories, funding, people)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
        JSON.stringify(feed.categories ?? []),
        toJson(fundingFromJson(toJson(feed.funding))),
        toJson(peopleFromJson(toJson(feed.people))),
      ],
    )
    for (const episode of insert) {
      const [sql, params] = insertEpisode(randomUUID(), id, episode)
      await tx.execute(sql, [...params])
    }
  })
  notifyLibraryChanged()
  const show = await getShow(id)
  if (!show) throw new Error("The show couldn't be saved.")
  return show
}

/**
 * Reads the show's feed again: adds new episodes, updates changed ones, deletes none. Returns
 * the episodes it added, for downloading the newest one by itself.
 */
export async function refreshShow(id: string): Promise<NewEpisode[]> {
  const show = await getShow(id)
  // "Your files" has no feed to read.
  if (!show || isLocalFeedUrl(show.feedUrl)) return []
  const feed = await fetchFeed(show.feedUrl)
  const { insert, update } = mergeEpisodes(
    await listEpisodes(id),
    feed.episodes.map(fetchedEpisode),
  )
  const ids = insert.map(() => randomUUID())
  const db = await database()
  await db.transaction(async (tx) => {
    await tx.execute(
      `UPDATE shows SET title = ?, author = ?, description = ?, image_url = ?, link = ?,
         language = ?, refreshed_at = ?, categories = ?, funding = ?, people = ?
       WHERE id = ?`,
      [
        feed.title,
        orNull(feed.author),
        feed.description,
        orNull(feed.imageUrl),
        orNull(feed.link),
        orNull(feed.language),
        Date.now(),
        JSON.stringify(feed.categories ?? []),
        toJson(fundingFromJson(toJson(feed.funding))),
        toJson(peopleFromJson(toJson(feed.people))),
        id,
      ],
    )
    for (const [at, episode] of insert.entries()) {
      const [sql, params] = insertEpisode(ids[at] as string, id, episode)
      await tx.execute(sql, [...params])
    }
    for (const { id: episodeId, episode } of update) {
      const [sql, params] = updateEpisode(episodeId, episode)
      await tx.execute(sql, [...params])
    }
  })
  notifyLibraryChanged()
  return newEpisodes(id, insert, ids)
}

/**
 * Refreshes every show, one after the other. A show that fails does not stop the rest.
 * `added` is every episode the refresh added.
 */
export async function refreshAllShows(): Promise<{
  failed: string[]
  added: NewEpisode[]
}> {
  const failed: string[] = []
  const added: NewEpisode[] = []
  for (const show of feedShows(await listShows())) {
    try {
      added.push(...(await refreshShow(show.id)))
    } catch {
      failed.push(show.title)
    }
  }
  return { failed, added }
}

// MARK: Kept answers

/** An answer kept in the cache table, with when it was saved (milliseconds since 1970). */
export async function cacheGet(
  key: string,
): Promise<{ value: string; savedAt: number } | null> {
  const found = await rows("SELECT value, saved_at FROM cache WHERE key = ?", [
    key,
  ])
  const row = found[0]
  if (!row || typeof row["value"] !== "string") return null
  return { value: row["value"], savedAt: Number(row["saved_at"] ?? 0) }
}

export async function cachePut(key: string, value: string): Promise<void> {
  const db = await database()
  await db.execute(
    "INSERT OR REPLACE INTO cache (key, value, saved_at) VALUES (?, ?, ?)",
    [key, value, Date.now()],
  )
}
