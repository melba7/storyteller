// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Clock } from "lucide-react-native"

import { EpisodeListScreen } from "./EpisodeListScreen"
import { useLatest } from "./useEpisodeLists"

/** Library's Latest Episodes: the newest episodes of the shows you follow, not archived. */
export function Latest() {
  return (
    <EpisodeListScreen
      title="Latest Episodes"
      episodes={useLatest()}
      icon={Clock}
      emptyTitle="No episodes yet"
      emptyBody="The newest episodes of the shows you follow appear here."
    />
  )
}
