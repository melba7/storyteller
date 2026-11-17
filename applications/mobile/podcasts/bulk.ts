// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import { getShow } from "@/modules/podcasts/db"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import {
  archiveEpisodes,
  unarchiveEpisodes,
} from "@/modules/podcasts/dbSettings"
import { startDownload } from "@/modules/podcasts/downloadsNative"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { markPlayed } from "@/modules/podcasts/playerInstance"
import {
  type BulkAction,
  bulkTargets,
  upNextOrder,
} from "@/modules/podcasts/selection"
import { queueEpisode } from "@/modules/podcasts/upNextNative"

/**
 * Does a bulk action on the picked episodes that it applies to (see bulkTargets). Tells the
 * listener when something fails; the ones before it stay done.
 */
export async function runBulk(
  action: BulkAction,
  picked: readonly StoredEpisode[],
  shows: ReadonlyMap<string, Show>,
  onPhone: ReadonlySet<string>,
): Promise<void> {
  const ids = bulkTargets(
    action,
    picked.map((episode) => ({
      id: episode.id,
      played: episode.played,
      archived: episode.archived,
      starred: episode.starredAt !== null,
    })),
    onPhone,
  )
  const byId = new Map(picked.map((episode) => [episode.id, episode]))
  try {
    switch (action) {
      case "played":
        return await markPlayed(ids, true)
      case "unplayed":
        return await markPlayed(ids, false)
      case "star":
        return await setStarred(ids, true)
      case "unstar":
        return await setStarred(ids, false)
      case "archive":
        return await archiveEpisodes(ids)
      case "unarchive":
        return await unarchiveEpisodes(ids)
      case "download":
        for (const id of ids) {
          const episode = byId.get(id)
          if (!episode) continue
          const show =
            shows.get(episode.showId) ?? (await getShow(episode.showId))
          await startDownload(
            episode.id,
            episode.audioUrl,
            episode.audioType,
            false,
            show?.language ?? null,
          )
        }
        return
      case "queueNext":
      case "queueLast":
        for (const step of upNextOrder(
          ids,
          action === "queueNext" ? "next" : "last",
        )) {
          const episode = byId.get(step.id)
          if (episode) {
            await queueEpisode(
              episode,
              shows.get(episode.showId) ?? null,
              step.place,
            )
          }
        }
        return
    }
  } catch (cause) {
    Alert.alert("Couldn't finish that", readableError(cause))
  }
}
