// LOFI-FORK: the podcasts section's new-episode notifications (see FORK.md).
//
// After a refresh (in the app or the background task), tells the listener about the episodes it
// added, when "Notify me about new episodes" is on. Not imported by any test, because the
// database and the native module are not there; the words are in newEpisodeNotice.ts.
import type { NewEpisode } from "./automatic"
import { getShow, listEpisodesByIds } from "./db"
import { noticesForNewEpisodes } from "./newEpisodeNotice"
import { loadNotifyNew, postNotification } from "./notificationsNative"

/** Posts one notification per show that gained episodes. A failure is logged, not thrown. */
export async function notifyAboutNewEpisodes(
  added: readonly NewEpisode[],
): Promise<void> {
  if (added.length === 0 || !(await loadNotifyNew())) return
  try {
    const shows = new Map<string, string>()
    for (const showId of new Set(added.map((episode) => episode.showId))) {
      const show = await getShow(showId)
      if (show) shows.set(showId, show.title)
    }
    const titles = new Map(
      (await listEpisodesByIds(added.map((episode) => episode.id))).map(
        (episode) => [episode.id, episode.title] as const,
      ),
    )
    for (const notice of noticesForNewEpisodes(added, shows, titles)) {
      await postNotification(notice.id, notice.title, notice.body)
    }
  } catch (cause) {
    console.warn("Couldn't post the new-episode notifications", cause)
  }
}
