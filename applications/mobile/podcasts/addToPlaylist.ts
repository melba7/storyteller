import { randomUUID } from "expo-crypto"
// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import {
  addToPlaylist,
  listPlaylists,
  nextPlaylistPosition,
  playlistsHolding,
  savePlaylist,
} from "@/modules/podcasts/dbPlaylists"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { newPlaylist } from "@/modules/podcasts/playlists"

function tell(cause: unknown) {
  Alert.alert("Couldn't add to the playlist", readableError(cause))
}

/** Asks for a name and makes an empty playlist to fill by hand; `then` gets its id. */
export function askNewPlaylist(then: (id: string) => void) {
  Alert.prompt(
    "New playlist",
    "What should it be called?",
    [
      { text: "Cancel", style: "cancel" },
      {
        text: "Create",
        onPress: (name?: string) => {
          const title = name?.trim() ?? ""
          if (title === "") return
          nextPlaylistPosition()
            .then(async (position) => {
              const playlist = {
                ...newPlaylist(randomUUID(), position, Date.now(), "manual"),
                title,
              }
              await savePlaylist(playlist)
              then(playlist.id)
            })
            .catch(tell)
        },
      },
    ],
    "plain-text",
  )
}

/**
 * Asks which of your own playlists an episode goes into (or makes a new one) and adds it. The
 * episode may come from a show you don't follow: enough of it is kept to play it.
 */
export async function chooseAndAddToPlaylist(
  episode: StoredEpisode,
  show: Show | null,
) {
  try {
    const holding = await playlistsHolding(episode.id)
    const mine = (await listPlaylists()).filter((p) => p.kind === "manual")
    const add = (id: string) => addToPlaylist(id, episode, show).catch(tell)
    Alert.alert("Add to playlist", episode.title, [
      ...mine.map((playlist) => ({
        text: holding.has(playlist.id)
          ? `${playlist.title} (already in it)`
          : playlist.title,
        onPress: () => void add(playlist.id),
      })),
      {
        text: "New playlist…",
        onPress: () => askNewPlaylist((id) => void add(id)),
      },
      { text: "Cancel", style: "cancel" as const },
    ])
  } catch (cause) {
    tell(cause)
  }
}
