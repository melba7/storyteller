// LOFI-FORK: the podcasts section's feed reading and writing (see FORK.md).
//
// Reading a feed, following and refreshing a show, and the one-day cache for Apple's
// charts. These use db.ts's open file. Not imported by any test, because op-sqlite is native.
import { randomUUID } from "expo-crypto"

import { settleArrived, loadList, PENDING_KEY } from "./appleMemory"
import { feedKey, findShowByFeed, pendingGuids } from "./applePodcasts"
import { type NewEpisode, newEpisodes } from "./automatic"
import { CACHE_KEEP_MS, PRUNE_CACHE_SQL } from "./cacheSql"
import { notifyLibraryChanged } from "./changes"
import { database, getShow, listEpisodes, listShows, rows } from "./db"
import { MARK_PLAYED_FROM_APPLE_SQL } from "./episodeSql"
import { feedChanged } from "./feedChanges"
import { movedFeedUrl } from "./feedMove"
import { normalizeFeedUrl } from "./feedUrl"
import { Podcasts, type PodcastFeedData } from "./index"
import {
  type FetchedEpisode,
  type Show,
  fetchedEpisode,
  mergeEpisodes,
} from "./library"
import { feedShows, isLocalFeedUrl } from "./localFiles"
import { readableError } from "./nativeError"
import { fundingFromJson, peopleFromJson, toJson } from "./people"
import { serialByKey } from "./serialByKey"

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

/** A pull-to-refresh and the automatic run never read one show at the same time. */
const oneRefreshAtATime = serialByKey()

/**
 * Two follows of one feed (the Apple Podcasts list, an OPML import, a pasted link) never run
 * at the same time, whatever the spelling of the address: the second finds the show.
 */
const oneFollowAtATime = serialByKey()

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
    `UPDATE episodes SET guid = ?, title = ?, published_at = ?, duration_seconds = ?, notes = ?,
       audio_url = ?, audio_type = ?, audio_bytes = ?, image_url = ?, season = ?, number = ?,
       transcript_url = ?, transcript_type = ?, chapters_url = ?, people = ?
     WHERE id = ?`,
    [
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
      id,
    ],
  ] as const
}

/** Subscribes to the feed at this link (a pasted one or one from the directory). */
export function subscribe(link: string): Promise<Show> {
  const feedUrl = normalizeFeedUrl(link)
  return oneFollowAtATime(feedKey(feedUrl), () => follow(feedUrl))
}

async function follow(feedUrl: string): Promise<Show> {
  // The same feed under another spelling (http, www, a closing slash) is the same show.
  const existing = findShowByFeed(await listShows(), feedUrl)
  if (existing) return existing

  const feed = await fetchFeed(feedUrl)
  // Looked at again: another follow of a feed that moved may have saved it meanwhile.
  const savedMeanwhile = findShowByFeed(await listShows(), feedUrl)
  if (savedMeanwhile) return savedMeanwhile
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
export function refreshShow(id: string): Promise<NewEpisode[]> {
  return oneRefreshAtATime(id, () => readFeedAgain(id))
}

async function readFeedAgain(id: string): Promise<NewEpisode[]> {
  const show = await getShow(id)
  // "Your files" has no feed to read.
  if (!show || isLocalFeedUrl(show.feedUrl)) return []
  const feed = await fetchFeed(show.feedUrl)
  const stored = await listEpisodes(id)
  // A feed that announced a new address is followed there, so the show keeps matching the
  // Mac's teaching table and Apple Podcasts.
  const movedTo = movedFeedUrl(show, feed.newFeedUrl, await listShows())
  const { insert, update } = mergeEpisodes(
    stored,
    feed.episodes.map(fetchedEpisode),
  )
  const ids = insert.map(() => randomUUID())
  // Episodes Apple Podcasts says were finished before they reached this phone arrive played,
  // so they do not count as new.
  const finished = pendingGuids(
    await loadList(PENDING_KEY).catch(() => []),
    show.feedUrl,
  )
  const arrived = insert.map((episode) => finished.has(episode.guid))
  const db = await database()
  await db.transaction(async (tx) => {
    // feedChanged (feedChanges.ts) compares these same values: a new column needs a line there.
    await tx.execute(
      `UPDATE shows SET title = ?, author = ?, description = ?, image_url = ?, link = ?,
         language = ?, refreshed_at = ?, categories = ?, funding = ?, people = ?,
         feed_url = ?
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
        movedTo ?? show.feedUrl,
        id,
      ],
    )
    for (const [at, episode] of insert.entries()) {
      const [sql, params] = insertEpisode(ids[at] as string, id, episode)
      await tx.execute(sql, [...params])
      if (arrived[at]) {
        await tx.execute(MARK_PLAYED_FROM_APPLE_SQL, [
          Date.now(),
          id,
          episode.guid,
        ])
      }
    }
    for (const { id: episodeId, episode } of update) {
      const [sql, params] = updateEpisode(episodeId, episode)
      await tx.execute(sql, [...params])
    }
  })
  await settleArrived(
    show.feedUrl,
    insert.filter((_, at) => arrived[at]).map((episode) => episode.guid),
  )
  // A feed that says nothing new does not make every open screen read the library again.
  if (
    movedTo !== null ||
    feedChanged(show, feed, { inserted: insert.length, updated: update.length })
  ) {
    notifyLibraryChanged()
  }
  return newEpisodes(
    id,
    insert.filter((_, at) => !arrived[at]),
    ids.filter((_, at) => !arrived[at]),
    stored,
    Date.now(),
  )
}

/**
 * Refreshes every show, one after the other. A show that fails does not stop the rest. The
 * screens are told once when the run is over, whatever the shows said on their own, so a
 * change that `feedChanged` missed still reaches them. `added` is every episode the refresh
 * added. `onAdded` is called with each show's new episodes as soon as that show is read, so a
 * run that is cut short loses none of them. The Apple Podcasts list is read first, but for no
 * more than 30 seconds (a pull-to-refresh reads it too); the automatic run reads it itself and
 * passes `appleSync: false`.
 */
export async function refreshAllShows(
  options: {
    appleSync?: boolean
    onAdded?: (added: NewEpisode[]) => Promise<void>
  } = {},
): Promise<{
  failed: string[]
  added: NewEpisode[]
}> {
  const failed: string[] = []
  const added: NewEpisode[] = []
  if (options.appleSync !== false) {
    const { syncApplePodcastsBriefly } = await import("./appleSync")
    await syncApplePodcastsBriefly()
  }
  for (const show of feedShows(await listShows())) {
    try {
      const batch = await refreshShow(show.id)
      added.push(...batch)
      if (batch.length > 0) await options.onAdded?.(batch)
    } catch {
      failed.push(show.title)
    }
  }
  notifyLibraryChanged()
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
  // Answers older than a week are not read again; the transcripts among them are large.
  await db.execute(PRUNE_CACHE_SQL, [Date.now() - CACHE_KEEP_MS])
}
