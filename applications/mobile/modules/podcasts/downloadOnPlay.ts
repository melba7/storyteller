// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// Playing an episode that is not downloaded starts its download when "Skip ads" is on, so it
// can be transcribed and its ads found. The decision is shouldDownloadOnPlay in downloads.ts.
// A download started here is a manual one, so the Wi-Fi-only setting applies to it as to a tap
// on the download button. Not imported by any test, because the native module is not there.
import { getAdSkipSettings } from "./adsNative"
import { getShow } from "./db"
import { shouldDownloadOnPlay } from "./downloads"
import { listDownloads, startDownload } from "./downloadsNative"
import type { StoredEpisode } from "./library"

export function downloadOnPlay(episode: StoredEpisode): void {
  run(episode).catch((cause: unknown) => {
    console.warn("Couldn't start the download of the playing episode", cause)
  })
}

async function run(episode: StoredEpisode): Promise<void> {
  const { skipAds } = await getAdSkipSettings()
  if (!skipAds) return
  const downloads = await listDownloads()
  const download = downloads.find((info) => info.episodeId === episode.id)
  if (!shouldDownloadOnPlay(episode, download, skipAds)) return
  const show = await getShow(episode.showId)
  await startDownload(
    episode.id,
    episode.audioUrl,
    episode.audioType,
    false,
    show?.language ?? null,
  )
}
