// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Bookmark } from "lucide-react-native"

import { EpisodeListScreen } from "./EpisodeListScreen"
import { useStarred } from "./useEpisodeLists"

/** Library's Saved: the episodes you saved (starred), the one saved last first. */
export function Saved() {
  return (
    <EpisodeListScreen
      title="Saved"
      episodes={useStarred()}
      icon={Bookmark}
      emptyTitle="Nothing saved yet"
      emptyBody="Open an episode's menu and choose Save to keep it here."
    />
  )
}
