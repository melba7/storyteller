// LOFI-FORK: the podcasts section's listening history (see FORK.md).
//
// Pure rules for the history screen: its day headings.
import { formatEpisodeDate } from "./library"

function startOfDay(time: number): number {
  const date = new Date(time)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

/** "Today", "Yesterday" or "10 Nov 2026" for the day of `time`, in the phone's time zone. */
export function dayTitle(time: number, now: number): string {
  const today = startOfDay(now)
  const day = startOfDay(time)
  if (day === today) return "Today"
  if (day === startOfDay(today - 1)) return "Yesterday"
  return formatEpisodeDate(time)
}

/** The episodes (newest listen first) under one heading per day. */
export function groupByDay<T extends { lastPlayedAt: number | null }>(
  episodes: readonly T[],
  now: number,
): { title: string; episodes: T[] }[] {
  const groups: { title: string; episodes: T[] }[] = []
  for (const episode of episodes) {
    if (episode.lastPlayedAt === null) continue
    const title = dayTitle(episode.lastPlayedAt, now)
    const last = groups.at(-1)
    if (last && last.title === title) last.episodes.push(episode)
    else groups.push({ title, episodes: [episode] })
  }
  return groups
}
