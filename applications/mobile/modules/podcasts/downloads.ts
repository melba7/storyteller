// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// The pure rules for downloads: what a row shows for each state, the storage label, the
// order of the Downloads list and how a change from Swift updates what the screens know.
// The wrappers over the native module are in downloadsNative.ts, so tests can import this
// file without the native module.
import type { DownloadChange, DownloadInfo } from "./index"

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

/** "3 episodes, 1.2 GB" for the Profile row; "No downloads" when there are none. */
export function downloadsSummary(map: DownloadMap): string {
  const count = Object.keys(map).length
  if (count === 0) return "No downloads"
  const noun = count === 1 ? "episode" : "episodes"
  return `${count} ${noun}, ${formatStorage(storageOf(map))}`
}
