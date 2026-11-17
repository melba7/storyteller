// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// Pure words for the playlist screens.
import { formatDuration } from "./library"
import { type PlaylistEntry } from "./manualPlaylist"

/** "1 episode", "3 episodes". */
export function episodeCount(count: number): string {
  return count === 1 ? "1 episode" : `${count} episodes`
}

/** What a row of a hand-filled playlist says under its title: the show and the length. */
export function entryDetails(entry: PlaylistEntry): string {
  const { episode, show } = entry
  return [show?.title ?? "", formatDuration(episode.durationSeconds)]
    .filter((part) => part !== "")
    .join(" · ")
}

/** For VoiceOver on a playlist row. */
export function entryLabel(
  entry: PlaylistEntry,
  index: number,
  count: number,
): string {
  return [
    entry.episode.title,
    entryDetails(entry),
    `place ${index + 1} of ${count}`,
  ]
    .filter((part) => part !== "")
    .join(", ")
}
