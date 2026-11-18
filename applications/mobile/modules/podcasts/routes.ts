// LOFI-FORK: the podcasts section's routes (see FORK.md).
//
// The section has four tabs (Home, New, Library, Search), each with its own stack. Every detail
// screen (a show, an episode, a playlist, the queue...) exists in all four stacks, so opening
// one stays in the tab you are in, and the link names that tab's group. The account sheet is a
// separate stack over the tabs.

export type TabGroup = "(home)" | "(new)" | "(library)" | "(search)"

const TABS: readonly TabGroup[] = ["(home)", "(new)", "(library)", "(search)"]

/** The tab's group when the screen is in New, Library or Search, else the Home tab's. */
export function tabBase(segments: readonly string[]): string {
  const tab = TABS.find((name) => segments.includes(name)) ?? "(home)"
  return `/podcasts/(tabs)/${tab}`
}

export type PodcastHref = {
  pathname: string
  params: { id: string }
}

function withId(
  segments: readonly string[],
  path: string,
  id: string,
): PodcastHref {
  return { pathname: `${tabBase(segments)}/${path}/[id]`, params: { id } }
}

export function showHref(segments: readonly string[], id: string): PodcastHref {
  return withId(segments, "show", id)
}

/** A show's own settings, in the tab you are in. */
export function settingsHref(
  segments: readonly string[],
  id: string,
): PodcastHref {
  return withId(segments, "show-settings", id)
}

export function episodeHref(
  segments: readonly string[],
  id: string,
): PodcastHref {
  return withId(segments, "episode", id)
}

/** A playlist's page (smart or hand-filled), in the tab you are in. */
export function playlistHref(
  segments: readonly string[],
  id: string,
): PodcastHref {
  return withId(segments, "playlist", id)
}

/** A smart playlist's rules editor (`id` is "new" for a new one). */
export function playlistEditHref(
  segments: readonly string[],
  id: string,
): PodcastHref {
  return withId(segments, "playlist-edit", id)
}

/** The pages without a parameter, in the tab you are in. */
function page(name: string) {
  return (segments: readonly string[]): string => `${tabBase(segments)}/${name}`
}

export const downloadsHref = page("downloads")
export const historyHref = page("history")
export const bookmarksHref = page("bookmarks")
/** The queue page ("Up Next"): the queue, then the Home shelf's episodes. */
export const upNextHref = page("up-next")
export const savedHref = page("saved")
export const latestHref = page("latest")
/** The followed shows' grid, with its layouts, orders and Arrange. */
export const showsHref = page("shows")
export const arrangeHref = page("arrange")

/**
 * A show read from its feed without saving it, in the tab you are in. A search result also
 * names its episode (guid, audio address) so the preview can point at it.
 */
export function previewHref(
  segments: readonly string[],
  feedUrl: string,
  episode: { guid?: string | null; audioUrl?: string | null } = {},
) {
  const params: { feed: string; guid?: string; audio?: string } = {
    feed: feedUrl,
  }
  if (episode.guid) params.guid = episode.guid
  if (episode.audioUrl) params.audio = episode.audioUrl
  return { pathname: `${tabBase(segments)}/preview`, params }
}

/**
 * A category's chart. Categories are opened from New and from Search, so the link stays in
 * Search when you are there and is New's otherwise.
 */
export function categoryHref(id: string, segments: readonly string[] = []) {
  const tab = segments.includes("(search)") ? "(search)" : "(new)"
  return {
    pathname: `/podcasts/(tabs)/${tab}/category/[id]`,
    params: { id },
  }
}

/** The tab roots, for links that change tab. */
export const HOME_HREF = "/podcasts/(tabs)/(home)"
export const NEW_HREF = "/podcasts/(tabs)/(new)"
export const LIBRARY_HREF = "/podcasts/(tabs)/(library)"
export const SEARCH_HREF = "/podcasts/(tabs)/(search)"

/** The account sheet (Profile) and the Stats page inside it. */
export const ACCOUNT_HREF = "/podcasts/account"
export const ACCOUNT_STATS_HREF = "/podcasts/account/stats"
