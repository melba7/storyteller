// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// The pure rules for downloads: what a row shows for each state, the storage label, the
// order of the Downloads list and how a change from Swift updates what the screens know.
// The wrappers over the native module are in downloadsNative.ts, so tests can import this
// file without the native module.
import type { AdSkipSettings, DownloadChange, DownloadInfo } from "./index"
import { isLocalEpisodeId } from "./localFiles"
import { isPreviewId } from "./preview"

/** What the screens know about downloads, by episode id. */
export type DownloadMap = Readonly<Record<string, DownloadInfo>>

/** The map after a change from Swift. A removed download leaves the map. */
export function applyChange(
  map: DownloadMap,
  change: DownloadChange,
): DownloadMap {
  if (change.state === "none") {
    if (!(change.episodeId in map)) return map
    const { [change.episodeId]: _removed, ...rest } = map
    return rest
  }
  return { ...map, [change.episodeId]: change }
}

/** The map for a list read from Swift. */
export function mapFromList(list: readonly DownloadInfo[]): DownloadMap {
  return Object.fromEntries(list.map((info) => [info.episodeId, info]))
}

/** The episodes whose download has finished, in order. */
export function downloadedIds(map: DownloadMap): string[] {
  return Object.values(map)
    .filter((info) => info.state === "downloaded")
    .map((info) => info.episodeId)
    .sort()
}

/**
 * A string that changes only when the set of finished downloads changes. A download's
 * progress, or one that starts or fails, does not change it, so a screen that only needs
 * to know which episodes are on the phone can draw again just then.
 */
export function downloadedIdsKey(map: DownloadMap): string {
  return JSON.stringify(downloadedIds(map))
}

/**
 * Reads the finished downloads' ids as a set, and gives back the very same set until a download
 * finishes or goes. A screen can hold it as a value that changes only then (the set of a map
 * that only moved on in progress is the one it had).
 */
export function finishedIdsReader(): (map: DownloadMap) => ReadonlySet<string> {
  let readMap: DownloadMap | null = null
  let readKey: string | null = null
  let ids: ReadonlySet<string> = new Set()
  return (map) => {
    if (map === readMap) return ids
    readMap = map
    const key = downloadedIdsKey(map)
    if (key !== readKey) {
      readKey = key
      ids = new Set(downloadedIds(map))
    }
    return ids
  }
}

/** How far a download has come, 0 to 1, or null when the size is not known. */
export function downloadFraction(info: DownloadInfo): number | null {
  if (info.state === "downloaded") return 1
  if (info.state !== "downloading") return null
  const { bytes, expected } = info
  if (bytes === undefined || expected === undefined || !(expected > 0)) {
    return null
  }
  return Math.max(0, Math.min(1, bytes / expected))
}

export type DownloadAction = "download" | "cancel" | "delete" | "retry"

export type DownloadLook = {
  /** The button's picture. */
  icon: "download" | "waiting" | "progress" | "done" | "failed"
  /** The ring's fill, 0 to 1; null when the size is not known or there is no ring. */
  fraction: number | null
  /** What the row says about the download; empty when there is none. */
  status: string
  /** What a tap does. */
  action: DownloadAction
  /** For VoiceOver. */
  label: string
}

/** What a download button and the line beside it show for an episode. */
export function downloadLook(
  info: DownloadInfo | undefined,
  title: string,
): DownloadLook {
  if (!info) {
    return {
      icon: "download",
      fraction: null,
      status: "",
      action: "download",
      label: `Download ${title}`,
    }
  }
  switch (info.state) {
    case "queued":
      return {
        icon: "waiting",
        fraction: null,
        status: "Waiting to download",
        action: "cancel",
        label: `Waiting to download ${title}. Cancel the download`,
      }
    case "downloading": {
      const fraction = downloadFraction(info)
      const percent = fraction === null ? null : Math.floor(fraction * 100)
      return {
        icon: "progress",
        fraction,
        status: percent === null ? "Downloading" : `Downloading ${percent}%`,
        action: "cancel",
        label:
          percent === null
            ? `Downloading ${title}. Cancel the download`
            : `Downloading ${title}, ${percent} percent. Cancel the download`,
      }
    }
    case "downloaded":
      return {
        icon: "done",
        fraction: 1,
        status:
          info.bytes === undefined ? "Downloaded" : formatStorage(info.bytes),
        action: "delete",
        label: `Downloaded ${title}. Delete the download`,
      }
    case "failed":
      return {
        icon: "failed",
        fraction: null,
        status: info.reason ?? "The download failed",
        action: "retry",
        label: `Download failed for ${title}. Try again`,
      }
  }
}

