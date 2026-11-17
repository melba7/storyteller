// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Ellipsis } from "lucide-react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import {
  archiveEpisodes,
  unarchiveEpisodes,
} from "@/modules/podcasts/dbSettings"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { isQueued } from "@/modules/podcasts/upNext"

import { localFileActions } from "./localFileActions"
import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

/**
 * The menu on an episode row: Play next and Play last (which also move an episode that is
 * already queued), for a queued one Remove from Up Next, and Archive or Unarchive. Nothing
 * where there is no native player.
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

export function EpisodeMenu({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const queue = useUpNext()
  if (Podcasts === null) return null
  const queued = isQueued(queue, episode.id)
  return (
    <Menu
      actions={[
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
        archiveAction(episode),
        ...(isLocalEpisodeId(episode.id) ? localFileActions(episode) : []),
      ]}
    >
      <Button
        variant="ghost"
        size="icon"
        accessibilityLabel={`More for ${episode.title}`}
      >
        <Icon as={Ellipsis} size={20} className="text-muted-foreground" />
      </Button>
    </Menu>
  )
}
