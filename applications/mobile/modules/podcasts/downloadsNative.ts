// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// Thin wrappers over the native module's download functions. Where there is no native
// module (Android, the web) nothing is downloaded and the screens hide the buttons. Not
// imported by any test, because the native module is not there; the rules are in
// downloads.ts.
import { type DownloadInfo, Podcasts } from "./index"

/** Whether this build can download (false on Android and the web). */
export const downloadsAvailable = Podcasts !== null

export async function listDownloads(): Promise<DownloadInfo[]> {
  return (await Podcasts?.listDownloads()) ?? []
}

export async function startDownload(
  episodeId: string,
  url: string,
  type: string,
  automatic = false,
  language: string | null = null,
): Promise<void> {
  await Podcasts?.download(episodeId, url, type, automatic, language)
}

export async function cancelDownload(episodeId: string): Promise<void> {
  await Podcasts?.cancelDownload(episodeId)
}

export async function deleteDownload(episodeId: string): Promise<void> {
  await Podcasts?.deleteDownload(episodeId)
}

/** Removes the downloads of these episodes (the ones that have none are skipped). */
export async function deleteDownloads(
  episodeIds: readonly string[],
): Promise<void> {
  const have = new Set((await listDownloads()).map((info) => info.episodeId))
  for (const id of episodeIds) if (have.has(id)) await deleteDownload(id)
}

export async function storageUsed(): Promise<number> {
  return (await Podcasts?.storageUsed()) ?? 0
}

export async function getWifiOnly(): Promise<boolean> {
  return (await Podcasts?.getWifiOnly()) ?? false
}

export async function setWifiOnly(on: boolean): Promise<void> {
  await Podcasts?.setWifiOnly(on)
}
