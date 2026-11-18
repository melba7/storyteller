// LOFI-FORK: the podcasts section's player (see FORK.md).
//
// A screen that opens the player can ask for one of its pages (the episode menu's "View
// Transcript" asks for "transcript"). The player takes the request once when it shows.

export type RequestedPage = "transcript" | "chapters" | "notes"

let pending: RequestedPage | null = null

export function requestPlayerPage(page: RequestedPage) {
  pending = page
}

/** The page asked for, once; null when nothing was asked since the last call. */
export function takePlayerPageRequest(): RequestedPage | null {
  const page = pending
  pending = null
  return page
}
