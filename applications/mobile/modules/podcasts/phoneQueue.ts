// LOFI-FORK: the podcasts section's list of next episodes for the Mac (see FORK.md).
//
// The phone writes `Podcasts/phone-queue.json` into the linked folder: the episodes the listener
// is likely to play next, so the Mac can read them ahead at night and send back where their ads
// are (docs/PODCASTS-ADS-TEACHING.md). These are the rules for choosing them and for the file's
// text. Nothing here touches the database or the folder (phoneNotesSync.ts does).
import type { LinkedFileRead } from "@/modules/lofi-score"

import { effectiveAdSettings } from "./ads"
import { SHOW_PLAYS_SQL } from "./homeSql"
import type { AdSkipSettings } from "./index"
import { isLocalEpisodeId } from "./localFiles"

export const QUEUE_FILE = "Podcasts/phone-queue.json"

/** The list holds this many episodes at most. */
export const QUEUE_MOST = 12

/** A show counts as one the listener plays when an episode of it was played in this many days. */
export const RECENT_DAYS = 14

const DAY = 86_400_000

/** An episode the queue may hold, with what the Mac and the show's switches need. */
export type QueueCandidate = {
  id: string
  feed: string
  guid: string
  title: string
  show: string
  audio: string
  skipAds: boolean | null
  skipPlugs: boolean | null
}

/** One episode of the file. The keys are written in this order. */
export type QueueEntry = {
  feed: string
  guid: string
  title: string
  show: string
  audio: string
  reason: "upNext" | "newest"
  rank: number
}

// MARK: Reading the database

const COLUMNS = `e.id, e.guid, e.title, e.audio_url, s.feed_url, s.title AS show_title,
  s.skip_ads, s.skip_plugs`

/** The SQL for the Up Next episodes: `count` ids as parameters. The order is Up Next's, not this. */
export function queueUpNextSql(count: number): string {
  const marks = Array.from({ length: count }, () => "?").join(", ")
  return `SELECT ${COLUMNS} FROM episodes e JOIN shows s ON s.id = e.show_id
    WHERE e.id IN (${marks})`
}

/**
 * The newest unplayed, unarchived, dated episode of each show that was played since the time
 * given as the one parameter, the show played last first. An added file's show is not one.
 */
export const QUEUE_NEWEST_SQL = `SELECT ${COLUMNS}
  FROM (${SHOW_PLAYS_SQL} HAVING MAX(history_at) >= ?) p
  JOIN shows s ON s.id = p.show_id
  JOIN episodes e ON e.id = (SELECT n.id FROM episodes n
    WHERE n.show_id = p.show_id AND n.played = 0 AND n.archived = 0
      AND n.published_at IS NOT NULL
    ORDER BY n.published_at DESC, n.id LIMIT 1)
  ORDER BY p.last_at DESC`

/** The time (milliseconds) a show must have been played since to count as played lately. */
export function newestSince(now: number): number {
  return now - RECENT_DAYS * DAY
}

function text(value: unknown): string {
  return typeof value === "string" ? value : ""
}

function flagOrNull(value: unknown): boolean | null {
  return value === null || value === undefined
    ? null
    : value === 1 || value === true
}

export function queueCandidate(row: Record<string, unknown>): QueueCandidate {
  return {
    id: text(row["id"]),
    feed: text(row["feed_url"]),
    guid: text(row["guid"]),
    title: text(row["title"]),
    show: text(row["show_title"]),
    audio: text(row["audio_url"]),
    skipAds: flagOrNull(row["skip_ads"]),
    skipPlugs: flagOrNull(row["skip_plugs"]),
  }
}

// MARK: Choosing

function isWebAddress(address: string): boolean {
  return /^https?:\/\/\S+/i.test(address)
}

/** Whether the Mac could fetch this episode and the phone would skip ads in it. */
function usable(episode: QueueCandidate, main: AdSkipSettings): boolean {
  if (isLocalEpisodeId(episode.id) || episode.guid === "") return false
  if (!isWebAddress(episode.feed) || !isWebAddress(episode.audio)) return false
  const own = effectiveAdSettings(main, episode)
  return own.skipAds || own.skipOwnPlugs || own.skipPromos
}

/**
 * The episodes to write: Up Next in its order, then the newest unplayed episode of each show
 * played lately (`newest`, in the order given), 12 at most. An added file, an episode the Mac
 * could not fetch, one of a show whose ad skipping is off, and a repeat are left out.
 */
export function chooseQueue(
  upNext: readonly QueueCandidate[],
  newest: readonly QueueCandidate[],
  main: AdSkipSettings,
): QueueEntry[] {
  const entries: QueueEntry[] = []
  const seen = new Set<string>()
  const add = (
    list: readonly QueueCandidate[],
    reason: QueueEntry["reason"],
  ) => {
    for (const episode of list) {
      if (entries.length >= QUEUE_MOST) return
      const key = `${episode.feed}\n${episode.guid}`
      if (seen.has(key) || !usable(episode, main)) continue
      seen.add(key)
      entries.push({
        feed: episode.feed,
        guid: episode.guid,
        title: episode.title,
        show: episode.show,
        audio: episode.audio,
        reason,
        rank: entries.length,
      })
    }
  }
  add(upNext, "upNext")
  add(newest, "newest")
  return entries
}

// MARK: The file

/** The file's text: `writtenAt` is in seconds since 1970. */
export function queueText(
  entries: readonly QueueEntry[],
  writtenAt: number,
): string {
  return JSON.stringify({ version: 1, writtenAt, episodes: entries })
}

function sameEpisodes(
  oldText: string,
  entries: readonly QueueEntry[],
): boolean {
  try {
    const old: unknown = JSON.parse(oldText)
    if (typeof old !== "object" || old === null) return false
    const record = old as Record<string, unknown>
    return (
      record["version"] === 1 &&
      JSON.stringify(record["episodes"]) === JSON.stringify(entries)
    )
  } catch {
    return false
  }
}

/**
 * The text to write over the file as it was read, or null when nothing is to be written: the
 * file already holds these episodes (the time is not compared, so the folder is not touched
 * again and again), or there is no file and nothing to put in one.
 */
export function queueToWrite(
  old: LinkedFileRead,
  entries: readonly QueueEntry[],
  now: number,
): string | null {
  if (old.status === "found" && sameEpisodes(old.text, entries)) return null
  if (old.status !== "found" && entries.length === 0) return null
  return queueText(entries, now)
}
