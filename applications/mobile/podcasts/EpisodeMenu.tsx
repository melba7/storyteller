// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Ellipsis } from "lucide-react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isQueued } from "@/modules/podcasts/upNext"

import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

/**
 * The menu on an episode row: Play next and Play last (which also move an episode that is
 * already queued) and, for a queued one, Remove from Up Next. Nothing where there is no
 * native player.
 */
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
