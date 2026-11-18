// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// What the last read of the Apple Podcasts file found, kept in memory for the screen that shows
// it (useAppleSyncStatus). appleSync.ts writes it. The wording is here, apart from React.
import { useSyncExternalStore } from "react"

import type { LinkedFileRead } from "@/modules/lofi-score"

export type AppleSyncStatus = {
  reading: boolean
  /** Milliseconds since 1970 of the last read that found the file, or null. */
  readAt: number | null
  /** Shows the file lists, from that read. */
  shows: number | null
  /** Shows that read subscribed to. */
  followed: number
  /** Plain words for why the last read found nothing, or null. */
  problem: string | null
}

const EMPTY: AppleSyncStatus = {
  reading: false,
  readAt: null,
  shows: null,
  followed: 0,
  problem: null,
}

let current = EMPTY
const listeners = new Set<() => void>()

export function getAppleSyncStatus(): AppleSyncStatus {
  return current
}

export function setAppleSyncStatus(patch: Partial<AppleSyncStatus>) {
  current = { ...current, ...patch }
  for (const listener of [...listeners]) listener()
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** The last read of the Apple Podcasts file, kept fresh. */
export function useAppleSyncStatus(): AppleSyncStatus {
  return useSyncExternalStore(subscribe, getAppleSyncStatus)
}

/** Why a read found nothing, in plain words; null when it found the file. */
export function problemFor(read: LinkedFileRead): string | null {
  switch (read.status) {
    case "found":
      return null
    case "notLinked":
      return "Folder not linked"
    case "folderGone":
      return "The linked folder can't be opened"
    case "missing":
      return "No Apple Podcasts file in the folder yet"
    case "notDownloaded":
      return "File not downloaded yet"
    case "unreadable":
      return read.message
  }
}

const RETRY_DELAYS = [20_000, 30_000, 60_000]

/** Milliseconds to wait before asking again for a file iCloud is downloading; null to stop. */
export function retryDelay(attempt: number): number | null {
  return RETRY_DELAYS[attempt] ?? null
}

function ago(now: number, then: number): string {
  const minutes = Math.floor((now - then) / 60_000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} h ago`
  return `${Math.floor(hours / 24)} d ago`
}

/** One line for the status, such as "64 shows found, 3 followed now, read 5 min ago". */
export function describeStatus(status: AppleSyncStatus, now: number): string {
  if (status.reading) return "Reading…"
  if (status.problem !== null) {
    return status.readAt === null
      ? status.problem
      : `${status.problem} (last read ${ago(now, status.readAt)})`
  }
  if (status.readAt === null || status.shows === null) return "Not read yet"
  const shows = `${status.shows} ${status.shows === 1 ? "show" : "shows"} found`
  const followed =
    status.followed > 0 ? `, ${status.followed} followed now` : ""
  return `${shows}${followed}, read ${ago(now, status.readAt)}`
}
