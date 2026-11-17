// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Ellipsis } from "lucide-react-native"
import { type ReactElement } from "react"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import {
  archiveEpisodes,
  unarchiveEpisodes,
} from "@/modules/podcasts/dbSettings"
import { downloadLook } from "@/modules/podcasts/downloads"
import {
  type MenuItem,
  downloadIcon,
  menuLayout,
} from "@/modules/podcasts/episodeMenuModel"
import { type DownloadInfo, Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { markPlayed, player } from "@/modules/podcasts/playerInstance"
import { requestPlayerPage } from "@/modules/podcasts/playerPageRequest"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeHref, showHref } from "@/modules/podcasts/routes"
import { episodeShare } from "@/modules/podcasts/share"
import { isQueued } from "@/modules/podcasts/upNext"

import { EpisodeMenuSurface } from "./EpisodeMenuSurface"
import { shareContent } from "./ShareButton"
import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { localFileActions } from "./localFileActions"
import { pressDownload, useDownload } from "./useDownloads"
import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

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

/** Save or Unsave (the data is still `starredAt`), for an episode in the library. */
export function starAction(episode: StoredEpisode) {
  const starred = episode.starredAt !== null
  return {
    id: "star",
    title: starred ? "Unsave" : "Save",
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
    title: episode.played ? "Mark as Unplayed" : "Mark as Played",
    onPress: () => {
      markPlayed([episode.id], !episode.played).catch((cause: unknown) =>
        console.warn("Couldn't change the episode's played mark", cause),
      )
    },
  }
}

/** Apple's capitals for the download entry. */
const DOWNLOAD_TITLES = {
  download: "Download",
  retry: "Download Again",
  cancel: "Cancel Download",
  delete: "Remove Download",
} as const

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
    title: DOWNLOAD_TITLES[look.action],
    icon: downloadIcon(look.action),
    destructive: look.action === "delete",
    onPress: () => pressDownload(look.action, episode),
  }
}

/** The "..." the menu opens from, in the row's grey. */
function EllipsisButton({ episode }: { episode: StoredEpisode }) {
  return (
    <Button
      variant="ghost"
      size="icon"
      className="size-11"
      accessibilityLabel={`More for ${episode.title}`}
    >
      <Icon as={Ellipsis} size={20} className="text-muted-foreground" />
    </Button>
  )
}

/**
 * The menu on an episode: Apple's, with Save and Share across the top, then Play Next, Play
 * Last (for a queued one also Remove from Up Next) and Mark as Played; Go to Episode, Go to
 * Show, View Transcript and Add to Playlist; Archive (and an added file's Rename and Delete);
 * and Download, Cancel Download or Remove Download last. Nothing where there is no native
 * player. `children` replaces the grey "..." as what opens it, and `tint` colours it (the Home
 * card's colour).
 */
export function EpisodeMenu({
  episode,
  show,
  children,
  tint,
}: {
  episode: StoredEpisode
  show: Show | null
  children?: ReactElement
  tint?: string
}) {
  const router = useRouter()
  const segments = useSegments()
  const queue = useUpNext()
  const download = downloadAction(episode, useDownload(episode.id))
  if (Podcasts === null) return null
  const preview = isPreviewId(episode.id)
  const local = isLocalEpisodeId(episode.id) ? localFileActions(episode) : []
  const extra: MenuItem[] = local.map((entry) => ({
    id: entry.id,
    title: entry.title,
    icon: entry.id === "rename" ? "pencil" : "trash",
    ...(entry.id === "delete-file" ? { destructive: true } : {}),
  }))
  const layout = menuLayout({
    starred: episode.starredAt !== null,
    played: episode.played,
    archived: episode.archived,
    queued: isQueued(queue, episode.id),
    preview,
    download: download
      ? {
          title: download.title,
          destructive: download.destructive,
          icon: download.icon,
        }
      : null,
    extra,
  })
  const handlers: Record<string, () => void> = {
    save: starAction(episode).onPress,
    share: () => void shareContent(() => episodeShare(episode, show)),
    next: () => addToUpNext(episode, show, "next"),
    last: () => addToUpNext(episode, show, "last"),
    "remove-queued": () => removeQueued(episode.id),
    played: playedAction(episode).onPress,
    episode: () => router.push(episodeHref(segments, episode.id)),
    show: () => router.push(showHref(segments, episode.showId)),
    transcript: () => {
      // The player has the transcript of the episode it has loaded; any other opens its page.
      if (player.getView().episode?.id === episode.id) {
        requestPlayerPage("transcript")
        router.push("/podcasts/player")
      } else {
        router.push(episodeHref(segments, episode.id))
      }
    },
    playlist: () => void chooseAndAddToPlaylist(episode, show),
    archive: archiveAction(episode).onPress,
    ...(download ? { download: download.onPress } : {}),
    ...Object.fromEntries(local.map((entry) => [entry.id, entry.onPress])),
  }
  return (
    <EpisodeMenuSurface
      layout={layout}
      tint={tint}
      onSelect={(id) => handlers[id]?.()}
    >
      {children ?? <EllipsisButton episode={episode} />}
    </EpisodeMenuSurface>
  )
}
