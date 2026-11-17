// LOFI-FORK: the podcasts section's multi-select (see FORK.md).
//
// Pure rules for picking several episodes in a list and what each bulk action applies to.
// The actions themselves (database, downloads, Up Next) are in the screens' bulk.ts.

export type BulkAction =
  | "download"
  | "played"
  | "unplayed"
  | "archive"
  | "unarchive"
  | "star"
  | "unstar"
  | "queueNext"
  | "queueLast"

/** The selected ids after tapping one: added, or removed when it was selected. */
export function toggleSelected(
  selected: readonly string[],
  id: string,
): string[] {
  return selected.includes(id)
    ? selected.filter((other) => other !== id)
    : [...selected, id]
}

/** Every id selected, or none when every id already was. */
export function selectAll(
  selected: readonly string[],
  all: readonly string[],
): string[] {
  return all.every((id) => selected.includes(id)) && all.length > 0
    ? []
    : [...all]
}

/** The title of the selection bar. */
export function selectionLabel(count: number): string {
  return count === 0 ? "Select episodes" : `${count} selected`
}

type Pickable = {
  id: string
  played: boolean
  archived: boolean
  starred: boolean
}

/**
 * The ids a bulk action applies to, in the order given: marking played skips what is
 * played, archiving skips what is archived, and so on. Downloading skips archived and
 * played episodes and the ones already on the phone or on their way (`downloaded`).
 */
export function bulkTargets(
  action: BulkAction,
  episodes: readonly Pickable[],
  downloaded: ReadonlySet<string>,
): string[] {
  const wanted = (episode: Pickable): boolean => {
    switch (action) {
      case "played":
        return !episode.played
      case "unplayed":
        return episode.played
      case "archive":
        return !episode.archived
      case "unarchive":
        return episode.archived
      case "star":
        return !episode.starred
      case "unstar":
        return episode.starred
      case "download":
        return (
          !episode.archived && !episode.played && !downloaded.has(episode.id)
        )
      case "queueNext":
      case "queueLast":
        return true
    }
  }
  return episodes.filter(wanted).map((episode) => episode.id)
}

/**
 * The order to hand episodes to Up Next so they end up in the order shown: to the bottom
 * one by one, to the top from the last up (each goes first).
 */
export function upNextOrder(
  ids: readonly string[],
  place: "next" | "last",
): { id: string; place: "next" | "last" }[] {
  const ordered = place === "next" ? [...ids].reverse() : [...ids]
  return ordered.map((id) => ({ id, place }))
}
