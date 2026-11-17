// LOFI-FORK: the podcasts section's Up Next (see FORK.md).
//
// Thin wrappers over the native module's Up Next functions. Where there is no native module
// (Android, the web) the queue is empty and nothing can be added. Not imported by any test,
// because the native module is not there; the rules are in upNext.ts.
import { Podcasts, type UpNextItem } from "./index"
import { type Show, type StoredEpisode } from "./library"
import { queueItem } from "./upNext"

export const upNextAvailable = Podcasts !== null

export async function listUpNext(): Promise<UpNextItem[]> {
  return (await Podcasts?.listUpNext()) ?? []
}

/** Puts an episode at the top ("next") or the bottom ("last") of Up Next. */
export async function queueEpisode(
  episode: StoredEpisode,
  show: Show | null,
  place: "next" | "last",
): Promise<void> {
  await Podcasts?.addToUpNext(queueItem(episode, show), place)
}

/** Moves a queued item to the top or bottom, keeping its saved place. */
export async function requeue(
  item: UpNextItem,
  place: "next" | "last",
): Promise<void> {
  await Podcasts?.addToUpNext(item, place)
}

export async function moveInUpNext(from: number, to: number): Promise<void> {
  await Podcasts?.moveInUpNext(from, to)
}

export async function removeFromUpNext(id: string): Promise<void> {
  await Podcasts?.removeFromUpNext(id)
}

export async function clearUpNext(): Promise<void> {
  await Podcasts?.clearUpNext()
}

/** Takes these episodes out of Up Next (the ones that are not queued are skipped). */
export async function removeManyFromUpNext(
  ids: readonly string[],
): Promise<void> {
  const queued = new Set((await listUpNext()).map((item) => item.id))
  for (const id of ids) if (queued.has(id)) await removeFromUpNext(id)
}
