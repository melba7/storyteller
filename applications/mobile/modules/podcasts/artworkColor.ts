// LOFI-FORK: the podcasts section's show colours (see FORK.md).
//
// A show's artwork colour is measured once, by the native module, and kept in the shows
// table (`artwork_color`). The player asks when an episode starts, and a show page asks when
// it opens without a colour.
import type { Show } from "./library"

export interface ArtworkColorDeps {
  /** The artwork's main colour as "#rrggbb", or null when it has none. */
  measure(url: string): Promise<string | null>
  save(showId: string, color: string): Promise<void>
}

// Shows being measured right now, so two screens asking together measure once.
const pending = new Map<string, Promise<string | null>>()

/**
 * The show's artwork colour: the one it already has, or one measured and saved now. Null
 * when there is no native module, no artwork or no colour. A failure rejects, and the
 * next call tries again.
 */
export async function ensureArtworkColor(
  show: Pick<Show, "id" | "imageUrl" | "artworkColor">,
  deps: ArtworkColorDeps | null,
): Promise<string | null> {
  if (show.artworkColor) return show.artworkColor
  if (!deps || !show.imageUrl) return null
  const running = pending.get(show.id)
  if (running) return running
  const url = show.imageUrl
  const job = (async () => {
    const color = await deps.measure(url)
    if (!color) return null
    await deps.save(show.id, color)
    return color
  })()
  pending.set(show.id, job)
  try {
    return await job
  } finally {
    pending.delete(show.id)
  }
}