/** The menu item's title for what a tap on the download button would do. */
export function downloadMenuTitle(action: DownloadAction): string {
  switch (action) {
    case "download":
      return "Download"
    case "retry":
      return "Download again"
    case "cancel":
      return "Cancel download"
    case "delete":
      return "Remove download"
  }
}

const UNITS = ["bytes", "KB", "MB", "GB", "TB"]

/** A size the way the phone's settings write it: "340 MB", "1.2 GB" (thousands, not 1024s). */
export function formatStorage(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 MB"
  let value = bytes
  let unit = 0
  while (value >= 1000 && unit < UNITS.length - 1) {
    value /= 1000
    unit += 1
  }
  if (unit === 0) return `${Math.round(value)} bytes`
  const text = value >= 100 ? value.toFixed(0) : value.toFixed(1)
  return `${text.replace(/\.0$/, "")} ${UNITS[unit]}`
}

/** Bytes taken by the finished downloads in the map. */
export function storageOf(map: DownloadMap): number {
  return Object.values(map).reduce(
    (total, info) =>
      info.state === "downloaded" ? total + (info.bytes ?? 0) : total,
    0,
  )
}

/** When a download last changed: the finish time for a finished one. */
function stamp(info: DownloadInfo): number {
  return info.date ?? info.updatedAt
}

/**
 * The Downloads list: newest first, with ones still moving among them by when they were
 * asked for. Ties keep the episode id's order so the list does not jump about.
 */
export function sortDownloads(list: readonly DownloadInfo[]): DownloadInfo[] {
  return [...list].sort(
    (a, b) => stamp(b) - stamp(a) || a.episodeId.localeCompare(b.episodeId),
  )
}

/** How many downloads Library's "Downloaded" row counts: every one but a failed one. */
export function downloadedCount(map: DownloadMap): number {
  return Object.values(map).filter((info) => info.state !== "failed").length
}

/** "3 episodes, 1.2 GB" for the Profile row; "No downloads" when there are none. */
export function downloadsSummary(map: DownloadMap): string {
  const count = Object.keys(map).length
  if (count === 0) return "No downloads"
  const noun = count === 1 ? "episode" : "episodes"
  return `${count} ${noun}, ${formatStorage(storageOf(map))}`
}

/** Whether ads are skipped for a show: its own choice where it has one, else the main switch. */
export function skipAdsFor(
  show: boolean | null | undefined,
  main: boolean,
): boolean {
  return show ?? main
}

/**
 * Whether any sort of ad is skipped for a show. The show's own choice replaces the main switch
 * for sponsor ads and for the hosts' plugs only; promos and credits follow the main switches.
 * Ads are skipped only in a file on the phone, so this is what asks for the download.
 */
export function skippingAnyFor(
  show: { skipAds: boolean | null; skipPlugs: boolean | null } | undefined,
  main: AdSkipSettings,
): boolean {
  return (
    skipAdsFor(show?.skipAds, main.skipAds) ||
    skipAdsFor(show?.skipPlugs, main.skipOwnPlugs) ||
    main.skipPromos ||
    main.skipCredits
  )
}

/**
 * Whether playing this episode should start its download: "Skip ads" is on, the episode is a
 * feed episode (not an added file or a preview) and it is not downloaded, queued or on its way.
 * A failed download is tried again, and so is a new episode's automatic one that has not
 * received a byte (it waits for Wi-Fi; the player cancels it and plays through its own).
 */
export function shouldDownloadOnPlay(
  episode: { id: string },
  download: DownloadInfo | undefined,
  skipAds: boolean,
): boolean {
  if (!skipAds) return false
  if (isLocalEpisodeId(episode.id) || isPreviewId(episode.id)) return false
  if (download === undefined || download.state === "failed") return true
  if (download.automatic !== true) return false
  return (
    download.state === "queued" ||
    (download.state === "downloading" && (download.bytes ?? 0) === 0)
  )
}
