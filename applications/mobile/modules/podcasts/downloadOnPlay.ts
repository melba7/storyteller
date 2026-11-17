// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// Playing an episode that is not downloaded, with "Skip ads" on, downloads it first and plays
// the file, because ads are found only in the exact file that plays. The player waits for the
// download (playback.ts awaits this); the wait ends when the file is there, the download fails
// or waits for Wi-Fi, a minute passes or the listener taps "Stream now" (the rules are
// waitDecision in playWait.ts), and then the episode plays. A download started here is a
// manual one, so the Wi-Fi-only setting applies as to a tap on the download button. Not
// imported by any test, because the native module is not there.
import { getAdSkipSettings } from "./adsNative"
import { getShow } from "./db"
import { shouldDownloadOnPlay } from "./downloads"
import { getWifiOnly, listDownloads, startDownload } from "./downloadsNative"
import type { StoredEpisode } from "./library"
import { waitDecision } from "./playWait"
import { beginWait, endWait, streamAsked } from "./playWaitStore"

const POLL_MS = 1000
let waits = 0

const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms))

/**
 * Resolves when the episode may load: at once when nothing is to be downloaded, otherwise
 * when the wait ends. Any failure means "play now" (streaming), so playing never breaks.
 * `abandoned` says a newer play took over, which ends the wait quietly.
 */
export async function downloadOnPlay(
  episode: StoredEpisode,
  abandoned: () => boolean,
): Promise<void> {
  const id = ++waits
  try {
    const { skipAds } = await getAdSkipSettings()
    if (!skipAds) return
    const first = (await listDownloads()).find(
      (info) => info.episodeId === episode.id,
    )
    if (!shouldDownloadOnPlay(episode, first, skipAds)) return
    const show = await getShow(episode.showId)
    const wifiOnly = await getWifiOnly()
    const began = Date.now()
    beginWait({ id, episodeId: episode.id, title: episode.title })
    await startDownload(
      episode.id,
      episode.audioUrl,
      episode.audioType,
      false,
      show?.language ?? null,
    )
    for (;;) {
      if (abandoned()) return
      const download = (await listDownloads()).find(
        (info) => info.episodeId === episode.id,
      )
      const decision = waitDecision({
        download,
        elapsedMs: Date.now() - began,
        wifiOnly,
        streamAsked: streamAsked(id),
      })
      if (decision !== "wait") return
      await sleep(POLL_MS)
    }
  } catch (cause) {
    console.warn("Couldn't download the playing episode first", cause)
  } finally {
    endWait(id)
  }
}
