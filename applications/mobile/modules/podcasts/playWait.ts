// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// With "Skip ads" on, playing an episode that is not downloaded waits for its download, because
// ads are found only in the exact file that plays. These are the rules for how long to wait.
import { downloadFraction } from "./downloads"
import type { DownloadInfo } from "./index"

/** The longest the listener waits for a download before the episode streams. */
export const WAIT_LIMIT_MS = 60_000
/** With Wi-Fi only on, a download with nothing received after this long is waiting for Wi-Fi. */
export const WIFI_GRACE_MS = 8_000

export type WaitDecision = "wait" | "play" | "stream"

/**
 * Keep waiting, play the downloaded file, or stream now. "Stream now" wins over everything. A
 * missing download means it was cancelled or removed. A download that has received nothing
 * while Wi-Fi only is on is taken to be waiting for Wi-Fi.
 */
export function waitDecision(input: {
  download: DownloadInfo | undefined
  elapsedMs: number
  wifiOnly: boolean
  streamAsked: boolean
}): WaitDecision {
  const { download, elapsedMs, wifiOnly, streamAsked } = input
  if (streamAsked) return "stream"
  if (download === undefined || download.state === "failed") return "stream"
  if (download.state === "downloaded") return "play"
  if (elapsedMs >= WAIT_LIMIT_MS) return "stream"
  const received = (download.bytes ?? 0) > 0
  if (wifiOnly && !received && elapsedMs >= WIFI_GRACE_MS) return "stream"
  return "wait"
}

/** Whole percent downloaded, or null when the size is not known. */
export function waitPercent(download: DownloadInfo | undefined): number | null {
  if (!download) return null
  const fraction = downloadFraction(download)
  return fraction === null ? null : Math.floor(fraction * 100)
}

/** The percent VoiceOver hears: it changes only every ten percent. */
export function announcedPercent(percent: number | null): number | null {
  return percent === null ? null : Math.floor(percent / 10) * 10
}
