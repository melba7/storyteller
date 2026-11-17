// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Ellipsis } from "lucide-react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import {
  archiveEpisodes,
  unarchiveEpisodes,
} from "@/modules/podcasts/dbSettings"
import { downloadLook, downloadMenuTitle } from "@/modules/podcasts/downloads"
import { type DownloadInfo, Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { markPlayed } from "@/modules/podcasts/playerInstance"
import { isPreviewId } from "@/modules/podcasts/preview"
import { isQueued } from "@/modules/podcasts/upNext"

import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { localFileActions } from "./localFileActions"
import { pressDownload, useDownload } from "./useDownloads"
import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

/**
 * The menu on an episode row: Download (or Cancel or Remove download), Play next and Play
 * last (which also move an episode that is already queued), for a queued one Remove from Up
 * Next, Star, Mark played and Archive (for episodes in the library). Nothing where there is
 * no native player.
 */
export function archiveAction(episode: StoredEpisode) {
  const archived = episode.archived
  return {
    id: "archive",
    title: archived ? "Unarchive" : "Archive",
    onPress: () => {
      const done = archived
        ? unarchiveEpisodes([episode.id])
        : archiveEpisodes([episode.id])
      done.catch((cause: unknown) =>
        console.warn("Couldn't change the episode's archive", cause),
      )
    },
  }
}

/** Star or Unstar, for an episode in the library. */
export function starAction(episode: StoredEpisode) {
  const starred = episode.starredAt !== null
  return {
    id: "star",
    title: starred ? "Unstar" : "Star",
    onPress: () => {
      setStarred([episode.id], !starred).catch((cause: unknown) =>
        console.warn("Couldn't change the episode's star", cause),
      )
    },
  }
}

/** Mark played or Mark unplayed, for an episode in the library. */
export function playedAction(episode: StoredEpisode) {
  return {
    id: "played",
    title: episode.played ? "Mark unplayed" : "Mark played",
    onPress: () => {
      markPlayed([episode.id], !episode.played).catch((cause: unknown) =>
        console.warn("Couldn't change the episode's played mark", cause),
      )
    },
  }
}

/**
 * Download, Cancel download, Download again or Remove download, for what the episode's
 * download is doing. Null where there is nothing to do: a preview episode, an added file
 * (its download is its only copy, so it is never removed from here) or no native module.
 */
export function downloadAction(
  episode: StoredEpisode,
  info: DownloadInfo | undefined,
) {
  if (
    Podcasts === null ||
    isPreviewId(episode.id) ||
    isLocalEpisodeId(episode.id)
  ) {
    return null
  }
  const look = downloadLook(info, episode.title)
  return {
    id: "download",
    title: downloadMenuTitle(look.action),
    ...(look.action === "delete" ? { attributes: { destructive: true } } : {}),
    onPress: () => pressDownload(look.action, episode),
  }
}

export function EpisodeMenu({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const queue = useUpNext()
  const download = downloadAction(episode, useDownload(episode.id))
  if (Podcasts === null) return null
  const queued = isQueued(queue, episode.id)
  return (
    <Menu
      actions={[
        ...(download ? [download] : []),
        {
          id: "next",
          title: "Play next",
          onPress: () => addToUpNext(episode, show, "next"),
        },
        {
          id: "last",
          title: "Play last",
          onPress: () => addToUpNext(episode, show, "last"),
        },
        ...(queued
          ? [
              {
                id: "remove",
                title: "Remove from Up Next",
                attributes: { destructive: true },
                onPress: () => removeQueued(episode.id),
              },
            ]
          : []),
        {
          id: "playlist",
          title: "Add to playlist",
          onPress: () => void chooseAndAddToPlaylist(episode, show),
        },
        ...(isPreviewId(episode.id)
          ? []
          : [
              starAction(episode),
              playedAction(episode),
              archiveAction(episode),
            ]),
        ...(isLocalEpisodeId(episode.id) ? localFileActions(episode) : []),
      ]}
    >
      <Button
        variant="ghost"
        size="icon"
        className="size-11"
        accessibilityLabel={`More for ${episode.title}`}
      >
        <Icon as={Ellipsis} size={20} className="text-muted-foreground" />
      </Button>
    </Menu>
  )
}
