// LOFI-FORK: the podcasts section's hand-filled playlists (see FORK.md).
//
// Pure rules: what is kept of an episode and its show when it is put in a playlist (so it
// plays even from a show that isn't followed), turning the kept items back into episodes,
// and what "Play all" does. The database calls are in dbPlaylists.ts.
import { type Show, type StoredEpisode } from "./library"
import { upNextOrder } from "./selection"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

/** What a playlist item remembers about its show. */
type KeptShow = Pick<
  Show,
  "id" | "feedUrl" | "title" | "author" | "imageUrl" | "link" | "language"
>

/** The episode's own details (what a feed gives) and its ids. */
type KeptEpisode = Omit<
  StoredEpisode,
  "positionSeconds" | "played" | "lastPlayedAt" | "archived" | "starredAt"
>

export type Snapshot = { episode: KeptEpisode; show: KeptShow | null }

/** What an item of a playlist is, once resolved: the episode and show to play it with. */
export type PlaylistEntry = {
  episode: StoredEpisode
  show: Show | null
  /** True when the episode is in the library (it has a card, a place and a played mark). */
  inLibrary: boolean
}

/** The text kept in the database for an episode put in a playlist. */
export function snapshotOf(episode: StoredEpisode, show: Show | null): string {
  const {
    positionSeconds: _position,
    played: _played,
    lastPlayedAt: _last,
    archived: _archived,
    starredAt: _starred,
    ...kept
  } = episode
  const snapshot: Snapshot = {
    episode: kept,
    show: show
      ? {
          id: show.id,
          feedUrl: show.feedUrl,
          title: show.title,
          author: show.author,
          imageUrl: show.imageUrl,
          link: show.link,
          language: show.language,
        }
      : null,
  }
  return JSON.stringify(snapshot)
}

function text(value: unknown): value is string {
  return typeof value === "string"
}

/** The kept episode and show, or null when the text isn't one (a broken or older value). */
export function parseSnapshot(saved: string): Snapshot | null {
  try {
    const value: unknown = JSON.parse(saved)
    if (typeof value !== "object" || value === null) return null
    const { episode, show } = value as { episode?: unknown; show?: unknown }
    if (typeof episode !== "object" || episode === null) return null
    const e = episode as Record<string, unknown>
    if (
      !text(e["id"]) ||
      !text(e["showId"]) ||
      !text(e["title"]) ||
      !text(e["audioUrl"]) ||
      !text(e["audioType"])
    ) {
      return null
    }
    return {
      episode: e as unknown as KeptEpisode,
      show:
        typeof show === "object" && show !== null && text((show as KeptShow).id)
          ? (show as KeptShow)
          : null,
    }
  } catch {
    return null
  }
}

function showOf(kept: KeptShow): Show {
  return {
    ...kept,
    description: "",
    addedAt: 0,
    refreshedAt: 0,
    artworkColor: null,
    ownPosition: null,
    categories: [],
    funding: [],
    people: [],
    settings: DEFAULT_SHOW_SETTINGS,
  }
}

/**
 * The playlist's items as episodes to show and play, in order. An episode still in the
 * library (`live`) is read from there, with its place and played mark, and so is its show;
 * any other comes from what was kept, unplayed. An item that can't be read is left out.
 */
export function resolveItems(
  items: readonly { episodeId: string; snapshot: string }[],
  live: ReadonlyMap<string, StoredEpisode>,
  shows: ReadonlyMap<string, Show>,
): PlaylistEntry[] {
  return items.flatMap((item): PlaylistEntry[] => {
    const kept = parseSnapshot(item.snapshot)
    const stored = live.get(item.episodeId)
    if (stored) {
      const show =
        shows.get(stored.showId) ?? (kept?.show ? showOf(kept.show) : null)
      return [{ episode: stored, show, inLibrary: true }]
    }
    if (!kept) return []
    return [
      {
        episode: {
          ...kept.episode,
          positionSeconds: 0,
          played: false,
          lastPlayedAt: null,
          archived: false,
          starredAt: null,
        },
        show: kept.show ? showOf(kept.show) : null,
        inLibrary: false,
      },
    ]
  })
}

/**
 * What "Play all" does with the playlist's episodes: the first plays now, and the rest go to
 * the top of Up Next, so they follow in order ahead of what was already queued.
 */
export function playAllPlan(ids: readonly string[]): {
  play: string | null
  queue: { id: string; place: "next" | "last" }[]
} {
  const [first, ...rest] = ids
  return { play: first ?? null, queue: upNextOrder(rest, "next") }
}
