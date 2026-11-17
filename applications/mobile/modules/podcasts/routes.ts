// LOFI-FORK: the podcasts section's routes (see FORK.md).
//
// A show's page and an episode's page exist in the tabs (Podcasts and Discover; Profile has
// the episode's card for its Downloads, Up Next the same for its queue), each in the tab's own stack. Opening one must stay
// in the tab you are in, so the link names that tab's group.

/** The tab's group when the screen is in Discover, Up Next or Profile, else the Podcasts tab's. */
export function tabBase(segments: readonly string[]): string {
  const tab = segments.includes("(discover)")
    ? "(discover)"
    : segments.includes("(upnext)")
      ? "(upnext)"
      : segments.includes("(profile)")
        ? "(profile)"
        : "(library)"
  return `/podcasts/(tabs)/${tab}`
}

export type PodcastHref = {
  pathname: string
  params: { id: string }
}

export function showHref(segments: readonly string[], id: string): PodcastHref {
  return { pathname: `${tabBase(segments)}/show/[id]`, params: { id } }
}

export function episodeHref(
  segments: readonly string[],
  id: string,
): PodcastHref {
  return { pathname: `${tabBase(segments)}/episode/[id]`, params: { id } }
}

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

/** A category's chart. Only the Discover tab has it, so the link always names that tab. */
export function categoryHref(id: string) {
  return {
    pathname: "/podcasts/(tabs)/(discover)/category/[id]",
    params: { id },
  }
}
