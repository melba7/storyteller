// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// Playing an episode that is not downloaded, with "Skip ads" on, plays it from its own
// download as the bytes arrive, because ads are found only in the exact file that plays. The
// player does not wait: this only says whether to ask the native player for that (the rules
// that need the network, such as Wi-Fi only, are native). The download it makes is a manual
// one, so it shows in the Downloads list. Not imported by any test, because the native module
// is not there; the rule it uses is shouldDownloadOnPlay.
import { getAdSkipSettings } from "./adsNative"
import { shouldDownloadOnPlay } from "./downloads"
import { listDownloads } from "./downloadsNative"
import type { StoredEpisode } from "./library"

/** True when the episode should play through its own download. Any failure means "no". */
export async function playThroughDownload(
  episode: StoredEpisode,
): Promise<boolean> {
  try {
    const { skipAds } = await getAdSkipSettings()
    if (!skipAds) return false
    const download = (await listDownloads()).find(
      (info) => info.episodeId === episode.id,
    )
    return shouldDownloadOnPlay(episode, download, skipAds)
  } catch (cause) {
    console.warn("Couldn't tell whether to play through the download", cause)
    return false
  }
}
