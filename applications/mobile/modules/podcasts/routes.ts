// LOFI-FORK: the podcasts section's routes (see FORK.md).
//
// A show's page and an episode's page exist in both tabs (Podcasts and Discover), each in
// the tab's own stack. Opening one must stay in the tab you are in, so the link names
// that tab's group.

/** "/podcasts/(tabs)/(discover)" when the screen is in the Discover tab, else the Podcasts tab's. */
export function tabBase(segments: readonly string[]): string {
  const tab = segments.includes("(discover)") ? "(discover)" : "(library)"
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
