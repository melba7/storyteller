// LOFI-FORK: the podcasts section's screen (see FORK.md).
import { useLocalSearchParams } from "expo-router"

import { PodcastEpisode } from "@/podcasts/PodcastEpisode"

export default function PodcastEpisodeScreen() {
  const { id } = useLocalSearchParams<{ id: string }>()
  return <PodcastEpisode id={id} />
}
