// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState, useSyncExternalStore } from "react"
import { Alert } from "react-native"

import { getShow } from "@/modules/podcasts/db"
import {
  type DownloadAction,
  type DownloadMap,
  applyChange,
  finishedIdsReader,
  mapFromList,
  storageOf,
} from "@/modules/podcasts/downloads"
import {
  cancelDownload,
  deleteDownload,
  listDownloads,
  startDownload,
  storageUsed,
} from "@/modules/podcasts/downloadsNative"
import { type DownloadInfo, Podcasts } from "@/modules/podcasts/index"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { readableError } from "@/modules/podcasts/nativeError"

// What the screens know about downloads: read once from Swift, then kept fresh by its
// onDownloadChange event. One copy is shared by every screen.
let current: DownloadMap = {}
let started = false
const listeners = new Set<() => void>()

function publish(next: DownloadMap) {
  current = next
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost.
  Podcasts.addListener("onDownloadChange", (change) =>
    publish(applyChange(current, change)),
  )
  listDownloads().then(
    (list) => publish({ ...mapFromList(list), ...current }),
    (cause: unknown) => {
      started = false
      console.warn("Couldn't read the downloads", cause)
    },
  )
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Every download, by episode id. */
export function useDownloadMap(): DownloadMap {
  return useSyncExternalStore(subscribe, () => current)
}

// The ids of the finished downloads as a set. It keeps its identity through every progress step.
const finishedIds = finishedIdsReader()

/**
 * The episodes whose download has finished. Draws again only when a download finishes or
 * goes, not at every progress step of every download (`useDownloadMap` does that).
 */
export function useDownloadedIds(): ReadonlySet<string> {
  return useSyncExternalStore(subscribe, () => finishedIds(current))
}

/** One episode's download, or undefined when it has none. Draws again only when it changes. */
export function useDownload(episodeId: string): DownloadInfo | undefined {
  return useSyncExternalStore(subscribe, () => current[episodeId])
}

/**
 * Bytes taken by finished downloads, asked of Swift again whenever the set of finished
 * downloads changes.
 */
export function useStorageUsed(): number {
  const map = useDownloadMap()
  const [bytes, setBytes] = useState(0)
  const finished = Object.values(map)
    .filter((info) => info.state === "downloaded")
    .map((info) => info.episodeId)
    .sort()
    .join(",")
  useEffect(() => {
    let live = true
    storageUsed().then(
      (value) => {
        if (live) setBytes(value)
      },
      // Swift can't be asked: what the screens know is close enough.
      () => {
        if (live) setBytes(storageOf(map))
      },
    )
    return () => {
      live = false
    }
    // Only a change in which downloads are finished can change the number.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [finished])
  return bytes
}

function tell(title: string, cause: unknown) {
  Alert.alert(title, readableError(cause))
}

/** What a tap on a download button does. Deleting asks first. */
export function pressDownload(
  action: DownloadAction,
  episode: Pick<
    StoredEpisode,
    "id" | "showId" | "title" | "audioUrl" | "audioType"
  >,
) {
  switch (action) {
    case "download":
    case "retry":
      // The show's language picks the transcript's language; without one, the phone's.
      getShow(episode.showId)
        .then(
          (show) =>
            startDownload(
              episode.id,
              episode.audioUrl,
              episode.audioType,
              false,
              show?.language ?? null,
            ),
          () => startDownload(episode.id, episode.audioUrl, episode.audioType),
        )
        .catch((cause: unknown) => tell("Couldn't download", cause))
      return
    case "cancel":
      cancelDownload(episode.id).catch((cause: unknown) =>
        tell("Couldn't cancel", cause),
      )
      return
    case "delete":
      confirmDelete(episode)
  }
}

export function confirmDelete(episode: Pick<StoredEpisode, "id" | "title">) {
  // An added file's download is its only copy; "Delete file" in its menu is the way.
  if (isLocalEpisodeId(episode.id)) return
  Alert.alert(
    "Delete this download?",
    `${episode.title} is removed from your phone. You can download it again later.`,
    [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: () => {
          deleteDownload(episode.id).catch((cause: unknown) =>
            tell("Couldn't delete", cause),
          )
        },
      },
    ],
  )
}
