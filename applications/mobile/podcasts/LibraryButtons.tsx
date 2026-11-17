// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { ListPlus, Star } from "lucide-react-native"
import { Pressable } from "react-native"

import { Icon } from "@/components/ui/icon"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import { player, usePlayerValue } from "@/modules/podcasts/playerInstance"
import { isPreviewId } from "@/modules/podcasts/preview"

import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { useEpisode } from "./hooks"

/**
 * The player's buttons that work on the library: star, and (as they come) add to a playlist
 * and bookmark. Kept in one file so the player's own button row changes by one line.
 */
export function LibraryButtons() {
  const id = usePlayerValue((view) => view.episode?.id ?? "")
  if (id === "") return null
  return (
    <>
      {isPreviewId(id) ? null : <StarButton id={id} />}
      <PlaylistButton />
    </>
  )
}

/** Add what is playing to one of your own playlists, whether or not its show is followed. */
function PlaylistButton() {
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
      accessibilityRole="button"
      accessibilityLabel="Add this episode to a playlist"
      onPress={() => {
        const { episode, show } = player.getView()
        if (episode) void chooseAndAddToPlaylist(episode, show)
      }}
    >
      <Icon as={ListPlus} size={22} className="text-white" />
    </Pressable>
  )
}

function StarButton({ id }: { id: string }) {
  const episode = useEpisode(id).data
  if (!episode) return null
  const starred = episode.starredAt !== null
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
      accessibilityRole="button"
      accessibilityLabel={starred ? "Unstar this episode" : "Star this episode"}
      accessibilityState={{ selected: starred }}
      onPress={() => {
        setStarred([id], !starred).catch((cause: unknown) =>
          console.warn("Couldn't change the episode's star", cause),
        )
      }}
    >
      <Icon
        as={Star}
        size={22}
        className="text-white"
        fill={starred ? "#ffffff" : "none"}
      />
    </Pressable>
  )
}
